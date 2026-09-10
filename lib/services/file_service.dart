import 'dart:io';
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

  DiscoveredFileItem({
    required this.entity,
    required this.path,
    required this.name,
    required this.category,
    required this.sizeInBytes,
    required this.lastModified,
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

  bool get canNavigateUp {
    if (_currentDirectoryPath == null) return false;
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
    }
    return '/';
  }

  /// Navigate into a subdirectory
  Future<void> navigateTo(String dirPath) async {
    _currentDirectoryPath = dirPath;
    await scanCurrentDirectory();
  }

  /// Jump directly to external drives / volumes directory
  Future<void> navigateToVolumes() async {
    await navigateTo(volumesDirectoryPath);
  }

  /// Navigate to parent directory
  Future<void> navigateUp() async {
    if (_currentDirectoryPath == null) return;
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
}
