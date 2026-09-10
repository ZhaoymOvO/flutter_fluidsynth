import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../i18n/i18n_service.dart';
import '../services/fluidsynth_service.dart';

class SettingsPage extends StatelessWidget {
  final FluidSynthService fluidService;
  final I18nService i18nService;

  const SettingsPage({
    super.key,
    required this.fluidService,
    required this.i18nService,
  });

  Future<void> _sideloadLibrary(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['dylib', 'dll', 'so'],
      dialogTitle: context.tr('settings_lib_sideload_btn'),
    );

    if (result != null && result.files.single.path != null) {
      final path = result.files.single.path!;
      final success = await fluidService.sideloadLibrary(path);
      if (context.mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(context.tr('settings_lib_status_loaded')),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  '${context.tr('settings_lib_status_failed')}: ${fluidService.loadError ?? ''}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _testSound(BuildContext context) async {
    final success = await fluidService.testNote();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success
                ? context.tr('settings_test_sound_success')
                : context.tr('settings_test_sound_failed'),
          ),
          backgroundColor: success ? Colors.green : Colors.orange,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('settings_page_title')),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Section 1: FluidSynth Library Status & Sideload
          _buildSectionHeader(context, context.tr('settings_section_lib')),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: theme.dividerColor.withValues(alpha: 0.4)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Status Badge
                  Row(
                    children: [
                      Icon(
                        fluidService.isLibraryLoaded
                            ? Icons.check_circle
                            : Icons.error_outline,
                        color: fluidService.isLibraryLoaded
                            ? Colors.green
                            : Colors.red,
                        size: 24,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          fluidService.isLibraryLoaded
                              ? context.tr('settings_lib_status_loaded')
                              : context.tr('settings_lib_status_failed'),
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: fluidService.isLibraryLoaded
                                ? Colors.green
                                : Colors.red,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  if (fluidService.isLibraryLoaded) ...[
                    _buildInfoRow(
                      context,
                      context.tr('settings_lib_version'),
                      fluidService.libraryVersion ?? 'Unknown',
                    ),
                    const SizedBox(height: 6),
                    _buildInfoRow(
                      context,
                      context.tr('settings_lib_path'),
                      fluidService.loadedLibraryPath ?? 'Default',
                    ),
                  ] else if (fluidService.loadError != null) ...[
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        fluidService.loadError!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.red.shade700,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 16),
                  Text(
                    context.tr('settings_lib_sideload_tip'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Sideload & Reset Buttons
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          icon: const Icon(Icons.folder_open, size: 18),
                          label: Text(context.tr('settings_lib_sideload_btn')),
                          onPressed: () => _sideloadLibrary(context),
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        child: Text(context.tr('settings_lib_reset_btn')),
                        onPressed: () async {
                          await fluidService.resetToDefaultLibrary();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content:
                                    Text(context.tr('settings_lib_reset_btn')),
                              ),
                            );
                          }
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Section 2: Audio Driver
          _buildSectionHeader(context, context.tr('settings_section_audio')),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: theme.dividerColor.withValues(alpha: 0.4)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(Icons.speaker),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          context.tr('settings_audio_driver_label'),
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                      DropdownButton<String>(
                        value: fluidService.audioDriverName,
                        underline: const SizedBox(),
                        items: fluidService.availableAudioDrivers
                            .map((driver) => DropdownMenuItem(
                                  value: driver,
                                  child: Text(driver),
                                ))
                            .toList(),
                        onChanged: (val) {
                          if (val != null) {
                            fluidService.setAudioDriver(val);
                          }
                        },
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  // Test sound button
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.volume_up),
                      label: Text(context.tr('settings_btn_test_sound')),
                      onPressed: () => _testSound(context),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Section 3: Language & Localization Adaptation
          _buildSectionHeader(context, context.tr('settings_section_i18n')),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: theme.dividerColor.withValues(alpha: 0.4)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Language Selection
                  Row(
                    children: [
                      const Icon(Icons.language),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          context.tr('settings_language_label'),
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                      DropdownButton<String>(
                        value: i18nService.currentLanguage,
                        underline: const SizedBox(),
                        items: [
                          DropdownMenuItem(
                            value: 'auto',
                            child: Text(
                                i18nService.getLanguageDisplayName('auto')),
                          ),
                          ...i18nService.supportedLanguages.map(
                            (lang) => DropdownMenuItem(
                              value: lang,
                              child: Text(
                                  i18nService.getLanguageDisplayName(lang)),
                            ),
                          ),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            i18nService.setLanguage(val);
                          }
                        },
                      ),
                    ],
                  ),

                  const Divider(height: 24),

                  // Localization Adaptation Option: Directly show control names
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    secondary: const Icon(Icons.code),
                    title: Text(
                      context.tr('settings_i18n_show_keys'),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Text(
                      context.tr('settings_i18n_show_keys_desc'),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    value: i18nService.showControlNames,
                    onChanged: (val) {
                      i18nService.setShowControlNames(val);
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }

  Widget _buildInfoRow(BuildContext context, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 90,
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
      ],
    );
  }
}
