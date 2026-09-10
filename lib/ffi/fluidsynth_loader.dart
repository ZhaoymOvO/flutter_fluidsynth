import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'fluidsynth_bindings.dart';

class FluidSynthLoadResult {
  final bool isSuccess;
  final FluidSynthBindings? bindings;
  final String? loadedPath;
  final String? version;
  final String? errorMessage;

  FluidSynthLoadResult.success({
    required this.bindings,
    required this.loadedPath,
    required this.version,
  })  : isSuccess = true,
        errorMessage = null;

  FluidSynthLoadResult.failure({
    required this.errorMessage,
  })  : isSuccess = false,
        bindings = null,
        loadedPath = null,
        version = null;
}

class FluidSynthLoader {
  static const String prefSideloadPathKey = 'fluidsynth_sideload_lib_path';

  /// Get the saved sideloaded library path if any
  static Future<String?> getSideloadedPath() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(prefSideloadPathKey);
  }

  /// Save the sideloaded library path
  static Future<void> saveSideloadedPath(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefSideloadPathKey, path);
  }

  /// Clear the sideloaded library path
  static Future<void> clearSideloadedPath() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(prefSideloadPathKey);
  }

  static void _setupWindowsDllDirectory(String path) {
    if (!Platform.isWindows) return;
    try {
      final dir = p.dirname(path);
      if (dir.isNotEmpty && dir != '.' && Directory(dir).existsSync()) {
        final kernel32 = DynamicLibrary.open('kernel32.dll');
        final setDllDirectory = kernel32.lookupFunction<
            Int32 Function(Pointer<Utf16>),
            int Function(Pointer<Utf16>)>('SetDllDirectoryW');
        final dirPtr = dir.toNativeUtf16();
        setDllDirectory(dirPtr);
        calloc.free(dirPtr);

        // Preload dependent DLLs if they exist in the same directory
        for (final dep in ['SDL3.dll', 'sndfile.dll']) {
          final depPath = p.join(dir, dep);
          if (File(depPath).existsSync()) {
            try {
              DynamicLibrary.open(depPath);
            } catch (_) {}
          }
        }
      }
    } catch (e) {
      debugPrint('SetDllDirectoryW error: $e');
    }
  }

  static void _setupAndroidDependencies() {
    if (!Platform.isAndroid) return;
    const deps = [
      'libc++_shared.so',
      'libogg.so',
      'libopus.so',
      'libFLAC.so',
      'libvorbis.so',
      'libvorbisenc.so',
      'libvorbisfile.so',
      'libsndfile.so',
      'liboboe.so',
      'libfluidsynth-assetloader.so',
    ];
    for (final dep in deps) {
      try {
        DynamicLibrary.open(dep);
      } catch (_) {}
    }
  }

  static DynamicLibrary _openLibrary(String path) {
    if (Platform.isWindows) {
      _setupWindowsDllDirectory(path);
    } else if (Platform.isAndroid) {
      _setupAndroidDependencies();
    }
    return DynamicLibrary.open(path);
  }

  /// Attempts to load FluidSynth, checking sideloaded path first,
  /// then fallback default / platform system paths.
  static Future<FluidSynthLoadResult> load({String? customPath}) async {
    final sideloaded = customPath ?? await getSideloadedPath();

    // 1. If user provided a sideloaded path, test it first
    if (sideloaded != null && sideloaded.isNotEmpty) {
      try {
        final lib = _openLibrary(sideloaded);
        final bindings = FluidSynthBindings(lib);
        final versionPtr = bindings.fluidVersionStr();
        final version = versionPtr.toDartString();
        return FluidSynthLoadResult.success(
          bindings: bindings,
          loadedPath: sideloaded,
          version: version,
        );
      } catch (e) {
        debugPrint('Failed to load sideloaded library ($sideloaded): $e');
        // If an explicit custom path was specified, report failure immediately
        if (customPath != null) {
          return FluidSynthLoadResult.failure(
            errorMessage: 'Failed to load sideloaded library from $sideloaded: $e',
          );
        }
      }
    }

    // 2. Try default bundled / platform system paths
    final candidatePaths = _getCandidatePaths();
    final errors = <String>[];

    for (final path in candidatePaths) {
      try {
        final lib = _openLibrary(path);
        final bindings = FluidSynthBindings(lib);
        final versionPtr = bindings.fluidVersionStr();
        final version = versionPtr.toDartString();
        return FluidSynthLoadResult.success(
          bindings: bindings,
          loadedPath: path,
          version: version,
        );
      } catch (e) {
        errors.add('$path: $e');
      }
    }

    // 3. On iOS, try DynamicLibrary.process() for embedded / statically linked frameworks
    if (Platform.isIOS) {
      try {
        final lib = DynamicLibrary.process();
        final bindings = FluidSynthBindings(lib);
        final versionPtr = bindings.fluidVersionStr();
        final version = versionPtr.toDartString();
        return FluidSynthLoadResult.success(
          bindings: bindings,
          loadedPath: 'DynamicLibrary.process()',
          version: version,
        );
      } catch (e) {
        errors.add('DynamicLibrary.process(): $e');
      }
    }

    return FluidSynthLoadResult.failure(
      errorMessage: 'FluidSynth library could not be found.\nAttempted paths:\n${errors.join('\n')}',
    );
  }

  static List<String> _getCandidatePaths() {
    if (Platform.isMacOS) {
      return [
        '/opt/homebrew/lib/libfluidsynth.dylib',
        '/opt/homebrew/lib/libfluidsynth.3.dylib',
        '/usr/local/lib/libfluidsynth.dylib',
        'libfluidsynth.dylib',
        '@rpath/libfluidsynth.dylib',
      ];
    } else if (Platform.isWindows) {
      final exeDir = p.dirname(Platform.resolvedExecutable);
      return [
        // 1. Next to executable
        p.join(exeDir, 'libfluidsynth-3.dll'),
        p.join(exeDir, 'fluidsynth.dll'),
        p.join(exeDir, 'libfluidsynth.dll'),
        p.join(exeDir, 'lib', 'libfluidsynth-3.dll'),
        p.join(exeDir, 'lib', 'fluidsynth.dll'),
        p.join(exeDir, 'bin', 'libfluidsynth-3.dll'),
        p.join(exeDir, 'bin', 'fluidsynth.dll'),

        // 2. Project workspace local paths during tests/dev
        p.join(Directory.current.path, 'windows', 'fluidsynth', 'x64', 'bin', 'libfluidsynth-3.dll'),
        p.join(Directory.current.path, 'windows', 'fluidsynth', 'x86', 'bin', 'libfluidsynth-3.dll'),

        // 3. System PATH bare names
        'libfluidsynth-3.dll',
        'fluidsynth.dll',
        'libfluidsynth.dll',

        // 4. Common installation paths
        r'C:\Program Files\FluidSynth\bin\libfluidsynth-3.dll',
        r'C:\Program Files\FluidSynth\bin\fluidsynth.dll',
        r'C:\Program Files (x86)\FluidSynth\bin\libfluidsynth-3.dll',
        r'C:\Program Files (x86)\FluidSynth\bin\fluidsynth.dll',
        r'C:\msys64\mingw64\bin\libfluidsynth-3.dll',
        r'C:\msys64\ucrt64\bin\libfluidsynth-3.dll',
        r'C:\msys64\clang64\bin\libfluidsynth-3.dll',
        r'C:\vcpkg\installed\x64-windows\bin\fluidsynth.dll',
        r'C:\vcpkg\installed\x64-windows\bin\libfluidsynth-3.dll',
        r'C:\tools\fluidsynth\bin\libfluidsynth-3.dll',
      ];
    } else if (Platform.isLinux) {
      return [
        'libfluidsynth.so.3',
        'libfluidsynth.so',
        '/usr/lib/libfluidsynth.so.3',
        '/usr/lib/x86_64-linux-gnu/libfluidsynth.so.3',
        '/usr/lib/aarch64-linux-gnu/libfluidsynth.so.3',
      ];
    } else if (Platform.isAndroid) {
      return [
        'libfluidsynth.so',
        'libfluidsynth.so.3',
        'fluidsynth',
      ];
    } else if (Platform.isIOS) {
      return [
        'FluidSynth.framework/FluidSynth',
        'fluidsynth.framework/fluidsynth',
        'FluidSynth',
        'libfluidsynth.dylib',
      ];
    }
    return ['fluidsynth'];
  }
}
