import 'dart:ui';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import '../i18n/i18n_service.dart';
import '../services/file_service.dart';
import '../services/fluidsynth_service.dart';
import '../services/soundfont_service.dart';
import 'player_widget.dart';
import 'settings_page.dart';
import 'soundfont_dialog.dart';

class MainNavigationPage extends StatefulWidget {
  final FileService fileService;
  final FluidSynthService fluidService;
  final SoundFontService soundFontService;
  final I18nService i18nService;

  const MainNavigationPage({
    super.key,
    required this.fileService,
    required this.fluidService,
    required this.soundFontService,
    required this.i18nService,
  });

  @override
  State<MainNavigationPage> createState() => _MainNavigationPageState();
}

class _MainNavigationPageState extends State<MainNavigationPage>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.fluidService.stop();
    super.dispose();
  }

  /// Terminates playback whenever Flutter triggers a hot reload
  @override
  void reassemble() {
    super.reassemble();
    widget.fluidService.stop();
  }

  /// Terminates playback when application requests exit (e.g. desktop window close or Alt+F4 / Cmd+Q)
  @override
  Future<AppExitResponse> didRequestAppExit() async {
    widget.fluidService.stop();
    return AppExitResponse.exit;
  }

  /// Terminates playback when app lifecycle transitions to detached/paused
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached || state == AppLifecycleState.paused) {
      widget.fluidService.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.fileService,
      builder: (context, _) {
        return PopScope(
          canPop: !widget.fileService.canNavigateUp,
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) return;
            if (widget.fileService.canNavigateUp) {
              widget.fileService.navigateUp();
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
                  if (widget.fileService.canNavigateUp) {
                    widget.fileService.navigateUp();
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
                  if (widget.fileService.canNavigateUp) {
                    widget.fileService.navigateUp();
                  }
                }
              },
              child: Scaffold(
                body: Column(
                  children: [
                    Expanded(
                      child: FileBrowserView(
                        fileService: widget.fileService,
                        fluidService: widget.fluidService,
                        soundFontService: widget.soundFontService,
                        i18nService: widget.i18nService,
                      ),
                    ),
                    // Persistent Player Bar
                    ListenableBuilder(
                      listenable: Listenable.merge([widget.fluidService, widget.soundFontService]),
                      builder: (ctx, _) {
                        return PlayerWidget(
                          fluidService: widget.fluidService,
                          soundFontService: widget.soundFontService,
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class FileBrowserView extends StatelessWidget {
  final FileService fileService;
  final FluidSynthService fluidService;
  final SoundFontService soundFontService;
  final I18nService i18nService;

  const FileBrowserView({
    super.key,
    required this.fileService,
    required this.fluidService,
    required this.soundFontService,
    required this.i18nService,
  });

  Future<void> _handleFileClick(BuildContext context, DiscoveredFileItem item, {bool singleOnly = false}) async {
    if (item.isDirectory) {
      await fileService.navigateTo(item.path);
      return;
    }

    if (item.isMidi) {
      // If tapping the currently active MIDI track and not single-only override, toggle pause/play
      if (!singleOnly &&
          fluidService.currentMidiPath != null &&
          p.equals(fluidService.currentMidiPath!, item.path)) {
        if (fluidService.isPlaying) {
          fluidService.pause();
          return;
        } else if (fluidService.isPaused) {
          fluidService.resume();
          return;
        }
      }

      // Check if FluidSynth library is loaded!
      if (!fluidService.isLibraryLoaded) {
        _showNoFluidSynthDialog(context);
        return;
      }

      // Check if SoundFont is loaded or available
      if (!fluidService.hasLoadedSoundFont) {
        // Try auto-loading active SoundFont from service if exists
        final activeSf = soundFontService.activeSoundFontPath;
        if (activeSf != null) {
          final loaded = await fluidService.loadSoundFont(activeSf);
          if (!loaded) {
            if (context.mounted) {
              _showNoSoundFontDialog(context);
            }
            return;
          }
        } else {
          _showNoSoundFontDialog(context);
          return;
        }
      }

      // Populate playlist: singleOnly or all MIDI files in current folder
      if (singleOnly) {
        fluidService.setPlaylist([item.path], initialIndex: 0);
      } else {
        final allMidi = fileService.currentFiles
            .where((f) => f.isMidi)
            .map((f) => f.path)
            .toList();
        final idx = allMidi.indexWhere((fPath) => p.equals(fPath, item.path));
        fluidService.setPlaylist(allMidi, initialIndex: idx >= 0 ? idx : 0);
      }

      // Play MIDI file
      final success = await fluidService.playMidi(item.path);
      if (!success && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.tr('common_error')),
            backgroundColor: Colors.red,
          ),
        );
      }
    } else if (item.isSoundFont) {
      // Save SoundFont to known list and activate it!
      final added = await soundFontService.addAndActivateSoundFont(item.path);
      if (added) {
        if (fluidService.isLibraryLoaded) {
          final loaded = await fluidService.loadSoundFont(item.path);
          if (context.mounted) {
            if (loaded) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('${context.tr('sf_toast_added')}: ${item.name}'),
                  duration: const Duration(seconds: 2),
                ),
              );
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(context.tr('sf_load_error')),
                  backgroundColor: Colors.red,
                ),
              );
            }
          }
        } else {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(context.tr('sf_toast_lib_missing')),
                backgroundColor: Colors.orange.shade800,
                duration: const Duration(seconds: 4),
                action: SnackBarAction(
                  label: context.tr('home_btn_goto_settings'),
                  textColor: Colors.white,
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => SettingsPage(
                          fluidService: fluidService,
                          i18nService: i18nService,
                        ),
                      ),
                    );
                  },
                ),
              ),
            );
          }
        }
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(context.tr('sf_load_error')),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  void _showNoFluidSynthDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('common_warning')),
        content: Text(context.tr('home_prompt_lib_not_loaded')),
        actions: [
          TextButton(
            child: Text(context.tr('common_cancel')),
            onPressed: () => Navigator.of(ctx).pop(),
          ),
          FilledButton(
            child: Text(context.tr('home_btn_goto_settings')),
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => SettingsPage(
                    fluidService: fluidService,
                    i18nService: i18nService,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  void _showNoSoundFontDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('common_warning')),
        content: Text(context.tr('home_prompt_select_soundfont')),
        actions: [
          TextButton(
            child: Text(context.tr('common_ok')),
            onPressed: () => Navigator.of(ctx).pop(),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListenableBuilder(
      listenable: Listenable.merge([fileService, fluidService, soundFontService]),
      builder: (ctx, _) {
        return Scaffold(
          appBar: AppBar(
            toolbarHeight: 52,
            titleSpacing: 4,
            elevation: 0,
            backgroundColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            title: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.home, size: 20),
                  tooltip: context.tr('home_btn_home'),
                  onPressed: () => fileService.navigateToHome(),
                ),
                IconButton(
                  icon: const Icon(Icons.storage_rounded, size: 20),
                  tooltip: context.tr('home_btn_volumes'),
                  onPressed: () => fileService.navigateToVolumes(),
                ),
                IconButton(
                  icon: const Icon(Icons.arrow_upward, size: 20),
                  tooltip: context.tr('home_btn_parent_dir'),
                  onPressed: fileService.canNavigateUp
                      ? () => fileService.navigateUp()
                      : null,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    fileService.isDrivesView
                        ? context.tr('home_this_pc')
                        : (fileService.currentDirectoryPath ?? ''),
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            actions: [
              IconButton(
                tooltip: context.tr('home_btn_refresh'),
                icon: const Icon(Icons.refresh, size: 20),
                onPressed: () => fileService.scanCurrentDirectory(),
              ),
              IconButton(
                tooltip: context.tr('home_tab_soundfonts'),
                icon: const Icon(Icons.piano, size: 20),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => SoundFontManagerPage(
                        soundFontService: soundFontService,
                        fluidService: fluidService,
                      ),
                    ),
                  );
                },
              ),
              IconButton(
                tooltip: context.tr('home_tab_settings'),
                icon: const Icon(Icons.settings, size: 20),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => SettingsPage(
                        fluidService: fluidService,
                        i18nService: i18nService,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(width: 4),
            ],
          ),
          body: Column(
            children: [
              // FluidSynth dynamic library not loaded warning banner
              if (!fluidService.isLibraryLoaded)
                Container(
                  color: theme.colorScheme.errorContainer,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, color: theme.colorScheme.onErrorContainer, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          context.tr('home_lib_not_loaded'),
                          style: TextStyle(
                            color: theme.colorScheme.onErrorContainer,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => SettingsPage(
                                fluidService: fluidService,
                                i18nService: i18nService,
                              ),
                            ),
                          );
                        },
                        child: Text(context.tr('home_btn_goto_settings')),
                      ),
                    ],
                  ),
                ),

              // Permission check warning if needed
              if (!fileService.permissionGranted)
                Container(
                  color: Colors.amber.shade100,
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const Icon(Icons.warning, color: Colors.amber),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          context.tr('home_permission_denied'),
                          style: const TextStyle(color: Colors.black87),
                        ),
                      ),
                      TextButton(
                        onPressed: () => fileService.requestStoragePermissions(),
                        child: Text(context.tr('home_btn_request_permission')),
                      ),
                    ],
                  ),
                ),


              // Loading indicator or file list
              Expanded(
                child: fileService.isLoading
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CircularProgressIndicator(),
                            const SizedBox(height: 12),
                            Text(context.tr('common_loading')),
                          ],
                        ),
                      )
                    : fileService.currentFiles.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(32),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.folder_open, size: 64, color: theme.disabledColor),
                                  const SizedBox(height: 16),
                                  Text(
                                    context.tr('home_no_files_found'),
                                    textAlign: TextAlign.center,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : ListView.separated(
                            itemCount: fileService.currentFiles.length,
                            separatorBuilder: (context, index) => const Divider(height: 1),
                            itemBuilder: (ctx, index) {
                              final item = fileService.currentFiles[index];
                              return _buildFileTile(context, item);
                            },
                          ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFileTile(BuildContext context, DiscoveredFileItem item) {
    final theme = Theme.of(context);

    if (item.isDirectory) {
      return ListTile(
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.secondaryContainer,
          child: Icon(
            item.isDrive ? Icons.storage_rounded : Icons.folder_rounded,
            color: theme.colorScheme.onSecondaryContainer,
            size: 20,
          ),
        ),
        title: Text(
          item.name,
          style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
        ),
        subtitle: Text(
          item.isDrive
              ? context.tr('home_item_badge_drive')
              : context.tr('home_item_badge_directory'),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: Icon(
          Icons.chevron_right_rounded,
          size: 20,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        onTap: () => _handleFileClick(context, item),
      );
    }

    if (item.isMidi) {
      final isCurrentTrack = fluidService.currentMidiPath != null &&
          p.equals(fluidService.currentMidiPath!, item.path);
      final isCurrentPlaying = isCurrentTrack && fluidService.isPlaying;

      return ListTile(
        leading: CircleAvatar(
          backgroundColor: isCurrentPlaying
              ? theme.colorScheme.primary
              : isCurrentTrack
                  ? theme.colorScheme.primaryContainer
                  : theme.colorScheme.surfaceContainerHighest,
          child: Icon(
            isCurrentPlaying
                ? Icons.equalizer_rounded
                : isCurrentTrack
                    ? Icons.play_arrow_rounded
                    : Icons.music_note_rounded,
            color: isCurrentPlaying
                ? theme.colorScheme.onPrimary
                : isCurrentTrack
                    ? theme.colorScheme.onPrimaryContainer
                    : theme.colorScheme.onSurfaceVariant,
            size: 20,
          ),
        ),
        title: Text(
          item.name,
          style: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: isCurrentTrack ? FontWeight.bold : FontWeight.w500,
            color: isCurrentTrack ? theme.colorScheme.primary : null,
          ),
        ),
        subtitle: Text(
          '${context.tr('home_item_badge_midi')} • ${item.formattedSize}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: IconButton.filledTonal(
          tooltip: context.tr('home_btn_add_next'),
          icon: const Icon(Icons.playlist_add_rounded, size: 20),
          style: IconButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.all(6),
          ),
          onPressed: () {
            fluidService.addToPlaylistNext(item.path);
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('${context.tr('home_toast_added_next')}: ${item.name}'),
                duration: const Duration(seconds: 2),
                behavior: SnackBarBehavior.floating,
              ),
            );
          },
        ),
        onTap: () => _handleFileClick(context, item),
      );
    }

    // SoundFont (.sf2 / .sf3 / .dls)
    final isCurrentSf = (soundFontService.activeSoundFontPath != null &&
            p.equals(soundFontService.activeSoundFontPath!, item.path)) ||
        (fluidService.loadedSfPath != null &&
            p.equals(fluidService.loadedSfPath!, item.path));

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: isCurrentSf ? theme.colorScheme.tertiary : theme.colorScheme.tertiaryContainer,
        child: Icon(
          Icons.piano_rounded,
          color: isCurrentSf ? theme.colorScheme.onTertiary : theme.colorScheme.onTertiaryContainer,
          size: 20,
        ),
      ),
      title: Text(
        item.name,
        style: theme.textTheme.bodyLarge?.copyWith(
          fontWeight: isCurrentSf ? FontWeight.bold : FontWeight.w500,
          color: isCurrentSf ? theme.colorScheme.tertiary : null,
        ),
      ),
      subtitle: Text(
        '${context.tr('home_item_badge_soundfont')} • ${item.formattedSize}',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: isCurrentSf
          ? Chip(
              label: Text(context.tr('sf_status_active')),
              backgroundColor: theme.colorScheme.tertiaryContainer,
              labelStyle: TextStyle(
                color: theme.colorScheme.onTertiaryContainer,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            )
          : OutlinedButton(
              onPressed: () => _handleFileClick(context, item),
              child: Text(context.tr('sf_btn_set_active')),
            ),
      onTap: () => _handleFileClick(context, item),
    );
  }
}
