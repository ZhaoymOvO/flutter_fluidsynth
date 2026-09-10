import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import '../ffi/fluidsynth_bindings.dart';
import '../ffi/fluidsynth_loader.dart';
import 'midi_parser.dart';

enum PlaybackState {
  stopped,
  playing,
  paused,
}

enum LoopMode {
  none,      // 不循環 (播完清單或單曲後停止)
  playlist,  // 列表循環 (播完最後一首回到第一首)
  single,    // 單曲循環 (單曲無限重複)
}

class FluidSynthService extends ChangeNotifier {
  static const String _prefAudioDriverKey = 'fluidsynth_audio_driver';
  static const String _prefVolumeKey = 'fluidsynth_volume';

  FluidSynthBindings? _bindings;
  Pointer<FluidSettings>? _settings;
  Pointer<FluidSynth>? _synth;
  Pointer<FluidAudioDriver>? _audioDriver;
  Pointer<FluidPlayer>? _player;

  bool _isLibraryLoaded = false;
  String? _loadedLibraryPath;
  String? _libraryVersion;
  String? _loadError;

  int? _loadedSfId;
  String? _loadedSfPath;

  String? _currentMidiPath;
  String? _currentMidiTitle;
  PlaybackState _playbackState = PlaybackState.stopped;

  List<String> _playlist = [];
  int _playlistIndex = -1;
  LoopMode _loopMode = LoopMode.playlist;
  bool _isShuffle = false;
  final List<int> _shuffleHistory = [];
  final math.Random _random = math.Random();

  int _currentTick = 0;
  int _totalTicks = 0;
  int _bpm = 120;
  int _division = 480;
  MidiFileInfo? _midiInfo;
  double _volume = 0.8;
  String _audioDriverName = 'auto';

  Timer? _progressTimer;

  // Getters
  bool get isLibraryLoaded => _isLibraryLoaded;
  String? get loadedLibraryPath => _loadedLibraryPath;
  String? get libraryVersion => _libraryVersion;
  String? get loadError => _loadError;

  int? get loadedSfId => _loadedSfId;
  String? get loadedSfPath => _loadedSfPath;
  String? get loadedSfName => _loadedSfPath != null ? p.basename(_loadedSfPath!) : null;
  bool get hasLoadedSoundFont => _loadedSfId != null && _loadedSfId! >= 0;

  String? get currentMidiPath => _currentMidiPath;
  String? get currentMidiTitle => _currentMidiTitle;
  PlaybackState get playbackState => _playbackState;
  bool get isPlaying => _playbackState == PlaybackState.playing;
  bool get isPaused => _playbackState == PlaybackState.paused;

  List<String> get playlist => List.unmodifiable(_playlist);
  int get playlistIndex => _playlistIndex;
  LoopMode get loopMode => _loopMode;
  bool get isShuffle => _isShuffle;
  bool get isLooping => _loopMode != LoopMode.none;

  bool get hasNext {
    if (_playlist.isEmpty) return false;
    if (_isShuffle) return _playlist.length > 1;
    if (_loopMode == LoopMode.playlist) return true;
    return _playlistIndex < _playlist.length - 1;
  }

  bool get hasPrevious {
    if (_playlist.isEmpty) return false;
    if (_isShuffle) return _shuffleHistory.isNotEmpty || _playlist.length > 1;
    if (_loopMode == LoopMode.playlist) return true;
    return _playlistIndex > 0;
  }

  int get currentTick => _currentTick;
  int get totalTicks => _totalTicks;
  int get bpm => _bpm;
  int get division => _division;
  double get volume => _volume;
  String get audioDriverName => _audioDriverName;

  /// Current playback position in seconds (calculated accurately using tempo map)
  double get currentTimeInSeconds {
    if (_midiInfo != null) {
      return _midiInfo!.tickToSeconds(_currentTick);
    }
    if (_division > 0 && _bpm > 0) {
      return (_currentTick * 60.0) / (_bpm * _division);
    }
    return 0.0;
  }

