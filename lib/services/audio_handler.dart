import 'dart:async';
import 'dart:io' show Platform, stderr;
import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import '../i18n/i18n_service.dart';
import 'fluidsynth_service.dart';

/// Diagnostic logger for media-control registration.
///
/// Two Flutter behaviours have to be worked around here, because these lines are
/// the primary evidence when the system media controls do not register:
///
///  * On Android the engine maps `print` onto `debugPrint`, which is
///    rate-limited (it silently drops output past a few lines per second), so a
///    long stack trace would be truncated exactly when it matters.
///  * `debugPrint` is itself a hook (`debugPrintOverride`) that tests and
///    debuggers replace, so depending on it alone can lose output.
///
/// `dart:io`'s `stderr` bypasses both wrappers, and the engine forwards it to
/// the platform log in every build mode. `debugPrint` is still emitted in debug
/// builds so the lines surface in the IDE console, but the `stderr` copy is
/// always written. Filter device logs with:
///
///   adb logcat | Select-String "SynthBoxMedia"
void _mediaLog(String message) {
  if (kDebugMode) {
    debugPrint('[SynthBoxMedia] $message');
  }
  stderr.writeln('[SynthBoxMedia] $message');
}

/// Whether the Android 13+ notification permission was observed to be granted.
///
/// When false, the foreground media service still starts but the system silently
/// drops its notification, and Android 11+ derives the Quick Settings media card
/// from that notification — so the media controls never appear. Read by the
/// settings screen to warn the user.
bool androidNotificationPermissionGranted = true;

/// Bridges FluidSynthService to the operating system media controls (Windows SMTC,
/// Android MediaSession & Foreground Service, iOS/macOS Now Playing Info Center).
class FluidAudioHandler extends BaseAudioHandler with SeekHandler {
  final FluidSynthService fluidService;
  final I18nService? i18nService;
  String? _lastTrackPath;
  String? _lastSfName;
  int _lastTotalTicks = -1;
  int _lastDurationMs = -1;

  /// Last progress tick already forwarded to the platform, in seconds.
  int _lastPushedPositionSecond = -1;

  FluidAudioHandler(this.fluidService, {this.i18nService}) {
    fluidService.addListener(_syncState);
    i18nService?.addListener(_syncState);

    // FluidSynthService deliberately updates `progressNotifier` (not
    // `notifyListeners`) on every 100 ms playback tick, so that unrelated UI is
    // not rebuilt. The system media card reads its position from PlaybackState
    // though, and PlaybackState is only pushed on notifyListeners — so without
    // this subscription the card's seek bar receives one position at the moment
    // playback starts and never advances. Re-publishing on the tick keeps the
    // position correct on every ROM, including those that do not interpolate
    // from speed + updateTime.
    fluidService.progressNotifier.addListener(_onProgressTick);

    _syncState();
  }

  /// Forwards FluidSynth progress ticks to the platform as PlaybackState.
  ///
  /// Throttled to one push per whole second: the service ticks every 100 ms but
  /// the media card's seek bar has 1 s resolution, so 10x the channel traffic
  /// would buy nothing visible.
  void _onProgressTick() {
    // Tactical throttle: the tick is 100 ms, the seek bar has 1 s resolution.
    final second = fluidService.currentTimeInSeconds.floor();
    if (second == _lastPushedPositionSecond) return;
    _lastPushedPositionSecond = second;
    _syncState();
  }

  /// Best available track duration in milliseconds, or 0 when unknown.
  ///
  /// [FluidSynthService.totalTimeInSeconds] is derived from the tempo map and
  /// the player's `totalTicks`. Both are 0 until FluidSynth has the file loaded,
  /// so fall back to the elapsed position — a non-zero duration keeps
  /// METADATA_KEY_DURATION present, which is what the media card's seek bar
  /// needs in order to render at all.
  int _resolveDurationMs() {
    final totalMs = (fluidService.totalTimeInSeconds * 1000).toInt();
    if (totalMs > 0) return totalMs;
    final elapsedMs = (fluidService.currentTimeInSeconds * 1000).toInt();
    return elapsedMs > 0 ? elapsedMs : 0;
  }

