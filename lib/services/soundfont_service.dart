import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

class SoundFontItem {
  final String path;
  final String name;
  final int fileSize;
  final DateTime addedAt;

  SoundFontItem({
    required this.path,
    required this.name,
    required this.fileSize,
    required this.addedAt,
  });

  Map<String, dynamic> toJson() => {
        'path': path,
        'name': name,
        'fileSize': fileSize,
        'addedAt': addedAt.toIso8601String(),
      };

  factory SoundFontItem.fromJson(Map<String, dynamic> json) => SoundFontItem(
        path: json['path'] as String,
        name: json['name'] as String,
        fileSize: json['fileSize'] as int? ?? 0,
        addedAt: DateTime.tryParse(json['addedAt'] as String? ?? '') ??
            DateTime.now(),
      );
}

class SoundFontService extends ChangeNotifier {
  static const String _prefKnownListKey = 'known_soundfonts_list';
  static const String _prefActiveSoundFontKey = 'active_soundfont_path';

  final List<SoundFontItem> _knownSoundFonts = [];
  String? _activeSoundFontPath;
  bool _isInitialized = false;

  List<SoundFontItem> get knownSoundFonts =>
      List.unmodifiable(_knownSoundFonts);
  String? get activeSoundFontPath => _activeSoundFontPath;
  bool get isInitialized => _isInitialized;

  SoundFontItem? get activeSoundFont {
    if (_activeSoundFontPath == null) return null;
    return _knownSoundFonts
        .where((item) => p.equals(item.path, _activeSoundFontPath!))
        .firstOrNull;
  }

  Future<void> initialize() async {
    if (_isInitialized) return;
    final prefs = await SharedPreferences.getInstance();

    final rawJson = prefs.getString(_prefKnownListKey);
    if (rawJson != null && rawJson.isNotEmpty) {
      try {
        final list = jsonDecode(rawJson) as List<dynamic>;
        _knownSoundFonts.clear();
        for (var item in list) {
          final sfItem = SoundFontItem.fromJson(item as Map<String, dynamic>);
          _knownSoundFonts.add(SoundFontItem(
            path: p.normalize(sfItem.path),
            name: sfItem.name,
            fileSize: sfItem.fileSize,
            addedAt: sfItem.addedAt,
          ));
        }
      } catch (e) {
        debugPrint('Error parsing known soundfonts: $e');
      }
    }

    _activeSoundFontPath = prefs.getString(_prefActiveSoundFontKey);
    if (_activeSoundFontPath != null) {
      _activeSoundFontPath = p.normalize(_activeSoundFontPath!);
    }

    // If active path is not valid or not in list, fallback to first if available
    if (_activeSoundFontPath != null &&
        !_knownSoundFonts.any((e) => p.equals(e.path, _activeSoundFontPath!))) {
      _activeSoundFontPath =
          _knownSoundFonts.isNotEmpty ? _knownSoundFonts.first.path : null;
    } else if (_activeSoundFontPath == null && _knownSoundFonts.isNotEmpty) {
      _activeSoundFontPath = _knownSoundFonts.first.path;
    }

    _isInitialized = true;
    notifyListeners();
  }

  /// Adds a SoundFont to the known list (if not already present) and sets it as active
  Future<bool> addAndActivateSoundFont(String rawFilePath) async {
    final filePath = p.normalize(rawFilePath);
    final file = File(filePath);
    if (!await file.exists()) {
      return false;
    }

    final filename = p.basename(filePath);
    final size = await file.length();

    // Check if already in list
    final existingIndex =
        _knownSoundFonts.indexWhere((e) => p.equals(e.path, filePath));
    if (existingIndex >= 0) {
      // Move to top
      final existing = _knownSoundFonts.removeAt(existingIndex);
      _knownSoundFonts.insert(0, existing);
    } else {
      _knownSoundFonts.insert(
        0,
        SoundFontItem(
          path: filePath,
          name: filename,
          fileSize: size,
          addedAt: DateTime.now(),
        ),
      );
    }

    _activeSoundFontPath = filePath;
    await _saveToPrefs();
    notifyListeners();
    return true;
  }

  /// Sets an existing SoundFont as active
  Future<void> setActiveSoundFont(String rawFilePath) async {
    final filePath = p.normalize(rawFilePath);
    if (_activeSoundFontPath != null &&
        p.equals(_activeSoundFontPath!, filePath)) {
      return;
    }
    _activeSoundFontPath = filePath;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefActiveSoundFontKey, filePath);
    notifyListeners();
  }

  /// Removes a SoundFont from the known list
  Future<void> removeSoundFont(String rawFilePath) async {
    final filePath = p.normalize(rawFilePath);
    _knownSoundFonts.removeWhere((e) => p.equals(e.path, filePath));
    if (_activeSoundFontPath != null &&
        p.equals(_activeSoundFontPath!, filePath)) {
      _activeSoundFontPath =
          _knownSoundFonts.isNotEmpty ? _knownSoundFonts.first.path : null;
    }
    await _saveToPrefs();
    notifyListeners();
  }

  Future<void> _saveToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = _knownSoundFonts.map((e) => e.toJson()).toList();
    await prefs.setString(_prefKnownListKey, jsonEncode(jsonList));
    if (_activeSoundFontPath != null) {
      await prefs.setString(_prefActiveSoundFontKey, _activeSoundFontPath!);
    } else {
      await prefs.remove(_prefActiveSoundFontKey);
    }
  }
}
