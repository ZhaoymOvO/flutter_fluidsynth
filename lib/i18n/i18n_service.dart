import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:csv/csv.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Localization service that parses a single CSV file.
///
/// Features:
/// 1. All strings are stored in `assets/i18n/strings.csv`.
/// 2. Columns correspond to language codes: [control_name, zh_TW, zh_CN, en, ja].
/// 3. Blank lines in the CSV separate strings across different pages/screens.
/// 4. Provides a "Localization Adaptation" option that directly displays the
///    control/widget name instead of the translated text.
class I18nService extends ChangeNotifier {
  static const String _prefLanguageKey = 'i18n_selected_language';
  static const String _prefShowControlNamesKey = 'i18n_show_control_names';

  String _currentLanguage = 'auto';
  bool _showControlNames = false;

  // Key: control_name, Value: Map<langCode, translatedString>
  final Map<String, Map<String, String>> _stringTable = {};
  final List<String> _supportedLanguages = ['zh_TW', 'zh_CN', 'en', 'ja'];

  bool _isLoaded = false;

  String get currentLanguage => _currentLanguage;
  bool get showControlNames => _showControlNames;
  bool get isLoaded => _isLoaded;
  List<String> get supportedLanguages => List.unmodifiable(_supportedLanguages);

  /// Human-readable name for each language code
  String getLanguageDisplayName(String code) {
    switch (code) {
      case 'zh_TW':
        return '繁體中文 (Traditional Chinese)';
      case 'zh_CN':
        return '简体中文 (Simplified Chinese)';
      case 'en':
        return 'English';
      case 'ja':
        return '日本語 (Japanese)';
      case 'auto':
      default:
        return '跟隨系統 / System Default';
    }
  }

  /// Initialize and load strings from the CSV asset
  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    _currentLanguage = prefs.getString(_prefLanguageKey) ?? 'auto';
    _showControlNames = prefs.getBool(_prefShowControlNamesKey) ?? false;

    await reloadCsv();
  }

  /// Load and parse the single CSV localization asset
  Future<void> reloadCsv() async {
    try {
      final csvData = await rootBundle.loadString('assets/i18n/strings.csv');
      parseCsvContent(csvData);
      _isLoaded = true;
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading i18n CSV: $e');
    }
  }

  /// Parses CSV content respecting empty line separations between pages
  void parseCsvContent(String csvData) {
    _stringTable.clear();
    _isLoaded = true;

    final lines = const LineSplitter().convert(csvData);
    List<String> header = [];

    for (var rawLine in lines) {
      final trimmed = rawLine.trim();
      // Skip empty lines (page separators) and comment lines starting with '#'
      if (trimmed.isEmpty || trimmed.startsWith('#')) {
        continue;
      }

      final row = const CsvToListConverter(shouldParseNumbers: false)
          .convert(rawLine)
          .firstOrNull;

      if (row == null || row.isEmpty) continue;

      if (header.isEmpty) {
        // Parse header row
        header = row.map((e) => e.toString().trim()).toList();
        continue;
      }

      final controlName = row[0].toString().trim();
      if (controlName.isEmpty) continue;

      final langMap = <String, String>{};
      for (int i = 1; i < row.length && i < header.length; i++) {
        final langCode = header[i];
        final val = row[i].toString().trim();
        langMap[langCode] = val;
      }

      _stringTable[controlName] = langMap;
    }
  }

  /// Set the user's preferred language
  Future<void> setLanguage(String langCode) async {
    _currentLanguage = langCode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefLanguageKey, langCode);
    notifyListeners();
  }

  /// Toggle or set the "Localization Adaptation Mode: Show Control Names Directly"
  Future<void> setShowControlNames(bool show) async {
    _showControlNames = show;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefShowControlNamesKey, show);
    notifyListeners();
  }

  /// Determine the effective language code
  String get effectiveLanguage {
    if (_currentLanguage != 'auto') {
      return _currentLanguage;
    }
    final locale = WidgetsBinding.instance.platformDispatcher.locale;
    final code = '${locale.languageCode}_${locale.countryCode}';
    if (code.startsWith('zh_TW') || code.startsWith('zh_HK') || code.startsWith('zh_MO')) {
      return 'zh_TW';
    } else if (code.startsWith('zh')) {
      return 'zh_CN';
    } else if (code.startsWith('ja')) {
      return 'ja';
    }
    return 'en';
  }

  /// Translate a string given its [controlName]
  String t(String controlName, [Map<String, String>? params]) {
    // If the user enabled the localization adaptation option, directly show control name!
    if (_showControlNames) {
      return controlName;
    }

    final langMap = _stringTable[controlName];
    if (langMap == null) {
      return controlName;
    }

    final lang = effectiveLanguage;
    String? text = langMap[lang];

    // Fallbacks
    if (text == null || text.isEmpty) {
      text = langMap['zh_TW'] ?? langMap['en'] ?? controlName;
    }

    if (params != null && params.isNotEmpty) {
      params.forEach((key, value) {
        text = text!.replaceAll('{$key}', value);
      });
    }

    return text ?? controlName;
  }
}

/// InheritedWidget for fast, clean access in the widget tree
class I18nScope extends InheritedNotifier<I18nService> {
  const I18nScope({
    super.key,
    required I18nService service,
    required super.child,
  }) : super(notifier: service);

  static I18nService of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<I18nScope>();
    return scope!.notifier!;
  }
}

extension I18nExtension on BuildContext {
  String tr(String controlName, [Map<String, String>? params]) {
    return I18nScope.of(this).t(controlName, params);
  }
}