  void _syncState() {
    final currentPath = fluidService.currentMidiPath;
    final isPlaying = fluidService.isPlaying;
    final isStopped = fluidService.playbackState == FluidPlaybackState.stopped;

    // 1. Synchronize MediaItem (Metadata)
    if (currentPath != null && !isStopped) {
      final sfName = fluidService.loadedSfName ?? 'SoundFont';
      final totalTicks = fluidService.totalTicks;

      // Android draws the media card's seek bar from
      // MediaMetadataCompat.METADATA_KEY_DURATION, and audio_service only writes
      // that key when MediaItem.duration is non-null. A missing key means no
      // seek bar at all, so derive a duration from whatever the service knows
      // rather than publishing null.
      final durationMs = _resolveDurationMs();

      // Update metadata when track, soundfont or duration changes. Duration is
      // part of the signature because FluidSynth reports totalTicks only once
      // the player is running, so the first push of a track often carries
      // duration 0 and must be repaired by a later one.
      if (_lastTrackPath != currentPath ||
          _lastSfName != sfName ||
          _lastTotalTicks != totalTicks ||
          _lastDurationMs != durationMs) {
        _lastTrackPath = currentPath;
        _lastSfName = sfName;
        _lastTotalTicks = totalTicks;
        _lastDurationMs = durationMs;

        final item = MediaItem(
          id: currentPath,
          album: sfName,
          title: fluidService.currentMidiTitle ?? 'MIDI Track',
          artist: 'SynthBox',
          duration: durationMs > 0 ? Duration(milliseconds: durationMs) : null,
        );
        mediaItem.add(item);
        _mediaLog(
          'mediaItem -> "${item.title}" album=$sfName '
          'duration=${item.duration} (totalTicks=$totalTicks)',
        );
      }
    } else if (isStopped && mediaItem.value != null) {
      _lastTrackPath = null;
      _lastSfName = null;
      _lastTotalTicks = -1;
      _lastDurationMs = -1;
      mediaItem.add(null);
      _mediaLog('mediaItem -> null (playback stopped)');
    }

    // 2. Synchronize PlaybackState
    final isShuffle = fluidService.isShuffle;
    final loopMode = fluidService.loopMode;

    final shuffleControl = MediaControl.custom(
      androidIcon: isShuffle
          ? 'drawable/ic_shuffle_on'
          : 'drawable/ic_shuffle_off',
      label: isShuffle
          ? (i18nService?.t('player_btn_shuffle_on') ?? '隨機播放：開啟')
          : (i18nService?.t('player_btn_shuffle_off') ?? '隨機播放：關閉'),
      name: 'toggleShuffle',
    );

    final repeatControl = MediaControl.custom(
      androidIcon: loopMode == LoopMode.single
          ? 'drawable/ic_repeat_one'
          : loopMode == LoopMode.playlist
          ? 'drawable/ic_repeat_all'
          : 'drawable/ic_repeat_none',
      label: loopMode == LoopMode.single
          ? (i18nService?.t('player_loop_single') ?? '循環模式：單曲循環')
          : loopMode == LoopMode.playlist
          ? (i18nService?.t('player_loop_playlist') ?? '循環模式：列表循環')
          : (i18nService?.t('player_loop_none') ?? '循環模式：不循環'),
      name: 'toggleLoop',
    );

    // Standard 5-button layout: [Shuffle] [Prev] [Play/Pause] [Next] [Loop]
    // Android AudioService filters out custom actions (toggleShuffle, toggleLoop) into customActions,
    // leaving exactly 3 native actions: [0: Prev, 1: Play/Pause, 2: Next].
    // Thus androidCompactActionIndices MUST be [0, 1, 2] to match the 3 native actions without index out of bounds.
    final controls = <MediaControl>[
      shuffleControl,
      MediaControl.skipToPrevious,
      if (isPlaying) MediaControl.pause else MediaControl.play,
      MediaControl.skipToNext,
      repeatControl,
    ];

    final currentPositionMs = (fluidService.currentTimeInSeconds * 1000)
        .toInt();
    final totalDurationMs = (fluidService.totalTimeInSeconds * 1000).toInt();

    // IMPORTANT — MediaSession lifetime.
    //
    // `AudioProcessingState.idle` does NOT mean "playback stopped", it means
    // "this app no longer has a media session". On the native side, sending
    // `idle` after any non-idle state calls AudioService.stop(), which runs
    // deactivateMediaSession(): mediaSession.setActive(false) plus
    // NotificationManager.cancel(). Android 11+ renders the Quick Settings and
    // lock screen media card only for an ACTIVE MediaSession backed by a live
    // MediaStyle notification, so every `idle` we send tears the system media
    // controls down.
    //
    // A stopped-but-loaded track must therefore stay `ready` with
    // `playing: false`. Report `idle` only when nothing is loaded at all, which
    // is the one case where releasing the session is correct.
    final hasContent = currentPath != null;
    final processingState = hasContent
        ? AudioProcessingState.ready
        : AudioProcessingState.idle;

    playbackState.add(
      PlaybackState(
        controls: controls,
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
          MediaAction.setShuffleMode,
          MediaAction.setRepeatMode,
        },
        androidCompactActionIndices: const [0, 1, 2],
        processingState: processingState,
        playing: isPlaying,
        updatePosition: Duration(
          milliseconds: currentPositionMs.clamp(
            0,
            totalDurationMs > 0 ? totalDurationMs : currentPositionMs,
          ),
        ),
        bufferedPosition: Duration(
          milliseconds: totalDurationMs > 0
              ? totalDurationMs
              : currentPositionMs,
        ),
        speed: isPlaying ? 1.0 : 0.0,
        repeatMode: loopMode == LoopMode.single
            ? AudioServiceRepeatMode.one
            : loopMode == LoopMode.playlist
            ? AudioServiceRepeatMode.all
            : AudioServiceRepeatMode.none,
        shuffleMode: isShuffle
            ? AudioServiceShuffleMode.all
            : AudioServiceShuffleMode.none,
      ),
    );

