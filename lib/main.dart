import 'dart:io';
import 'dart:ui';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'i18n/i18n_service.dart';
import 'services/audio_handler.dart';
import 'services/file_service.dart';
import 'services/fluidsynth_service.dart';
import 'services/soundfont_service.dart';
import 'ui/home_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final i18nService = I18nService();
  await i18nService.initialize();

  final soundFontService = SoundFontService();
  await soundFontService.initialize();

  final fluidService = FluidSynthService();
  final fileService = FileService();

  // Handle OS process termination signals on desktop to ensure clean stop
  if (!Platform.isWindows) {
    try {
      ProcessSignal.sigterm.watch().listen((_) {
        fluidService.stop();
        exit(0);
      });
    } catch (_) {}
  }
  try {
    ProcessSignal.sigint.watch().listen((_) {
      fluidService.stop();
      exit(0);
    });
  } catch (_) {}

  // Run the app IMMEDIATELY so Flutter paints the first frame in milliseconds (no black screen delay)
  runApp(
    FluidMidiApp(
      i18nService: i18nService,
      soundFontService: soundFontService,
      fluidService: fluidService,
      fileService: fileService,
    ),
  );

  // Initialize file scanning & FluidSynth audio engine asynchronously in background
  _initServicesAsync(fluidService, soundFontService, fileService, i18nService);
}

void _initServicesAsync(
  FluidSynthService fluidService,
  SoundFontService soundFontService,
  FileService fileService,
  I18nService i18nService,
) async {
  // Scan home directory in background (fileService notifies listeners when complete)
  fileService.initialize();

  // Initialize FluidSynth engine & load active SoundFont in background
  await fluidService.initialize();
  if (soundFontService.activeSoundFontPath != null) {
    await fluidService.loadSoundFont(soundFontService.activeSoundFontPath!);
  }

  // Initialize system media controls (Windows SMTC, Android MediaSession & Foreground Service, iOS/macOS Now Playing)
  await initAudioService(fluidService, i18nService: i18nService);
}

class FluidMidiApp extends StatefulWidget {
  final I18nService i18nService;
  final SoundFontService soundFontService;
  final FluidSynthService fluidService;
  final FileService fileService;

  const FluidMidiApp({
    super.key,
    required this.i18nService,
    required this.soundFontService,
    required this.fluidService,
    required this.fileService,
  });

  @override
  State<FluidMidiApp> createState() => _FluidMidiAppState();
}

class _FluidMidiAppState extends State<FluidMidiApp> {
  late final AppLifecycleListener _lifecycleListener;

  @override
  void initState() {
    super.initState();
    _lifecycleListener = AppLifecycleListener(
      onExitRequested: () async {
        widget.fluidService.stop();
        return AppExitResponse.exit;
      },
      onDetach: () {
        widget.fluidService.stop();
      },
    );
  }

  @override
  void reassemble() {
    super.reassemble();
    // Stop playback immediately upon Flutter hot reload
    widget.fluidService.stop();
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    widget.fluidService.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return I18nScope(
      service: widget.i18nService,
      child: ListenableBuilder(
        listenable: widget.i18nService,
        builder: (context, _) {
          final fontFallbacks = _getFontFamilyFallback(
            widget.i18nService.currentLanguage,
          );
          return DynamicColorBuilder(
            builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
              final lightColorScheme =
                  lightDynamic ??
                  ColorScheme.fromSeed(
                    seedColor: Colors.deepPurple,
                    brightness: Brightness.light,
                  );
              final darkColorScheme =
                  darkDynamic ??
                  ColorScheme.fromSeed(
                    seedColor: Colors.deepPurple,
                    brightness: Brightness.dark,
                  );

              return MaterialApp(
                title: widget.i18nService.t('app_title'),
                debugShowCheckedModeBanner: false,
                theme: ThemeData(
                  useMaterial3: true,
                  colorScheme: lightColorScheme,
                  fontFamily: 'GoogleSans',
                  fontFamilyFallback: fontFallbacks,
                  cardTheme: const CardThemeData(elevation: 0),
                  snackBarTheme: const SnackBarThemeData(
                    behavior: SnackBarBehavior.floating,
                  ),
                  bottomSheetTheme: const BottomSheetThemeData(
                    showDragHandle: true,
                  ),
                ),
                darkTheme: ThemeData(
                  useMaterial3: true,
                  colorScheme: darkColorScheme,
                  fontFamily: 'GoogleSans',
                  fontFamilyFallback: fontFallbacks,
                  cardTheme: const CardThemeData(elevation: 0),
                  snackBarTheme: const SnackBarThemeData(
                    behavior: SnackBarBehavior.floating,
                  ),
                  bottomSheetTheme: const BottomSheetThemeData(
                    showDragHandle: true,
                  ),
                ),
                themeMode: ThemeMode.system,
                home: MainNavigationPage(
                  fileService: widget.fileService,
                  fluidService: widget.fluidService,
                  soundFontService: widget.soundFontService,
                  i18nService: widget.i18nService,
                ),
              );
            },
          );
        },
      ),
    );
  }
}

List<String> _getFontFamilyFallback(String languageCode) {
  final isHant =
      languageCode == 'zh_TW' ||
      (languageCode == 'auto' &&
          (PlatformDispatcher.instance.locale.scriptCode == 'Hant' ||
              PlatformDispatcher.instance.locale.countryCode == 'TW' ||
              PlatformDispatcher.instance.locale.countryCode == 'HK'));

  final isJapanese =
      languageCode == 'ja' ||
      (languageCode == 'auto' &&
          PlatformDispatcher.instance.locale.languageCode == 'ja');

  if (isJapanese) {
    return const [
      'Hiragino Sans',
      'Hiragino Kaku Gothic ProN',
      'Yu Gothic',
      'Meiryo',
      'Noto Sans CJK JP',
      'Noto Sans JP',
      'PingFang SC',
      'Microsoft YaHei',
      'sans-serif',
    ];
  }

  if (isHant) {
    return const [
      'PingFang TC',
      'PingFang HK',
      'Microsoft JhengHei',
      'Noto Sans CJK TC',
      'Noto Sans TC',
      'PingFang SC',
      'Microsoft YaHei',
      'Noto Sans CJK SC',
      'Noto Sans SC',
      'sans-serif',
    ];
  }

  // Simplified Chinese & general fallback
  return const [
    'PingFang SC',
    'Microsoft YaHei',
    'Noto Sans CJK SC',
    'Noto Sans SC',
    'PingFang TC',
    'Microsoft JhengHei',
    'Noto Sans CJK TC',
    'Noto Sans TC',
    'sans-serif',
  ];
}