  /// Total duration of track in seconds (calculated accurately using tempo map)
  double get totalTimeInSeconds {
    if (_midiInfo != null) {
      return _midiInfo!.tickToSeconds(_totalTicks);
    }
    if (_division > 0 && _bpm > 0) {
      return (_totalTicks * 60.0) / (_bpm * _division);
    }
    return 0.0;
  }

  String get formattedCurrentTime => formatDuration(currentTimeInSeconds);
  String get formattedTotalTime => formatDuration(totalTimeInSeconds);

  static String formatDuration(double seconds) {
    if (seconds.isNaN || seconds.isInfinite || seconds <= 0) return '0:00';
    final total = seconds.floor();
    final m = total ~/ 60;
    final s = total % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  /// Available audio drivers per platform
  List<String> get availableAudioDrivers {
    if (Platform.isMacOS || Platform.isIOS) {
      return ['auto', 'coreaudio', 'portaudio', 'file'];
    } else if (Platform.isWindows) {
      return ['auto', 'wasapi', 'dsound', 'waveout', 'portaudio', 'file'];
    } else if (Platform.isLinux) {
      return ['auto', 'pulseaudio', 'alsa', 'jack', 'portaudio', 'file'];
    } else if (Platform.isAndroid) {
      return ['auto', 'oboe', 'opensles', 'file'];
    }
    return ['auto', 'file'];
  }

  /// Initialize FluidSynth subsystem
  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    _audioDriverName = prefs.getString(_prefAudioDriverKey) ?? 'auto';
    _volume = prefs.getDouble(_prefVolumeKey) ?? 0.8;

    await _loadLibraryAndInitEngine();
  }

  /// Sideload a user-provided dynamic library file
  Future<bool> sideloadLibrary(String filePath) async {
    await _teardownEngine();
    await FluidSynthLoader.saveSideloadedPath(filePath);

    final result = await FluidSynthLoader.load(customPath: filePath);
    if (!result.isSuccess) {
      _isLibraryLoaded = false;
      _loadError = result.errorMessage;
      notifyListeners();
      return false;
    }

    _bindings = result.bindings;
    _loadedLibraryPath = result.loadedPath;
    _libraryVersion = result.version;
    _isLibraryLoaded = true;
    _loadError = null;

    final initOk = _initEngine();
    notifyListeners();
    return initOk;
  }

  /// Reset to bundled/default library
  Future<void> resetToDefaultLibrary() async {
    await _teardownEngine();
    await FluidSynthLoader.clearSideloadedPath();
    await _loadLibraryAndInitEngine();
  }

  /// Change audio driver
  Future<void> setAudioDriver(String driverName) async {
    if (_audioDriverName == driverName) return;
    _audioDriverName = driverName;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefAudioDriverKey, driverName);

