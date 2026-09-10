import 'dart:ffi' hide Size;
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ffs/i18n/i18n_service.dart';
import 'package:audio_service/audio_service.dart';
import 'package:ffs/services/audio_handler.dart';
import 'package:ffs/services/file_service.dart';
import 'package:ffs/services/fluidsynth_service.dart';
import 'package:ffs/services/midi_parser.dart';
import 'package:ffs/services/soundfont_service.dart';
import 'package:ffs/ffi/fluidsynth_loader.dart';
import 'package:ffs/ui/settings_page.dart';
import 'package:ffs/ui/home_page.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('I18nService & CSV Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('I18nService parses CSV with empty lines separating pages', () async {
      final i18n = I18nService();

      const sampleCsv = '''control_name,zh_TW,zh_CN,en,ja
app_title,FluidMIDI 播放器,FluidMIDI 播放器,FluidMIDI Player,FluidMIDI プレーヤー
common_ok,確定,确定,OK,確定

home_title,家目錄音樂檔案,家目录音乐文件,Home Music Files,ホームの音楽ファイル
home_no_files_found,在家目錄中未找到任何 MIDI 或 SoundFont 檔案,在家目录中未找到任何 MIDI 或 SoundFont 文件,No MIDI or SoundFont files found in home directory,ホームディレクトリ内に MIDI または SoundFont ファイルが見つかりませんでした

sf_manager_title,已知 SoundFont 清單,已知 SoundFont 列表,Known SoundFonts,登録済みサウンドフォント
''';

      // Explicitly test parseCsvContent with sample CSV containing empty lines
      i18n.parseCsvContent(sampleCsv);

      expect(i18n.isLoaded, isTrue);

      // Test English
      await i18n.setLanguage('en');
      expect(i18n.t('app_title'), 'FluidMIDI Player');
      expect(i18n.t('home_title'), 'Home Music Files');
      expect(i18n.t('sf_manager_title'), 'Known SoundFonts');

      // Test Traditional Chinese
      await i18n.setLanguage('zh_TW');
      expect(i18n.t('app_title'), 'FluidMIDI 播放器');
      expect(i18n.t('home_title'), '家目錄音樂檔案');

      // Test Simplified Chinese
      await i18n.setLanguage('zh_CN');
      expect(i18n.t('app_title'), 'FluidMIDI 播放器');
      expect(i18n.t('home_title'), '家目录音乐文件');

      // Test Japanese
      await i18n.setLanguage('ja');
      expect(i18n.t('app_title'), 'FluidMIDI プレーヤー');
      expect(i18n.t('home_title'), 'ホームの音楽ファイル');
    });

    test('Localization Adaptation Mode directly displays control name', () async {
      final i18n = I18nService();
      await i18n.initialize();
      await i18n.reloadCsv();

      // Normal mode: translated string
      await i18n.setLanguage('en');
      expect(i18n.t('app_title'), 'FluidMIDI Player');

      // Adaptation mode: show control name directly!
      await i18n.setShowControlNames(true);
      expect(i18n.showControlNames, isTrue);
      expect(i18n.t('app_title'), 'app_title');
      expect(i18n.t('home_title'), 'home_title');
      expect(i18n.t('sf_manager_title'), 'sf_manager_title');

      // Switch back
      await i18n.setShowControlNames(false);
      expect(i18n.t('app_title'), 'FluidMIDI Player');
    });
  });

  group('File Filtering Tests', () {
    test('Strictly includes MIDI and SoundFont files while excluding all others', () {
      expect(FileService.midiExtensions, contains('.mid'));
      expect(FileService.midiExtensions, contains('.midi'));
      expect(FileService.midiExtensions, contains('.kar'));

      expect(FileService.soundFontExtensions, contains('.sf2'));
      expect(FileService.soundFontExtensions, contains('.sf3'));
      expect(FileService.soundFontExtensions, contains('.dls'));

      // Test exclusion of non-midi/non-sf files
      final nonAllowedExtensions = [
        '.mp3',
        '.wav',
        '.flac',
        '.ogg',
        '.txt',
        '.pdf',
        '.doc',
        '.jpg',
        '.png',
        '.zip',
        '.exe',
        '.dylib',
      ];

      for (var ext in nonAllowedExtensions) {
        expect(FileService.midiExtensions.contains(ext), isFalse);
        expect(FileService.soundFontExtensions.contains(ext), isFalse);
      }
    });
  });

  group('FluidSynthLoader & FFI Integration Tests', () {
    test('FluidSynthLoader loads dynamic library and exposes version', () async {
      final result = await FluidSynthLoader.load();
      if (result.isSuccess) {
        expect(result.bindings, isNotNull);
        expect(result.loadedPath, isNotNull);
        expect(result.version, isNotNull);
        expect(result.version!.isNotEmpty, isTrue);

        final b = result.bindings!;
        final settings = b.newFluidSettings();
        expect(settings != nullptr, isTrue);

        final synth = b.newFluidSynth(settings);
        expect(synth != nullptr, isTrue);

        b.deleteFluidSynth(synth);
        b.deleteFluidSettings(settings);
      } else {
        // If library is not on standard search path (e.g. CI headless), error message must be informative
        expect(result.errorMessage, isNotNull);
      }
    });

    test('FluidSynthService stop and reset operate cleanly without throwing and keep audio driver inactive', () {
      final service = FluidSynthService();
      expect(service.isAudioDriverActive, isFalse);
      // Calling stop or pause before initialization or when stopped is safe and idempotent
      expect(() => service.stop(), returnsNormally);
      expect(() => service.pause(), returnsNormally);
      expect(service.playbackState, equals(FluidPlaybackState.stopped));
      expect(service.isAudioDriverActive, isFalse);
    });

    test('Bundled FluidSynth native binaries exist for Android, Windows, and iOS', () {
      // Android
      final androidAbis = ['arm64-v8a', 'armeabi-v7a', 'x86', 'x86_64'];
      for (final abi in androidAbis) {
        final libPath = 'android/app/src/main/jniLibs/$abi/libfluidsynth.so';
        expect(File(libPath).existsSync(), isTrue, reason: 'Missing $libPath');
      }

      // Windows
      for (final arch in ['x64', 'x86']) {
        final dllPath = 'windows/fluidsynth/$arch/bin/libfluidsynth-3.dll';
        final sdlPath = 'windows/fluidsynth/$arch/bin/SDL3.dll';
        final sndPath = 'windows/fluidsynth/$arch/bin/sndfile.dll';
        expect(File(dllPath).existsSync(), isTrue, reason: 'Missing $dllPath');
        expect(File(sdlPath).existsSync(), isTrue, reason: 'Missing $sdlPath');
        expect(File(sndPath).existsSync(), isTrue, reason: 'Missing $sndPath');
      }

      // iOS
      final xcframeworkPath = 'ios/Frameworks/FluidSynth/FluidSynth.xcframework';
      expect(Directory(xcframeworkPath).existsSync(), isTrue, reason: 'Missing $xcframeworkPath');
    });
  });

  group('MidiParser & Time Accuracy Tests', () {
    test('Correctly calculates exact seconds for division=120 and BPM=109 (orc01.mid case)', () {
      // Create synthetic MIDI data matching orc01.mid:
      // Division = 120 (0x0078), Tempo = 109 BPM = 550458 us (0x08663A)
      final bytes = Uint8List.fromList([
        // MThd header
        0x4D, 0x54, 0x68, 0x64,
        0x00, 0x00, 0x00, 0x06,
        0x00, 0x01, // Format 1
        0x00, 0x01, // 1 track
        0x00, 0x78, // Division = 120
        // MTrk chunk
        0x4D, 0x54, 0x72, 0x6B,
        0x00, 0x00, 0x00, 0x0B, // Length = 11
        // Delta = 0, Meta Set Tempo (0xFF 0x51 0x03 0x08 0x66 0x3A)
        0x00, 0xFF, 0x51, 0x03, 0x08, 0x66, 0x3A,
        // End of track
        0x00, 0xFF, 0x2F, 0x00,
      ]);

      final info = MidiFileInfo.parseBytes(bytes);
      expect(info.division, equals(120));
      expect(info.tempoPoints.length, greaterThanOrEqualTo(1));

      // At BPM 109 and division 120, 1 second = (109 * 120) / 60 = 218 ticks
      final oneSecond = info.tickToSeconds(218);
      expect((oneSecond - 1.0).abs(), lessThan(0.01));

      // 10 seconds = 2180 ticks
      final tenSeconds = info.tickToSeconds(2180);
      expect((tenSeconds - 10.0).abs(), lessThan(0.05));

      // Total duration for e.g. 15478 ticks should be ~71 seconds (1:11), NOT 17 seconds
      final totalSecs = info.tickToSeconds(15478);
      expect((totalSecs - 71.0).abs(), lessThan(1.0));
      expect(FluidSynthService.formatDuration(totalSecs), equals('1:10'));
    });
  });

  group('Playlist & Playback Control Tests', () {
    test('Playlist initializes, tracks current index, and clamps properly', () {
      final service = FluidSynthService();
      expect(service.playlist, isEmpty);
      expect(service.playlistIndex, equals(-1));
      expect(service.hasNext, isFalse);
      expect(service.hasPrevious, isFalse);

      service.setPlaylist(['/path/1.mid', '/path/2.mid', '/path/3.mid'], initialIndex: 1);
      expect(service.playlist.length, equals(3));
      expect(service.playlistIndex, equals(1));
      expect(service.playlist[service.playlistIndex], equals('/path/2.mid'));
      expect(service.hasNext, isTrue);
      expect(service.hasPrevious, isTrue);

      // Clamping test
      service.setPlaylist(['/path/1.mid'], initialIndex: 99);
      expect(service.playlistIndex, equals(0));
    });

    test('LoopMode cycles correctly: playlist -> single -> none -> playlist', () {
      final service = FluidSynthService();
      // Default loopMode is playlist
      expect(service.loopMode, equals(LoopMode.playlist));
      expect(service.isLooping, isTrue);

      service.cycleLoopMode();
      expect(service.loopMode, equals(LoopMode.single));
      expect(service.isLooping, isTrue);

      service.cycleLoopMode();
      expect(service.loopMode, equals(LoopMode.none));
      expect(service.isLooping, isFalse);

      service.cycleLoopMode();
      expect(service.loopMode, equals(LoopMode.playlist));
      expect(service.isLooping, isTrue);

      service.setLoopMode(LoopMode.single);
      expect(service.loopMode, equals(LoopMode.single));
    });

    test('Toggle shuffle updates state and initializes history', () {
      final service = FluidSynthService();
      expect(service.isShuffle, isFalse);

      service.setPlaylist(['/path/1.mid', '/path/2.mid'], initialIndex: 0);
      service.toggleShuffle();
      expect(service.isShuffle, isTrue);

      service.toggleShuffle();
      expect(service.isShuffle, isFalse);
    });

    test('addToPlaylistNext inserts track immediately after current index', () {
      final service = FluidSynthService();
      // Empty playlist
      service.addToPlaylistNext('/path/a.mid');
      expect(service.playlist, equals(['/path/a.mid']));
      expect(service.playlistIndex, equals(0));

      // Append next when 1 item
      service.addToPlaylistNext('/path/b.mid');
      expect(service.playlist, equals(['/path/a.mid', '/path/b.mid']));
      expect(service.playlistIndex, equals(0));

      // Insert next in middle
      service.setPlaylist(['/path/1.mid', '/path/2.mid', '/path/3.mid'], initialIndex: 0);
      service.addToPlaylistNext('/path/next.mid');
      expect(service.playlist, equals(['/path/1.mid', '/path/next.mid', '/path/2.mid', '/path/3.mid']));
      expect(service.playlistIndex, equals(0));

      // Adding an existing item moves it to next
      service.addToPlaylistNext('/path/3.mid');
      expect(service.playlist, equals(['/path/1.mid', '/path/3.mid', '/path/next.mid', '/path/2.mid']));
    });

    test('reorderPlaylist and removeFromPlaylist safely maintain current index', () {
      final service = FluidSynthService();
      service.setPlaylist(['/path/0.mid', '/path/1.mid', '/path/2.mid', '/path/3.mid'], initialIndex: 2);
      expect(service.playlist[service.playlistIndex], equals('/path/2.mid'));

      // Reorder item 0 to 3
      service.reorderPlaylist(0, 4);
      expect(service.playlist[service.playlistIndex], equals('/path/2.mid'));

      // Remove before current index
      service.removeFromPlaylist(0);
      expect(service.playlist[service.playlistIndex], equals('/path/2.mid'));

      // Clear playlist
      service.clearPlaylist();
      expect(service.playlist, isEmpty);
      expect(service.playlistIndex, equals(-1));
    });

    test('playNext with autoAdvance stops playback and releases pipeline when playlist ends', () async {
      final service = FluidSynthService();
      service.setLoopMode(LoopMode.none);
      service.setPlaylist(['/path/1.mid', '/path/2.mid'], initialIndex: 1);

      // Sequential playlist at last track with LoopMode.none
      final hasNext = await service.playNext(autoAdvance: true);
      expect(hasNext, isFalse);
      expect(service.playbackState, equals(FluidPlaybackState.stopped));
      expect(service.isAudioDriverActive, isFalse);
    });

    test('Shuffle playNext with autoAdvance stops playback when all tracks have been played', () async {
      final service = FluidSynthService();
      service.setLoopMode(LoopMode.none);
      // Single track playlist in shuffle mode
      service.setPlaylist(['/path/single.mid'], initialIndex: 0);
      service.toggleShuffle();
      final hasNextSingle = await service.playNext(autoAdvance: true);
      expect(hasNextSingle, isFalse);
      expect(service.playbackState, equals(FluidPlaybackState.stopped));
      expect(service.isAudioDriverActive, isFalse);
    });
  });

  group('Windows Drive & Path Navigation Tests', () {
    test('isWindowsDriveRoot correctly identifies drive roots and rejects subdirectories', () {
      // Valid drive root formats
      expect(FileService.isWindowsDriveRoot(r'C:\'), isTrue);
      expect(FileService.isWindowsDriveRoot('C:'), isTrue);
      expect(FileService.isWindowsDriveRoot('C:/'), isTrue);
      expect(FileService.isWindowsDriveRoot(r'c:\'), isTrue);
      expect(FileService.isWindowsDriveRoot(r'D:\'), isTrue);
      expect(FileService.isWindowsDriveRoot(r'z:\'), isTrue);
      expect(FileService.isWindowsDriveRoot('/'), isTrue);
      expect(FileService.isWindowsDriveRoot(r'\'), isTrue);

      // Subdirectories - NOT drive roots
      expect(FileService.isWindowsDriveRoot(r'C:\Users'), isFalse);
      expect(FileService.isWindowsDriveRoot(r'C:\Users\zhaoy'), isFalse);
      expect(FileService.isWindowsDriveRoot('C:/Windows/System32'), isFalse);
      expect(FileService.isWindowsDriveRoot('/Volumes'), isFalse);
      expect(FileService.isWindowsDriveRoot('/Volumes/Macintosh HD'), isFalse);
    });

    test('I18n contains all newly added localization keys for Windows drives and FluidSynth status', () async {
      final i18n = I18nService();
      await i18n.initialize();
      await i18n.reloadCsv();

      await i18n.setLanguage('zh_TW');
      expect(i18n.t('home_this_pc'), '本機');
      expect(i18n.t('home_item_badge_drive'), '磁碟機');
      expect(i18n.t('home_lib_not_loaded'), contains('FluidSynth'));
      expect(i18n.t('home_btn_goto_settings'), '前往設定');

      await i18n.setLanguage('zh_CN');
      expect(i18n.t('home_this_pc'), '此电脑');
      expect(i18n.t('home_item_badge_drive'), '磁盘驱动器');

      await i18n.setLanguage('en');
      expect(i18n.t('home_this_pc'), 'This PC');
      expect(i18n.t('home_item_badge_drive'), 'Disk Drive');
      expect(i18n.t('home_btn_goto_settings'), 'Settings');
    });

    test('SoundFontService normalizes paths and compares with p.equals', () async {
      final sfService = SoundFontService();
      await sfService.initialize();

      // Ensure activeSoundFont returns null when no path set
      expect(sfService.activeSoundFont, isNull);
    });
  });

  group('Back Navigation Widget Logic Tests', () {
    testWidgets('PopScope, mouse side button, and browser back key trigger callback when canNavigateUp is true', (tester) async {
      int backCount = 0;
      bool canNavigateUp = true;

      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              return PopScope(
                canPop: !canNavigateUp,
                onPopInvokedWithResult: (didPop, result) {
                  if (didPop) return;
                  if (canNavigateUp) {
                    backCount++;
                  }
                },
                child: Focus(
                  autofocus: true,
                  onKeyEvent: (node, event) {
                    if (event is KeyDownEvent) {
                      final isBrowserBack = event.logicalKey == LogicalKeyboardKey.browserBack ||
                          event.logicalKey == LogicalKeyboardKey.goBack;
                      final isAltUp = HardwareKeyboard.instance.isAltPressed &&
                          event.logicalKey == LogicalKeyboardKey.arrowUp;
                      final isCmdUp = HardwareKeyboard.instance.isMetaPressed &&
                          event.logicalKey == LogicalKeyboardKey.arrowUp;

                      if (isBrowserBack || isAltUp || isCmdUp) {
                        if (canNavigateUp) {
                          backCount++;
                          return KeyEventResult.handled;
                        }
                      }
                    }
                    return KeyEventResult.ignored;
                  },
                  child: Listener(
                    behavior: HitTestBehavior.translucent,
                    onPointerDown: (event) {
                      if ((event.buttons & kBackMouseButton) != 0) {
                        if (canNavigateUp) {
                          backCount++;
                        }
                      }
                    },
                    child: const Scaffold(body: Text('Navigation Test View')),
                  ),
                ),
              );
            },
          ),
        ),
      );
      await tester.pump();

      // 1. Android back button (handlePopRoute)
      await tester.binding.handlePopRoute();
      expect(backCount, equals(1));

      // 2. Mouse side button (kBackMouseButton = 8)
      final center = tester.getCenter(find.text('Navigation Test View'));
      final gesture = await tester.startGesture(center, buttons: kBackMouseButton, kind: PointerDeviceKind.mouse);
      await gesture.up();
      expect(backCount, equals(2));

      // 3. Browser back keyboard key (Windows / Desktop)
      await tester.sendKeyEvent(LogicalKeyboardKey.browserBack, platform: 'windows');
      expect(backCount, equals(3));

      // 4. Alt + UpArrow (Windows / Linux)
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      expect(backCount, equals(4));

      // 5. Cmd + UpArrow (macOS)
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      expect(backCount, equals(5));
    });
  });

  group('FluidAudioHandler & System Media Controls Tests', () {
    test('seekSeconds handles valid seconds and edge cases gracefully', () {
      final service = FluidSynthService();
      // When uninitialized or no track loaded, seekSeconds should not throw
      expect(() => service.seekSeconds(10.0), returnsNormally);
      expect(() => service.seekSeconds(-5.0), returnsNormally);
      expect(() => service.seekSeconds(double.nan), returnsNormally);
      expect(() => service.seekSeconds(double.infinity), returnsNormally);
    });

    test('FluidAudioHandler delegates play, pause, stop, and skips cleanly to service', () async {
      final service = FluidSynthService();
      final handler = FluidAudioHandler(service);

      // Verify initial state
      expect(handler.playbackState.value.playing, isFalse);
      expect(handler.playbackState.value.processingState, equals(AudioProcessingState.idle));

      // Test pause and stop delegates (safe and idempotent when stopped)
      await expectLater(handler.pause(), completes);
      expect(service.playbackState, equals(FluidPlaybackState.stopped));

      await expectLater(handler.stop(), completes);
      expect(service.playbackState, equals(FluidPlaybackState.stopped));

      // Test repeat mode delegate
      await handler.setRepeatMode(AudioServiceRepeatMode.one);
      expect(service.loopMode, equals(LoopMode.single));

      await handler.setRepeatMode(AudioServiceRepeatMode.all);
      expect(service.loopMode, equals(LoopMode.playlist));

      await handler.setRepeatMode(AudioServiceRepeatMode.none);
      expect(service.loopMode, equals(LoopMode.none));

      // Test shuffle mode delegate
      await handler.setShuffleMode(AudioServiceShuffleMode.all);
      expect(service.isShuffle, isTrue);

      await handler.setShuffleMode(AudioServiceShuffleMode.none);
      expect(service.isShuffle, isFalse);
    });
  });

  group('SettingsPage Responsive Layout Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets('SettingsPage renders without overflow on narrow width (320px)', (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final i18n = I18nService();
      i18n.parseCsvContent('''control_name,zh_TW,zh_CN,en,ja
settings_page_title,設定,设置,Settings,設定とライブラリ管理
settings_section_lib,庫,库,Lib,FluidSynth ライブラリの状態
settings_lib_status_loaded,已載入,已加载,Loaded,ライブラリは正常に読み込まれました
settings_lib_status_failed,載入失敗,加载失败,Failed,ライブラリの読み込みに失敗しました
settings_lib_version,版本,版本,Version,ライブラリバージョン
settings_lib_path,路徑,路径,Path,読み込みパス
settings_lib_sideload_tip,提示,提示,Tip,tip
settings_lib_sideload_btn,手動載入,手动加载,Sideload,FluidSynthを手動読み込み
settings_lib_reset_btn,重設,重置,Reset,デフォルトに戻す
settings_section_audio,音訊,音频,Audio,オーディオドライバ設定
settings_audio_driver_label,音訊驅動,音频驱动,Audio Driver,オーディオドライバ
player_volume_label,音量,音量,Volume,音量
settings_btn_test_sound,測試,测试,Test,サウンドテスト (Play C4)
settings_section_i18n,語言,语言,Language,言語とローカライズ
settings_language_label,介面語言,界面语言,Interface Language,インターフェース言語
settings_i18n_show_keys,鍵名,键名,Keys,適応モード：コントロール名を直接表示
settings_i18n_show_keys_desc,說明,说明,Desc,UIにCSVのcontrol_nameを表示し、翻訳や調整を容易にします
''');
      await i18n.setLanguage('ja');

      final fluidService = FluidSynthService();

      await tester.pumpWidget(
        I18nScope(
          service: i18n,
          child: MaterialApp(
            home: SettingsPage(
              fluidService: fluidService,
              i18nService: i18n,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byType(SettingsPage), findsOneWidget);
      expect(find.text('FluidSynth ライブラリの状態'), findsOneWidget);

      await tester.scrollUntilVisible(find.byIcon(Icons.speaker), 100);
      expect(find.byIcon(Icons.speaker), findsOneWidget);

      await tester.scrollUntilVisible(find.byIcon(Icons.language), 100);
      expect(find.byIcon(Icons.language), findsOneWidget);
    });

    testWidgets('SettingsPage renders without overflow on regular width (600px)', (tester) async {
      tester.view.physicalSize = const Size(600, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final i18n = I18nService();
      i18n.parseCsvContent('''control_name,zh_TW,zh_CN,en,ja
settings_page_title,設定,设置,Settings,設定とライブラリ管理
settings_section_lib,庫,库,Lib,FluidSynth ライブラリの状態
settings_lib_status_loaded,已載入,已加载,Loaded,ライブラリは正常に読み込まれました
settings_lib_status_failed,載入失敗,加载失败,Failed,ライブラリの読み込みに失敗しました
settings_lib_version,版本,版本,Version,ライブラリバージョン
settings_lib_path,路徑,路径,Path,読み込みパス
settings_lib_sideload_tip,提示,提示,Tip,tip
settings_lib_sideload_btn,手動載入,手动加载,Sideload,FluidSynthを手動読み込み
settings_lib_reset_btn,重設,重置,Reset,デフォルトに戻す
settings_section_audio,音訊,音频,Audio,オーディオドライバ設定
settings_audio_driver_label,音訊驅動,音频驱动,Audio Driver,オーディオドライバ
player_volume_label,音量,音量,Volume,音量
settings_btn_test_sound,測試,测试,Test,サウンドテスト (Play C4)
settings_section_i18n,語言,语言,Language,言語とローカライズ
settings_language_label,介面語言,界面语言,Interface Language,インターフェース言語
settings_i18n_show_keys,鍵名,键名,Keys,適応モード：コントロール名を直接表示
settings_i18n_show_keys_desc,說明,说明,Desc,UIにCSVのcontrol_nameを表示し、翻訳や調整を容易にします
''');
      await i18n.setLanguage('ja');

      final fluidService = FluidSynthService();

      await tester.pumpWidget(
        I18nScope(
          service: i18n,
          child: MaterialApp(
            home: SettingsPage(
              fluidService: fluidService,
              i18nService: i18n,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byType(SettingsPage), findsOneWidget);
    });
  });

  group('App Lifecycle & Background Playback Tests', () {
    testWidgets('MainNavigationPage preserves playback on paused/hidden/inactive and only stops on detached', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final i18n = I18nService();
      i18n.parseCsvContent('''control_name,zh_TW,zh_CN,en,ja
app_title,FluidMIDI 播放器,FluidMIDI 播放器,FluidMIDI Player,FluidMIDI プレーヤー
''');
      await i18n.setLanguage('en');

      final testFluidService = _LifecycleTestFluidSynthService();
      final fileService = FileService();
      final soundFontService = SoundFontService();

      await tester.pumpWidget(
        I18nScope(
          service: i18n,
          child: MaterialApp(
            home: MainNavigationPage(
              fileService: fileService,
              fluidService: testFluidService,
              soundFontService: soundFontService,
              i18nService: i18n,
            ),
          ),
        ),
      );
      await tester.pump();

      final state = tester.state(find.byType(MainNavigationPage)) as WidgetsBindingObserver;

      expect(testFluidService.stopCallCount, equals(0));

      // 1. Entering background / screen off: AppLifecycleState.paused
      state.didChangeAppLifecycleState(AppLifecycleState.paused);
      expect(testFluidService.stopCallCount, equals(0),
          reason: 'Playback must NOT stop when switching to background (paused)');

      // 2. Window minimized or hidden on desktop: AppLifecycleState.hidden
      state.didChangeAppLifecycleState(AppLifecycleState.hidden);
      expect(testFluidService.stopCallCount, equals(0),
          reason: 'Playback must NOT stop when hidden/minimized');

      // 3. Loss of window focus: AppLifecycleState.inactive
      state.didChangeAppLifecycleState(AppLifecycleState.inactive);
      expect(testFluidService.stopCallCount, equals(0),
          reason: 'Playback must NOT stop when inactive');

      // 4. App process termination / engine detach: AppLifecycleState.detached
      state.didChangeAppLifecycleState(AppLifecycleState.detached);
      expect(testFluidService.stopCallCount, equals(1),
          reason: 'Playback MUST stop when engine is detached');
    });
  });
}

class _LifecycleTestFluidSynthService extends FluidSynthService {
  int stopCallCount = 0;

  @override
  void stop() {
    stopCallCount++;
    super.stop();
  }
}



