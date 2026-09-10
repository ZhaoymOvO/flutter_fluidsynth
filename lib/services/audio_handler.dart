import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import '../i18n/i18n_service.dart';
import 'fluidsynth_service.dart';

/// Bridges FluidSynthService to the operating system media controls (Windows SMTC,
/// Android MediaSession & Foreground Service, iOS/macOS Now Playing Info Center).
class FluidAudioHandler extends BaseAudioHandler with SeekHandler {
  final FluidSynthService fluidService;
  final I18nService? i18nService;
  String? _lastTrackPath;
  String? _lastSfName;
  int _lastTotalTicks = -1;

  FluidAudioHandler(this.fluidService, {this.i18nService}) {
    fluidService.addListener(_syncState);
    i18nService?.addListener(_syncState);
    _syncState();
  }

  void _syncState() {
    final currentPath = fluidService.currentMidiPath;
    final isPlaying = fluidService.isPlaying;
    final isStopped = fluidService.playbackState == FluidPlaybackState.stopped;

    // 1. Synchronize MediaItem (Metadata)
    if (currentPath != null && !isStopped) {
      final sfName = fluidService.loadedSfName ?? 'SoundFont';
      final totalTicks = fluidService.totalTicks;

      // Update metadata when track or soundfont changes
      if (_lastTrackPath != currentPath ||
          _lastSfName != sfName ||
          _lastTotalTicks != totalTicks) {
        _lastTrackPath = currentPath;
        _lastSfName = sfName;
        _lastTotalTicks = totalTicks;

        final durationMs = (fluidService.totalTimeInSeconds * 1000).toInt();
        final item = MediaItem(
          id: currentPath,
          album: sfName,
          title: fluidService.currentMidiTitle ?? 'MIDI Track',
          artist: 'SynthBox',
          duration: durationMs > 0 ? Duration(milliseconds: durationMs) : null,
        );
        mediaItem.add(item);
      }
    } else if (isStopped && mediaItem.value != null) {
      _lastTrackPath = null;
      _lastSfName = null;
      _lastTotalTicks = -1;
      mediaItem.add(null);
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
        androidCompactActionIndices: const [1, 2, 3],
        processingState: isStopped
            ? AudioProcessingState.idle
            : AudioProcessingState.ready,
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
  }

  @override
  Future<void> play() async {
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
    fluidService.pause();
  }

  @override
  Future<void> stop() async {
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
    fluidService.stop();
  }
}

/// Initializes the global AudioService across platforms (Android, iOS, macOS, Windows).
Future<AudioHandler?> initAudioService(
  FluidSynthService fluidService, {
  I18nService? i18nService,
}) async {
  try {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        final notifStatus = await Permission.notification.status;
        if (!notifStatus.isGranted) {
          await Permission.notification.request();
        }
      } catch (e) {
        debugPrint('Notification permission error: $e');
      }
    }

    return await AudioService.init(
      builder: () => FluidAudioHandler(fluidService, i18nService: i18nService),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'io.github.zhaoymovo.ffs.audio',
        androidNotificationChannelName: 'SynthBox Playback',
        androidNotificationChannelDescription: 'SynthBox playback controls',
        androidNotificationOngoing: true,
        androidStopForegroundOnPause: true,
        androidNotificationIcon: 'mipmap/ic_launcher',
      ),
    );
  } catch (e) {
    debugPrint('AudioService init exception: $e');
    return null;
  }
}
