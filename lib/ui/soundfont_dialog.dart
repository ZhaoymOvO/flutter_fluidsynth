import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../i18n/i18n_service.dart';
import '../services/fluidsynth_service.dart';
import '../services/soundfont_service.dart';

class SoundFontManagerPage extends StatelessWidget {
  final SoundFontService soundFontService;
  final FluidSynthService fluidService;

  const SoundFontManagerPage({
    super.key,
    required this.soundFontService,
    required this.fluidService,
  });

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  Future<void> _pickSoundFont(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['sf2', 'sf3', 'dls'],
      dialogTitle: context.tr('sf_btn_add_manual'),
    );

    if (result != null && result.files.single.path != null) {
      final path = result.files.single.path!;
      final added = await soundFontService.addAndActivateSoundFont(path);
      if (added) {
        await fluidService.loadSoundFont(path);
      }
      if (context.mounted) {
        if (added) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.tr('sf_toast_added'))),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.tr('sf_load_error'))),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([soundFontService, fluidService]),
      builder: (context, _) {
        final theme = Theme.of(context);
        final knownList = soundFontService.knownSoundFonts;
        final activePath = soundFontService.activeSoundFontPath;

        return Scaffold(
          appBar: AppBar(
            title: Text(context.tr('sf_manager_title')),
            actions: [
              IconButton(
                icon: const Icon(Icons.add),
                tooltip: context.tr('sf_btn_add_manual'),
                onPressed: () => _pickSoundFont(context),
              ),
            ],
          ),
          body: knownList.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.library_music_outlined,
                          size: 64,
                          color: theme.disabledColor,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          context.tr('sf_empty_list'),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 24),
                        FilledButton.icon(
                          icon: const Icon(Icons.add),
                          label: Text(context.tr('sf_btn_add_manual')),
                          onPressed: () => _pickSoundFont(context),
                        ),
                      ],
                    ),
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: Text(
                        context.tr('sf_manager_subtitle'),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: ListView.separated(
                        itemCount: knownList.length,
                        separatorBuilder: (context, index) =>
                            const Divider(height: 1),
                        itemBuilder: (ctx, index) {
                          final item = knownList[index];
                          final isActive = item.path == activePath;

                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 6,
                            ),
                            leading: CircleAvatar(
                              backgroundColor: isActive
                                  ? theme.colorScheme.tertiary
                                  : theme.colorScheme.surfaceContainerHighest,
                              child: Icon(
                                Icons.piano_rounded,
                                color: isActive
                                    ? theme.colorScheme.onTertiary
                                    : theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            title: Text(
                              item.name,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: isActive
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.path,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (item.fileSize > 0)
                                  Text(
                                    _formatBytes(item.fileSize),
                                    style:
                                        theme.textTheme.labelSmall?.copyWith(
                                      color: theme.colorScheme.secondary,
                                    ),
                                  ),
                              ],
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (isActive)
                                  Chip(
                                    label: Text(context.tr('sf_status_active')),
                                    backgroundColor:
                                        theme.colorScheme.tertiaryContainer,
                                    labelStyle: TextStyle(
                                      color:
                                          theme.colorScheme.onTertiaryContainer,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  )
                                else
                                  TextButton(
                                    child:
                                        Text(context.tr('sf_btn_set_active')),
                                    onPressed: () async {
                                      await soundFontService
                                          .setActiveSoundFont(item.path);
                                      await fluidService
                                          .loadSoundFont(item.path);
                                      if (ctx.mounted) {
                                        ScaffoldMessenger.of(ctx).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                                context.tr('sf_toast_switched')),
                                            duration:
                                                const Duration(seconds: 2),
                                          ),
                                        );
                                      }
                                    },
                                  ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline,
                                      size: 20),
                                  tooltip: context.tr('sf_btn_remove'),
                                  onPressed: () async {
                                    await soundFontService
                                        .removeSoundFont(item.path);
                                    if (soundFontService.activeSoundFontPath !=
                                        null) {
                                      await fluidService.loadSoundFont(
                                          soundFontService
                                              .activeSoundFontPath!);
                                    } else {
                                      await fluidService.unloadSoundFont();
                                    }
                                    if (ctx.mounted) {
                                      ScaffoldMessenger.of(ctx).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                              context.tr('sf_toast_removed')),
                                          duration:
                                              const Duration(seconds: 2),
                                        ),
                                      );
                                    }
                                  },
                                ),
                              ],
                            ),
                            onTap: () async {
                              if (!isActive) {
                                await soundFontService
                                    .setActiveSoundFont(item.path);
                                await fluidService.loadSoundFont(item.path);
                                if (ctx.mounted) {
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                    SnackBar(
                                      content:
                                          Text(context.tr('sf_toast_switched')),
                                      duration: const Duration(seconds: 2),
                                    ),
                                  );
                                }
                              }
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
          floatingActionButton: knownList.isNotEmpty
              ? FloatingActionButton.extended(
                  onPressed: () => _pickSoundFont(context),
                  icon: const Icon(Icons.add),
                  label: Text(context.tr('sf_btn_add_manual')),
                )
              : null,
        );
      },
    );
  }
}

/// Backward compatibility alias
typedef SoundFontManagerSheet = SoundFontManagerPage;