    // Trace every state pushed to the platform layer. This is the line that
    // decides whether the native AudioService activates the MediaSession
    // (`playing` false -> true) and whether it stays parked at `idle` (which
    // makes it release the session and cancel the notification instead).
    // position/duration are included because a null duration drops
    // METADATA_KEY_DURATION on the native side, which removes the media card's
    // seek bar entirely.
    _mediaLog(
      'playbackState -> processing=$processingState playing=$isPlaying '
      'controls=${controls.length} compact=[0,1,2] '
      'pos=${currentPositionMs}ms dur=${totalDurationMs}ms speed='
      '${isPlaying ? 1.0 : 0.0} track=${currentPath ?? "none"}',
    );
  }

  @override
  Future<void> play() async {
    _mediaLog('handler.play() called');
    if (fluidService.isPaused) {
      fluidService.resume();
    } else if (fluidService.currentMidiPath != null) {
      await fluidService.playMidi(fluidService.currentMidiPath!);
    } else if (fluidService.playlist.isNotEmpty) {
      final index = fluidService.playlistIndex >= 0
          ? fluidService.playlistIndex
          : 0;
      await fluidService.playPlaylistItem(index);
    }
  }

  @override
  Future<void> pause() async {
    _mediaLog('handler.pause() called');
    fluidService.pause();
  }

  @override
  Future<void> stop() async {
    _mediaLog('handler.stop() called');
    fluidService.stop();
  }

  @override
  Future<void> skipToNext() async {
    await fluidService.playNext();
  }

  @override
  Future<void> skipToPrevious() async {
    await fluidService.playPrevious();
  }

  @override
  Future<void> seek(Duration position) async {
    fluidService.seekSeconds(position.inMilliseconds / 1000.0);
  }

  @override
  Future<void> fastForward([
    Duration time = const Duration(seconds: 10),
  ]) async {
    fluidService.seekSeconds(
      fluidService.currentTimeInSeconds + time.inSeconds,
    );
  }

  @override
  Future<void> rewind([Duration time = const Duration(seconds: 10)]) async {
    fluidService.seekSeconds(
      fluidService.currentTimeInSeconds - time.inSeconds,
    );
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    switch (repeatMode) {
      case AudioServiceRepeatMode.none:
        fluidService.setLoopMode(LoopMode.none);
        break;
      case AudioServiceRepeatMode.one:
        fluidService.setLoopMode(LoopMode.single);
        break;
      case AudioServiceRepeatMode.all:
      case AudioServiceRepeatMode.group:
        fluidService.setLoopMode(LoopMode.playlist);
        break;
    }
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    final wantShuffle =
        shuffleMode == AudioServiceShuffleMode.all ||
        shuffleMode == AudioServiceShuffleMode.group;
    if (fluidService.isShuffle != wantShuffle) {
      fluidService.toggleShuffle();
    }
  }

  @override
  Future<dynamic> customAction(
    String name, [
    Map<String, dynamic>? extras,
  ]) async {
    switch (name) {
      case 'toggleShuffle':
        fluidService.toggleShuffle();
        break;
      case 'toggleLoop':
        fluidService.cycleLoopMode();
        break;
      default:
        return super.customAction(name, extras);
    }
  }

  @override
  Future<void> onTaskRemoved() async {
    // Note: this fires when the user swipes the app out of Recents, not when
    // playback ends. Stopping here means background playback cannot outlive the
    // task, which is why a swipe in Recents also removes the system media card.
    _mediaLog('handler.onTaskRemoved() called - stopping playback');
    fluidService.stop();
  }
}

