import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

enum FileCategory {
  directory,
  midi,
  soundFont,
}

class DiscoveredFileItem {
  final FileSystemEntity entity;
  final String path;
  final String name;
  final FileCategory category;
  final int sizeInBytes;
  final DateTime? lastModified;
  final bool isDrive;

  DiscoveredFileItem({
    required this.entity,
    required this.path,
    required this.name,
    required this.category,
    required this.sizeInBytes,
    required this.lastModified,
    this.isDrive = false,
  });

  bool get isDirectory => category == FileCategory.directory;
  bool get isMidi => category == FileCategory.midi;
  bool get isSoundFont => category == FileCategory.soundFont;

  String get formattedSize {
    if (isDirectory) return '';
    if (sizeInBytes < 1024) return '$sizeInBytes B';
    if (sizeInBytes < 1024 * 1024) {
      return '${(sizeInBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(sizeInBytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }
}

class FileService extends ChangeNotifier {
  static const Set<String> midiExtensions = {'.mid', '.midi', '.kar'};
  static const Set<String> soundFontExtensions = {'.sf2', '.sf3', '.dls'};

  static const String windowsDrivesPath = 'This PC';

  String? _homeDirectoryPath;
  String? _currentDirectoryPath;
  List<DiscoveredFileItem> _currentFiles = [];
  bool _isLoading = true;
  bool _permissionGranted = true;
  String? _errorMessage;

  String? get homeDirectoryPath => _homeDirectoryPath;
  String? get currentDirectoryPath => _currentDirectoryPath;
  List<DiscoveredFileItem> get currentFiles => List.unmodifiable(_currentFiles);
  bool get isLoading => _isLoading;
  bool get permissionGranted => _permissionGranted;
  String? get errorMessage => _errorMessage;

  bool get isDrivesView =>
      Platform.isWindows && _currentDirectoryPath == windowsDrivesPath;

  /// Detect whether a given path is a Windows drive root (e.g. C:\, C:, C:/, /, \)
  static bool isWindowsDriveRoot(String path) {
    final clean = path.replaceAll('/', '\\').trim();
    return RegExp(r'^[a-zA-Z]:\\?$').hasMatch(clean) || clean == '\\';
  }

  bool get canNavigateUp {
    if (_currentDirectoryPath == null) return false;
    if (Platform.isWindows && isDrivesView) return false;
    if (Platform.isWindows && isWindowsDriveRoot(_currentDirectoryPath!)) {
      return true;
    }
    final parent = p.dirname(_currentDirectoryPath!);
    return parent != _currentDirectoryPath && parent.isNotEmpty;
  }

  /// Request storage / home directory permissions
  Future<bool> requestStoragePermissions() async {
    if (Platform.isAndroid) {
      var status = await Permission.storage.status;
      if (!status.isGranted) {
        status = await Permission.storage.request();
      }

      if (await Permission.manageExternalStorage.isRestricted) {
        // Ignored if restricted
      } else {
        var manageStatus = await Permission.manageExternalStorage.status;
        if (!manageStatus.isGranted) {
          await Permission.manageExternalStorage.request();
        }
      }

      _permissionGranted = status.isGranted || await Permission.manageExternalStorage.isGranted;
    } else {
      // Desktop platforms (macOS, Linux, Windows) & iOS
      _permissionGranted = true;
    }

    notifyListeners();
    return _permissionGranted;
  }

  /// Resolve the user's home directory across platforms
  Future<String> resolveHomeDirectory() async {
    if (Platform.isMacOS || Platform.isLinux) {
      final home = Platform.environment['HOME'];
      if (home != null && Directory(home).existsSync()) {
        return home;
      }
    } else if (Platform.isWindows) {
      final userProfile = Platform.environment['USERPROFILE'];
      if (userProfile != null && Directory(userProfile).existsSync()) {
        return userProfile;
      }
      final homeDrive = Platform.environment['HOMEDRIVE'];
      final homePath = Platform.environment['HOMEPATH'];
      if (homeDrive != null && homePath != null) {
        final combined = '$homeDrive$homePath';
        if (Directory(combined).existsSync()) {
          return combined;
        }
      }
    } else if (Platform.isAndroid) {
      final ext = Directory('/storage/emulated/0');
      if (ext.existsSync()) {
        return ext.path;
      }
    }

    // Fallback: system documents directory
    final docDir = await getApplicationDocumentsDirectory();
    return docDir.path;
  }

  /// Initialize file service: request permission, resolve home dir, list filtered files
  Future<void> initialize() async {
    await requestStoragePermissions();
    _homeDirectoryPath = await resolveHomeDirectory();
    _currentDirectoryPath = _homeDirectoryPath;
    await scanCurrentDirectory();
  }

  /// Scans the directory, filtering ONLY MIDI and SoundFont files, excluding everything else!
  Future<void> scanCurrentDirectory() async {
    if (_currentDirectoryPath == null) return;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    if (Platform.isWindows && isDrivesView) {
      try {
        _currentFiles = await getWindowsDrives();
      } catch (e) {
        _errorMessage = 'Error getting drives: $e';
        _currentFiles = [];
      } finally {
        _isLoading = false;
        notifyListeners();
      }
      return;
    }

    try {
      final dir = Directory(_currentDirectoryPath!);
      if (!await dir.exists()) {
        _errorMessage = 'Directory does not exist: $_currentDirectoryPath';
        _currentFiles = [];
        _isLoading = false;
        notifyListeners();
        return;
      }

      final entities = await dir
          .list(followLinks: false)
          .handleError((e) {
            debugPrint('File scan warning: $e');
          })
          .toList();
      final List<DiscoveredFileItem> items = [];

      for (var entity in entities) {
        final baseName = p.basename(entity.path);

        // Skip hidden files/folders (starting with '.')
        if (baseName.startsWith('.')) continue;

        bool isDir = entity is Directory;
        bool isFile = entity is File;

        // Handle symlinks (such as /Volumes/Macintosh HD or symlinked folders)
        if (entity is Link) {
          try {
            final targetType = FileSystemEntity.typeSync(entity.path);
            if (targetType == FileSystemEntityType.directory) {
              isDir = true;
            } else if (targetType == FileSystemEntityType.file) {
              isFile = true;
            }
          } catch (_) {}
        }

        if (isDir) {
          // Keep directories so user can navigate into subfolders
          items.add(DiscoveredFileItem(
            entity: entity,
            path: entity.path,
            name: baseName,
            category: FileCategory.directory,
            sizeInBytes: 0,
            lastModified: null,
          ));
        } else if (isFile) {
          final ext = p.extension(entity.path).toLowerCase();

          // REQUIREMENT: Strictly exclude any file that is NOT midi or soundfont!
          if (midiExtensions.contains(ext)) {
            int size = 0;
            DateTime? mod;
            try {
              final stat = await entity.stat();
              size = stat.size;
              mod = stat.modified;
            } catch (_) {}
            items.add(DiscoveredFileItem(
              entity: entity,
              path: entity.path,
              name: baseName,
              category: FileCategory.midi,
              sizeInBytes: size,
              lastModified: mod,
            ));
          } else if (soundFontExtensions.contains(ext)) {
            int size = 0;
            DateTime? mod;
            try {
              final stat = await entity.stat();
              size = stat.size;
              mod = stat.modified;
            } catch (_) {}
            items.add(DiscoveredFileItem(
              entity: entity,
              path: entity.path,
              name: baseName,
              category: FileCategory.soundFont,
              sizeInBytes: size,
              lastModified: mod,
            ));
          }
          // Any other file format is completely excluded!
        }
      }

      // Sort: directories first (alphabetical), then files (alphabetical)
      items.sort((a, b) {
        if (a.isDirectory && !b.isDirectory) return -1;
        if (!a.isDirectory && b.isDirectory) return 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

      _currentFiles = items;
    } catch (e) {
      _errorMessage = 'Error reading directory: $e';
      debugPrint(_errorMessage);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Path to external drives / volumes directory across platforms
  String get volumesDirectoryPath {
    if (Platform.isMacOS) {
      if (Directory('/Volumes').existsSync()) return '/Volumes';
    } else if (Platform.isLinux) {
      if (Directory('/media').existsSync()) return '/media';
      if (Directory('/mnt').existsSync()) return '/mnt';
    } else if (Platform.isWindows) {
      return windowsDrivesPath;
    }
    return '/';
  }

  /// Navigate into a subdirectory
  Future<void> navigateTo(String dirPath) async {
    if (Platform.isWindows &&
        (dirPath == '/' || dirPath == '\\' || dirPath == windowsDrivesPath)) {
      _currentDirectoryPath = windowsDrivesPath;
    } else {
      _currentDirectoryPath = dirPath;
    }
    await scanCurrentDirectory();
  }

  /// Jump directly to external drives / volumes directory
  Future<void> navigateToVolumes() async {
    await navigateTo(volumesDirectoryPath);
  }

  /// Navigate to parent directory
  Future<void> navigateUp() async {
    if (_currentDirectoryPath == null) return;
    if (Platform.isWindows) {
      if (isDrivesView) return;
      if (isWindowsDriveRoot(_currentDirectoryPath!)) {
        await navigateToVolumes();
        return;
      }
    }
    final parent = p.dirname(_currentDirectoryPath!);
    if (parent != _currentDirectoryPath && parent.isNotEmpty) {
      _currentDirectoryPath = parent;
      await scanCurrentDirectory();
    }
  }

  /// Reset to home directory
  Future<void> navigateToHome() async {
    if (_homeDirectoryPath == null) return;
    _currentDirectoryPath = _homeDirectoryPath;
    await scanCurrentDirectory();
  }

  /// Detect all logical drives on Windows with friendly names and types
  static Future<List<DiscoveredFileItem>> getWindowsDrives() async {
    final List<DiscoveredFileItem> driveItems = [];

    if (!Platform.isWindows) return driveItems;

    try {
      final kernel32 = DynamicLibrary.open('kernel32.dll');

      // SetErrorMode to suppress OS error popups for unformatted/empty media
      try {
        final setErrorMode = kernel32.lookupFunction<
            Uint32 Function(Uint32),
            int Function(int)>('SetErrorMode');
        setErrorMode(0x0001 | 0x8000);
      } catch (_) {}

      final getLogicalDrives = kernel32.lookupFunction<
          Uint32 Function(),
          int Function()>('GetLogicalDrives');
      final getDriveType = kernel32.lookupFunction<
          Uint32 Function(Pointer<Utf16>),
          int Function(Pointer<Utf16>)>('GetDriveTypeW');
      final getVolumeInfo = kernel32.lookupFunction<
          Int32 Function(
            Pointer<Utf16>,
            Pointer<Utf16>,
            Uint32,
            Pointer<Uint32>,
            Pointer<Uint32>,
            Pointer<Uint32>,
            Pointer<Utf16>,
            Uint32,
          ),
          int Function(
            Pointer<Utf16>,
            Pointer<Utf16>,
            int,
            Pointer<Uint32>,
            Pointer<Uint32>,
            Pointer<Uint32>,
            Pointer<Utf16>,
            int,
          )>('GetVolumeInformationW');

      final mask = getLogicalDrives();
      for (int i = 0; i < 26; i++) {
        if ((mask & (1 << i)) != 0) {
          final letter = String.fromCharCode(65 + i);
          final drivePath = '$letter:\\';
          final drivePathPtr = drivePath.toNativeUtf16();

          String label = '';
          int type = 0;

          try {
            type = getDriveType(drivePathPtr);
            if (type == 1) {
              calloc.free(drivePathPtr);
              continue;
            }

            final volNameBuf = calloc<Uint16>(260).cast<Utf16>();
            try {
              final ok = getVolumeInfo(
                drivePathPtr,
                volNameBuf,
                260,
                nullptr,
                nullptr,
                nullptr,
                nullptr,
                0,
              );
              if (ok != 0) {
                label = volNameBuf.toDartString().trim();
              }
            } catch (_) {
            } finally {
              calloc.free(volNameBuf);
            }
          } finally {
            calloc.free(drivePathPtr);
          }

          String displayName;
          if (label.isNotEmpty) {
            displayName = '$label ($letter:)';
          } else {
            switch (type) {
              case 2: // DRIVE_REMOVABLE
                displayName = 'Removable Disk ($letter:)';
                break;
              case 3: // DRIVE_FIXED
                displayName = 'Local Disk ($letter:)';
                break;
              case 4: // DRIVE_REMOTE
                displayName = 'Network Drive ($letter:)';
                break;
              case 5: // DRIVE_CDROM
                displayName = 'CD Drive ($letter:)';
                break;
              case 6: // DRIVE_RAMDISK
                displayName = 'RAM Disk ($letter:)';
                break;
              default:
                displayName = 'Drive ($letter:)';
            }
          }

          driveItems.add(DiscoveredFileItem(
            entity: Directory(drivePath),
            path: drivePath,
            name: displayName,
            category: FileCategory.directory,
            sizeInBytes: 0,
            lastModified: null,
            isDrive: true,
          ));
        }
      }
    } catch (e) {
      debugPrint('Error getting Windows drives via FFI: $e');
      driveItems.clear();
      for (int i = 0; i < 26; i++) {
        final letter = String.fromCharCode(65 + i);
        final drivePath = '$letter:\\';
        try {
          final dir = Directory(drivePath);
          if (dir.existsSync()) {
            driveItems.add(DiscoveredFileItem(
              entity: dir,
              path: drivePath,
              name: 'Drive ($letter:)',
              category: FileCategory.directory,
              sizeInBytes: 0,
              lastModified: null,
              isDrive: true,
            ));
          }
        } catch (_) {}
      }
    }

    return driveItems;
  }
}