    if (_isLibraryLoaded) {
      // Re-init audio driver and synth with new driver setting
      final currentSf = _loadedSfPath;
      await _teardownEngine();
      _initEngine();
      if (currentSf != null) {
        await loadSoundFont(currentSf);
      }
      notifyListeners();
    }
  }

  Future<void> _loadLibraryAndInitEngine() async {
    final result = await FluidSynthLoader.load();
    if (!result.isSuccess) {
      _isLibraryLoaded = false;
      _loadError = result.errorMessage;
      notifyListeners();
      return;
    }

    _bindings = result.bindings;
    _loadedLibraryPath = result.loadedPath;
    _libraryVersion = result.version;
    _isLibraryLoaded = true;
    _loadError = null;

    _initEngine();
    notifyListeners();
  }

  bool _initEngine() {
    if (_bindings == null) return false;

    try {
      final b = _bindings!;
      _settings = b.newFluidSettings();
      if (_settings == null || _settings == nullptr) {
        _loadError = 'Failed to allocate fluid_settings';
        return false;
      }

      // Configure audio driver if not 'auto'
      if (_audioDriverName != 'auto') {
        final driverKey = 'audio.driver'.toNativeUtf8();
        final driverVal = _audioDriverName.toNativeUtf8();
        b.fluidSettingsSetStr(_settings!, driverKey, driverVal);
        calloc.free(driverKey);
        calloc.free(driverVal);
      }

      // Configure sample rate & polyphony
      final srKey = 'synth.sample-rate'.toNativeUtf8();
      b.fluidSettingsSetNum(_settings!, srKey, 44100.0);
      calloc.free(srKey);

      final polyKey = 'synth.polyphony'.toNativeUtf8();
      b.fluidSettingsSetInt(_settings!, polyKey, 256);
      calloc.free(polyKey);

      // Create synth
      _synth = b.newFluidSynth(_settings!);
      if (_synth == null || _synth == nullptr) {
        _loadError = 'Failed to create fluid_synth';
        return false;
      }

      // Set initial gain
      b.fluidSynthSetGain(_synth!, (_volume * 2.0));

      // Create audio driver
      _audioDriver = b.newFluidAudioDriver(_settings!, _synth!);
      if (_audioDriver == null || _audioDriver == nullptr) {
        debugPrint('Warning: new_fluid_audio_driver returned null. Driver may be unavailable.');
      }

      return true;
    } catch (e) {
      _loadError = 'Exception initializing FluidSynth engine: $e';
      debugPrint(_loadError);
      return false;
    }
  }

  Future<void> _teardownEngine() async {
    _stopProgressTimer();
    _playbackState = PlaybackState.stopped;

    final b = _bindings;
    if (b != null) {
      if (_player != null && _player != nullptr) {
        try {
          b.fluidPlayerStop(_player!);
          b.deleteFluidPlayer(_player!);
        } catch (_) {}
        _player = null;
      }

      if (_loadedSfId != null && _loadedSfId! >= 0 && _synth != null && _synth != nullptr) {
        try {
          b.fluidSynthSfUnload(_synth!, _loadedSfId!, 1);
        } catch (_) {}
        _loadedSfId = null;
        _loadedSfPath = null;
      }

      if (_audioDriver != null && _audioDriver != nullptr) {
        try {
          b.deleteFluidAudioDriver(_audioDriver!);
        } catch (_) {}
        _audioDriver = null;
      }

      if (_synth != null && _synth != nullptr) {
        try {
          b.deleteFluidSynth(_synth!);
        } catch (_) {}
        _synth = null;
      }

      if (_settings != null && _settings != nullptr) {
        try {
          b.deleteFluidSettings(_settings!);
        } catch (_) {}
        _settings = null;
      }
    }
  }

  /// Converts a path to an 8.3 short path on Windows if needed, ensuring C standard library
  /// `fopen(path, "rb")` succeeds when paths contain non-ASCII characters (e.g. CJK/Japanese).
  static String _toNativePath(String path) {
    if (!Platform.isWindows) return path;
    try {
      final kernel32 = DynamicLibrary.open('kernel32.dll');
      final getShortPathName = kernel32.lookupFunction<
          Uint32 Function(Pointer<Utf16>, Pointer<Utf16>, Uint32),
          int Function(Pointer<Utf16>, Pointer<Utf16>, int)>('GetShortPathNameW');
      final pathPtr = path.toNativeUtf16();
      final buf = calloc<Uint16>(1024).cast<Utf16>();
      try {
        final len = getShortPathName(pathPtr, buf, 1024);
        if (len > 0) {
          return buf.toDartString();
        }
      } finally {
        calloc.free(pathPtr);
        calloc.free(buf);
      }
    } catch (e) {
      debugPrint('GetShortPathNameW fallback: $e');
    }
    return path;
  }

  /// Loads a SoundFont file into the active synthesizer
  Future<bool> loadSoundFont(String rawFilePath) async {
    if (_bindings == null || _synth == null || _synth == nullptr) {
      return false;
    }

    final filePath = p.normalize(rawFilePath);
    final file = File(filePath);
    if (!await file.exists()) {
      return false;
    }

    final b = _bindings!;

    // Unload previous SoundFont if one was loaded
    if (_loadedSfId != null && _loadedSfId! >= 0) {
      try {
        b.fluidSynthSfUnload(_synth!, _loadedSfId!, 1);
      } catch (e) {
        debugPrint('Error unloading previous SoundFont: $e');
      }
      _loadedSfId = null;
      _loadedSfPath = null;
    }

    final nativePath = _toNativePath(filePath);
    final pathPtr = nativePath.toNativeUtf8();
    final sfId = b.fluidSynthSfLoad(_synth!, pathPtr, 1);
    calloc.free(pathPtr);

    if (sfId < 0) {
      debugPrint('fluid_synth_sfload failed for $filePath with code $sfId');
      return false;
    }

    _loadedSfId = sfId;
    _loadedSfPath = filePath;

    // If a MIDI track is currently playing, silence active notes and seek to current tick so new soundfont presets take effect cleanly
    if (_player != null && _player != nullptr && _playbackState == PlaybackState.playing) {
      b.fluidSynthAllSoundsOff(_synth!, -1);
      final tick = b.fluidPlayerGetCurrentTick(_player!);
      b.fluidPlayerSeek(_player!, tick);
    }

    notifyListeners();
    return true;
  }

  /// Unload current SoundFont
  Future<void> unloadSoundFont() async {
    if (_bindings != null && _synth != null && _synth != nullptr && _loadedSfId != null && _loadedSfId! >= 0) {
      try {
        _bindings!.fluidSynthSfUnload(_synth!, _loadedSfId!, 1);
      } catch (e) {
        debugPrint('Error unloading SoundFont: $e');
      }
      _loadedSfId = null;
      _loadedSfPath = null;
      notifyListeners();
    }
  }

  /// Start playing a MIDI file
  Future<bool> playMidi(String rawMidiPath) async {
    if (_bindings == null || _synth == null || _synth == nullptr) {
      return false;
    }

    final midiPath = p.normalize(rawMidiPath);
    final file = File(midiPath);
    if (!await file.exists()) {
      return false;
    }

    final b = _bindings!;

    // Stop and delete previous player if exists
    if (_player != null && _player != nullptr) {
      b.fluidPlayerStop(_player!);
      b.fluidPlayerJoin(_player!);
      b.deleteFluidPlayer(_player!);
      _player = null;
    }

    // Completely cut off all voices, release tails, and lingering notes from previous song
    b.fluidSynthAllSoundsOff(_synth!, -1);
    b.fluidSynthAllNotesOff(_synth!, -1);
    b.fluidSynthSystemReset(_synth!);
    b.fluidSynthSetGain(_synth!, (_volume * 2.0));

    _player = b.newFluidPlayer(_synth!);
    if (_player == null || _player == nullptr) {
      debugPrint('Failed to create new_fluid_player');
      return false;
    }

    final nativePath = _toNativePath(midiPath);
    final pathPtr = nativePath.toNativeUtf8();
    final addRes = b.fluidPlayerAdd(_player!, pathPtr);
    calloc.free(pathPtr);

    if (addRes != 0) {
      debugPrint('fluid_player_add returned $addRes');
      return false;
    }

    // Configure loop: -1 for infinite loop, 1 for single play
    b.fluidPlayerSetLoop(_player!, _loopMode == LoopMode.single ? -1 : 1);

    final playRes = b.fluidPlayerPlay(_player!);
    if (playRes != 0) {
      debugPrint('fluid_player_play returned $playRes');
      return false;
    }

    _currentMidiPath = midiPath;
    _currentMidiTitle = p.basename(midiPath);
    _playbackState = PlaybackState.playing;

    final existingIdx =
        _playlist.indexWhere((pItem) => p.equals(pItem, midiPath));
    if (existingIdx >= 0) {
      _playlistIndex = existingIdx;
    } else {
      _playlist = [midiPath];
      _playlistIndex = 0;
      _shuffleHistory.clear();
      _shuffleHistory.add(0);
    }

    _midiInfo = await MidiFileInfo.parseFile(midiPath);
    _division = _midiInfo?.division ?? 480;
    try {
      final div = b.fluidPlayerGetDivision(_player!);
      if (div > 0) _division = div;
    } catch (_) {}

    _totalTicks = b.fluidPlayerGetTotalTicks(_player!);
    _bpm = b.fluidPlayerGetBpm(_player!);
    _currentTick = 0;

    _startProgressTimer();
    notifyListeners();
    return true;
  }

  /// Pause current playback
  void pause() {
    if (_bindings == null || _player == null || _player == nullptr) return;
    if (_playbackState != PlaybackState.playing) return;

    final b = _bindings!;
    _currentTick = b.fluidPlayerGetCurrentTick(_player!);
    b.fluidPlayerStop(_player!);
    b.fluidPlayerJoin(_player!);
    if (_synth != null && _synth != nullptr) {
      b.fluidSynthAllSoundsOff(_synth!, -1);
      b.fluidSynthAllNotesOff(_synth!, -1);
    }
    _playbackState = PlaybackState.paused;
    _stopProgressTimer();
    notifyListeners();
  }

  /// Resume playback from paused position
  void resume() {
    if (_bindings == null || _player == null || _player == nullptr) return;
    if (_playbackState != PlaybackState.paused) return;

    final b = _bindings!;
    b.fluidPlayerSeek(_player!, _currentTick);
    b.fluidPlayerPlay(_player!);
    _playbackState = PlaybackState.playing;
    _startProgressTimer();
    notifyListeners();
  }

  /// Stop playback
  void stop() {
    _stopProgressTimer();
    if (_bindings != null) {
      final b = _bindings!;
      if (_player != null && _player != nullptr) {
        b.fluidPlayerStop(_player!);
        b.fluidPlayerJoin(_player!);
        b.deleteFluidPlayer(_player!);
        _player = null;
      }
      if (_synth != null && _synth != nullptr) {
        b.fluidSynthAllSoundsOff(_synth!, -1);
        b.fluidSynthAllNotesOff(_synth!, -1);
        b.fluidSynthSystemReset(_synth!);
        b.fluidSynthSetGain(_synth!, (_volume * 2.0));
      }
    }
    _playbackState = PlaybackState.stopped;
    _currentTick = 0;
    notifyListeners();
  }

  /// Seek to a tick position
  void seek(int tick) {
    if (_bindings == null || _player == null || _player == nullptr) return;
    final b = _bindings!;
    final target = tick.clamp(0, _totalTicks);
    b.fluidPlayerSeek(_player!, target);
    _currentTick = target;
    notifyListeners();
  }

  /// Set playlist of MIDI files
  void setPlaylist(List<String> paths, {int initialIndex = 0}) {
    _playlist = List<String>.from(paths);
    _playlistIndex = _playlist.isEmpty ? -1 : initialIndex.clamp(0, _playlist.length - 1);
    _shuffleHistory.clear();
    if (_playlistIndex >= 0) {
      _shuffleHistory.add(_playlistIndex);
    }
    notifyListeners();
  }

  /// Cycle through loop modes: none -> playlist -> single -> none
  void cycleLoopMode() {
    switch (_loopMode) {
      case LoopMode.none:
        _loopMode = LoopMode.playlist;
        break;
      case LoopMode.playlist:
        _loopMode = LoopMode.single;
        break;
      case LoopMode.single:
        _loopMode = LoopMode.none;
        break;
    }
    if (_bindings != null && _player != null && _player != nullptr) {
      _bindings!.fluidPlayerSetLoop(_player!, _loopMode == LoopMode.single ? -1 : 1);
    }
    notifyListeners();
  }

  /// Explicitly set loop mode
  void setLoopMode(LoopMode mode) {
    _loopMode = mode;
    if (_bindings != null && _player != null && _player != nullptr) {
      _bindings!.fluidPlayerSetLoop(_player!, _loopMode == LoopMode.single ? -1 : 1);
    }
    notifyListeners();
  }

  /// Backward-compatible setLoop
  void setLoop(bool loop) {
    setLoopMode(loop ? LoopMode.playlist : LoopMode.none);
  }

  /// Toggle shuffle mode
  void toggleShuffle() {
    _isShuffle = !_isShuffle;
    _shuffleHistory.clear();
    if (_playlistIndex >= 0 && _playlistIndex < _playlist.length) {
      _shuffleHistory.add(_playlistIndex);
    }
    notifyListeners();
  }

  /// Play next track in playlist
  Future<bool> playNext({bool autoAdvance = false}) async {
    if (_playlist.isEmpty) {
      if (autoAdvance) stop();
      return false;
    }

    if (_isShuffle) {
      if (_playlist.length == 1) {
        if (_loopMode == LoopMode.none && autoAdvance) {
          stop();
          return false;
        }
        return playMidi(_playlist[0]);
      }
      int nextIdx;
      do {
        nextIdx = _random.nextInt(_playlist.length);
      } while (nextIdx == _playlistIndex && _playlist.length > 1);

      _playlistIndex = nextIdx;
      _shuffleHistory.add(nextIdx);
      return playMidi(_playlist[_playlistIndex]);
    }

    // Sequential next
    if (_playlistIndex < _playlist.length - 1) {
      _playlistIndex++;
      return playMidi(_playlist[_playlistIndex]);
    } else {
      // Reached the end of playlist
      if (_loopMode == LoopMode.playlist) {
        _playlistIndex = 0;
        return playMidi(_playlist[0]);
      } else {
        if (autoAdvance) {
          stop();
        }
        return false;
      }
    }
  }

  /// Play previous track in playlist
  Future<bool> playPrevious() async {
    if (_playlist.isEmpty) return false;

    // If more than 3 seconds into current track, restart current track from beginning
    if (currentTimeInSeconds > 3.0) {
      seek(0);
      return true;
    }

    if (_isShuffle) {
      if (_shuffleHistory.length > 1) {
        _shuffleHistory.removeLast(); // pop current
        _playlistIndex = _shuffleHistory.last;
        return playMidi(_playlist[_playlistIndex]);
      } else {
        return playMidi(_playlist[_playlistIndex]);
      }
    }

    // Sequential previous
    if (_playlistIndex > 0) {
      _playlistIndex--;
      return playMidi(_playlist[_playlistIndex]);
    } else {
      if (_loopMode == LoopMode.playlist) {
        _playlistIndex = _playlist.length - 1;
        return playMidi(_playlist[_playlistIndex]);
      } else {
        seek(0);
        return true;
      }
    }
  }

  /// Add a track to playlist to be played next (immediately after current index)
  void addToPlaylistNext(String path) {
    final existingIdx = _playlist.indexOf(path);
    if (existingIdx == _playlistIndex && existingIdx >= 0) {
      // Currently playing this track already
      return;
    }
    if (existingIdx >= 0) {
      _playlist.removeAt(existingIdx);
      if (existingIdx < _playlistIndex) {
        _playlistIndex--;
      }
    }
    if (_playlist.isEmpty) {
      _playlist.add(path);
      _playlistIndex = 0;
    } else if (_playlistIndex >= 0 && _playlistIndex < _playlist.length) {
      _playlist.insert(_playlistIndex + 1, path);
    } else {
      _playlist.add(path);
      _playlistIndex = 0;
    }
    notifyListeners();
  }

  /// Remove a track from playlist at index
  void removeFromPlaylist(int index) {
    if (index < 0 || index >= _playlist.length) return;
    final isRemovingCurrent = (index == _playlistIndex);
    _playlist.removeAt(index);
    if (_playlist.isEmpty) {
      _playlistIndex = -1;
      _shuffleHistory.clear();
      if (isRemovingCurrent) {
        stop();
      }
    } else if (index < _playlistIndex) {
      _playlistIndex--;
    } else if (_playlistIndex >= _playlist.length) {
      _playlistIndex = _playlist.length - 1;
    }
    notifyListeners();
  }

  /// Reorder items in playlist
  void reorderPlaylist(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _playlist.length) return;
    if (newIndex < 0 || newIndex > _playlist.length) return;
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    final currentItem = (_playlistIndex >= 0 && _playlistIndex < _playlist.length)
        ? _playlist[_playlistIndex]
        : null;

    final item = _playlist.removeAt(oldIndex);
    _playlist.insert(newIndex, item);

    if (currentItem != null) {
      _playlistIndex = _playlist.indexOf(currentItem);
    }
    notifyListeners();
  }

  /// Clear the playlist
  void clearPlaylist() {
    _playlist.clear();
    _playlistIndex = -1;
    _shuffleHistory.clear();
    notifyListeners();
  }

  /// Play a specific item in the playlist by index
  Future<bool> playPlaylistItem(int index) async {
    if (index < 0 || index >= _playlist.length) return false;
    _playlistIndex = index;
    if (_isShuffle) {
      _shuffleHistory.add(index);
    }
    return playMidi(_playlist[index]);
  }

  /// Set volume / master gain (0.0 to 1.0)
  void setVolume(double vol) {
    _volume = vol.clamp(0.0, 1.0);
    if (_bindings != null && _synth != null && _synth != nullptr) {
      _bindings!.fluidSynthSetGain(_synth!, (_volume * 2.0));
    }
    notifyListeners();
    SharedPreferences.getInstance().then((prefs) {
      prefs.setDouble(_prefVolumeKey, _volume);
    }).catchError((_) {});
  }

  /// Test sound: Plays a middle C (60) note with velocity 100 for 400ms
  Future<bool> testNote() async {
    if (_bindings == null || _synth == null || _synth == nullptr) {
      return false;
    }
    final b = _bindings!;
    try {
      b.fluidSynthNoteOn(_synth!, 0, 60, 100);
      Future.delayed(const Duration(milliseconds: 400), () {
        if (_synth != null && _synth != nullptr) {
          b.fluidSynthNoteOff(_synth!, 0, 60);
        }
      });
      return true;
    } catch (e) {
      debugPrint('testNote error: $e');
      return false;
    }
  }

  void _startProgressTimer() {
    _stopProgressTimer();
    _progressTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (_bindings != null && _player != null && _player != nullptr) {
        final b = _bindings!;
        final status = b.fluidPlayerGetStatus(_player!);
        _currentTick = b.fluidPlayerGetCurrentTick(_player!);
        _totalTicks = b.fluidPlayerGetTotalTicks(_player!);
        _bpm = b.fluidPlayerGetBpm(_player!);
        try {
          final div = b.fluidPlayerGetDivision(_player!);
          if (div > 0) _division = div;
        } catch (_) {}

        if (status == FluidPlayerStatus.done) {
          if (_loopMode == LoopMode.single) {
            if (_currentMidiPath != null) {
              playMidi(_currentMidiPath!);
            }
          } else {
            playNext(autoAdvance: true);
          }
        }
        notifyListeners();
      }
    });
  }

  void _stopProgressTimer() {
    _progressTimer?.cancel();
    _progressTimer = null;
  }

  @override
  void dispose() {
    _stopProgressTimer();
    _teardownEngine();
    super.dispose();
  }
}