/// Reads the Android 13+ notification permission *before* the media service
/// starts.
///
/// The foreground service may start without this permission, but the system then
/// suppresses its notification — and Android 11+ builds the Quick Settings media
/// card from that notification. A denied permission is therefore
/// indistinguishable from "the media controls never register".
///
/// This deliberately does NOT call `request()`. Only one permission UI can be in
/// flight at a time, and the storage request ("All files access", a system
/// settings screen rather than a dialog) is sequenced ahead of this call from
/// `main.dart`. A second requester here made one of the two silently lose, which
/// left the file browser without storage access on first launch.
Future<void> _ensureAndroidNotificationPermission() async {
  if (kIsWeb || !Platform.isAndroid) return;

  try {
    final status = await Permission.notification.status;
    androidNotificationPermissionGranted = status.isGranted;
    _mediaLog(
      'POST_NOTIFICATIONS status=$status granted=$androidNotificationPermissionGranted',
    );
    if (!androidNotificationPermissionGranted) {
      _mediaLog(
        'WARNING: notifications not granted. The Android media card is derived '
        'from the media notification and will NOT appear until notifications '
        'are enabled for this app in system settings.',
      );
    }
  } catch (e) {
    _mediaLog('POST_NOTIFICATIONS check failed: $e');
  }
}

/// Initializes the global AudioService across platforms (Android, iOS, macOS, Windows).
///
/// Returns null when initialization fails. Failures are logged loudly, because a
/// silent failure here is exactly what "the system media controls never appear"
/// looks like from the outside.
Future<AudioHandler?> initAudioService(
  FluidSynthService fluidService, {
  I18nService? i18nService,
}) async {
  try {
    _mediaLog(
      'initAudioService() begin (platform=$defaultTargetPlatform)',
    );
    await _ensureAndroidNotificationPermission();

    final handler = await AudioService.init(
      builder: () => FluidAudioHandler(fluidService, i18nService: i18nService),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'io.github.zhaoymovo.ffs.audio',
        androidNotificationChannelName: 'SynthBox Playback',
        androidNotificationChannelDescription: 'SynthBox playback controls',
        // Keep the media session alive while paused. With this set to true the
        // foreground service — and with it the Android 11+ media card — is torn
        // down on every pause, which makes registration look intermittent.
        //
        // androidNotificationOngoing must stay false: AudioServiceConfig asserts
        // `!androidNotificationOngoing || androidStopForegroundOnPause`, so the
        // two flags cannot be combined. Ongoing only matters while the service
        // is foregrounded, and a foreground service already forces its
        // notification to be non-dismissable.
        androidStopForegroundOnPause: false,
        androidNotificationOngoing: false,
        // Must be a flat monochrome silhouette. The colorised launcher icon is
        // rendered as an opaque blob or dropped entirely by several ROMs.
        androidNotificationIcon: 'drawable/ic_stat_synthbox',
      ),
    );

    _mediaLog(
      'AudioService.init OK - media session registered '
      '(platform=$defaultTargetPlatform)',
    );
    return handler;
  } catch (e, st) {
    _mediaLog('AudioService.init FAILED: $e');
    _mediaLog('$st');
    return null;
  }
}
