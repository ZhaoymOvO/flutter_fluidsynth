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
                '${context.tr('settings_lib_status_failed')}: ${fluidService.loadError ?? ''}',
              ),
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
      body: ListenableBuilder(
        listenable: Listenable.merge([fluidService, i18nService]),
        builder: (context, _) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Section 1: FluidSynth Library Status & Sideload
              _buildSectionHeader(context, context.tr('settings_section_lib')),
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: theme.dividerColor.withValues(alpha: 0.4),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Status Badge
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
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

                      // Sideload & Reset Buttons (wrap if width is tight)
                      LayoutBuilder(
                        builder: (context, constraints) {
                          return Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth: constraints.maxWidth,
                                ),
                                child: FilledButton.icon(
                                  icon: const Icon(Icons.folder_open, size: 18),
                                  label: Text(
                                    context.tr('settings_lib_sideload_btn'),
                                  ),
                                  onPressed: () => _sideloadLibrary(context),
                                ),
                              ),
                              ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth: constraints.maxWidth,
                                ),
                                child: OutlinedButton(
                                  child: Text(
                                    context.tr('settings_lib_reset_btn'),
                                  ),
                                  onPressed: () async {
                                    await fluidService.resetToDefaultLibrary();
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            context.tr('settings_lib_reset_btn'),
                                          ),
                                        ),
                                      );
                                    }
                                  },
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Section 2: Audio Driver & Volume
              _buildSectionHeader(
                context,
                context.tr('settings_section_audio'),
              ),
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: theme.dividerColor.withValues(alpha: 0.4),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      // Audio Driver Selection (Adaptive Wrap)
                      _buildAdaptiveDropdownTile<String>(
                        context: context,
                        icon: const Icon(Icons.speaker),
                        label: context.tr('settings_audio_driver_label'),
                        value: fluidService.audioDriverName,
                        items: fluidService.availableAudioDrivers
                            .map(
                              (driver) => DropdownMenuItem(
                                value: driver,
                                child: Text(
                                  driver,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (val) {
                          if (val != null) {
                            fluidService.setAudioDriver(val);
                          }
                        },
                      ),
                      const Divider(height: 24),
                      // Volume Slider
                      Row(
                        children: [
                          Icon(
                            fluidService.volume > 0.5
                                ? Icons.volume_up
                                : (fluidService.volume > 0
                                      ? Icons.volume_down
                                      : Icons.volume_mute),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              context.tr('player_volume_label'),
                              style: theme.textTheme.titleMedium,
                            ),
                          ),
                          Text(
                            '${(fluidService.volume * 100).round()}%',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      Slider(
                        value: fluidService.volume,
                        min: 0.0,
                        max: 1.0,
                        divisions: 20,
                        label: '${(fluidService.volume * 100).round()}%',
                        onChanged: (val) {
                          fluidService.setVolume(val);
                        },
                      ),
                      const Divider(height: 24),
                      // Test sound button
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.music_note),
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
                  side: BorderSide(
                    color: theme.dividerColor.withValues(alpha: 0.4),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Language Selection (Adaptive Wrap)
                      _buildAdaptiveDropdownTile<String>(
                        context: context,
                        icon: const Icon(Icons.language),
                        label: context.tr('settings_language_label'),
                        value: i18nService.currentLanguage,
                        items: [
                          DropdownMenuItem(
                            value: 'auto',
                            child: Text(
                              i18nService.getLanguageDisplayName('auto'),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          ...i18nService.supportedLanguages.map(
                            (lang) => DropdownMenuItem(
                              value: lang,
                              child: Text(
                                i18nService.getLanguageDisplayName(lang),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            i18nService.setLanguage(val);
                          }
                        },
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
          );
        },
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
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 280) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 100,
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
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildAdaptiveDropdownTile<T>({
    required BuildContext context,
    required Widget icon,
    required String label,
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    final theme = Theme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final textDirection = Directionality.of(context);

        // Measure label text width
        final labelPainter = TextPainter(
          text: TextSpan(
            text: label,
            style: theme.textTheme.titleMedium,
          ),
          textDirection: textDirection,
          maxLines: 1,
        )..layout();

        // Measure widest dropdown item text
        double maxItemWidth = 0;
        for (final item in items) {
          final child = item.child;
          String text = '';
          if (child is Text) {
            text = child.data ?? '';
          }
          final itemPainter = TextPainter(
            text: TextSpan(
              text: text,
              style: theme.textTheme.bodyMedium,
            ),
            textDirection: textDirection,
            maxLines: 1,
          )..layout();
          if (itemPainter.width > maxItemWidth) {
            maxItemWidth = itemPainter.width;
          }
        }

        // Icon(24) + spacing(12) + label + gap(16) + dropdown(item + arrow(24) + padding(24))
        final totalNeeded = 24 + 12 + labelPainter.width + 16 + maxItemWidth + 48;
        final isWideEnough = constraints.maxWidth >= totalNeeded;

        if (isWideEnough) {
          return Row(
            children: [
              icon,
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              const SizedBox(width: 8),
              DropdownButtonHideUnderline(
                child: DropdownButton<T>(
                  value: value,
                  items: items,
                  onChanged: onChanged,
                ),
              ),
            ],
          );
        } else {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  icon,
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      label,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: theme.dividerColor.withValues(alpha: 0.3),
                  ),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<T>(
                    value: value,
                    isExpanded: true,
                    items: items,
                    onChanged: onChanged,
                  ),
                ),
              ),
            ],
          );
        }
      },
    );
  }
}
