import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'fluidsynth_service.dart';

/// Bridges FluidSynthService to the operating system media controls (Windows SMTC,
/// Android MediaSession & Foreground Service, iOS/macOS Now Playing Info Center).
class FluidAudioHandler extends BaseAudioHandler with SeekHandler {
  final FluidSynthService fluidService;
  String? _lastTrackPath;
  String? _lastSfName;
  int _lastTotalTicks = -1;

  FluidAudioHandler(this.fluidService) {
    fluidService.addListener(_syncState);
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
          artist: 'FluidMIDI',
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
    final controls = <MediaControl>[
      MediaControl.skipToPrevious,
      if (isPlaying) MediaControl.pause else MediaControl.play,
      MediaControl.skipToNext,
      MediaControl.stop,
    ];

    final currentPositionMs = (fluidService.currentTimeInSeconds * 1000).toInt();
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
        androidCompactActionIndices: const [0, 1, 2],
        processingState: isStopped
            ? AudioProcessingState.idle
            : AudioProcessingState.ready,
        playing: isPlaying,
        updatePosition: Duration(milliseconds: currentPositionMs.clamp(0, totalDurationMs > 0 ? totalDurationMs : currentPositionMs)),
        bufferedPosition: Duration(milliseconds: totalDurationMs > 0 ? totalDurationMs : currentPositionMs),
        speed: isPlaying ? 1.0 : 0.0,
        repeatMode: fluidService.loopMode == LoopMode.single
            ? AudioServiceRepeatMode.one
            : fluidService.loopMode == LoopMode.playlist
                ? AudioServiceRepeatMode.all
                : AudioServiceRepeatMode.none,
        shuffleMode: fluidService.isShuffle
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
      final index = fluidService.playlistIndex >= 0 ? fluidService.playlistIndex : 0;
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
  Future<void> fastForward([Duration time = const Duration(seconds: 10)]) async {
    fluidService.seekSeconds(fluidService.currentTimeInSeconds + time.inSeconds);
  }

  @override
  Future<void> rewind([Duration time = const Duration(seconds: 10)]) async {
    fluidService.seekSeconds(fluidService.currentTimeInSeconds - time.inSeconds);
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
    final wantShuffle = shuffleMode == AudioServiceShuffleMode.all ||
        shuffleMode == AudioServiceShuffleMode.group;
    if (fluidService.isShuffle != wantShuffle) {
      fluidService.toggleShuffle();
    }
  }

  @override
  Future<void> onTaskRemoved() async {
    fluidService.stop();
  }
}

/// Initializes the global AudioService across platforms (Android, iOS, macOS, Windows).
Future<AudioHandler?> initAudioService(FluidSynthService fluidService) async {
  try {
    return await AudioService.init(
      builder: () => FluidAudioHandler(fluidService),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.ffs.ffs.audio',
        androidNotificationChannelName: 'FluidMIDI Playback',
        androidNotificationChannelDescription: 'FluidMIDI playback controls',
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
