import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../i18n/i18n_service.dart';
import '../services/fluidsynth_service.dart';

class PlaylistSheet extends StatelessWidget {
  final FluidSynthService fluidService;

  const PlaylistSheet({super.key, required this.fluidService});

  static void show(BuildContext context, FluidSynthService fluidService) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      constraints: const BoxConstraints(
        maxWidth: 640,
      ),
      builder: (ctx) => PlaylistSheet(fluidService: fluidService),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListenableBuilder(
      listenable: fluidService,
      builder: (context, _) {
        final playlist = fluidService.playlist;
        final currentIndex = fluidService.playlistIndex;

        return SizedBox(
          height: MediaQuery.of(context).size.height * 0.75,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header Row
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.queue_music_rounded,
                                color: theme.colorScheme.primary,
                                size: 22,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '${context.tr('playlist_title')} (${playlist.length} ${context.tr('playlist_tracks_count')})',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              if (playlist.isNotEmpty)
                                IconButton(
                                  icon: const Icon(Icons.delete_sweep_outlined),
                                  color: theme.colorScheme.error,
                                  tooltip: context.tr('playlist_clear'),
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () => fluidService.clearPlaylist(),
                                ),
                              IconButton(
                                icon: const Icon(Icons.close_rounded),
                                tooltip: context.tr('common_close'),
                                visualDensity: VisualDensity.compact,
                                onPressed: () => Navigator.of(context).pop(),
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 1),

                        // Playlist Content
                        Expanded(
                          child: playlist.isEmpty
                              ? Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.music_off_outlined,
                                        size: 48,
                                        color: theme
                                            .colorScheme
                                            .onSurfaceVariant
                                            .withValues(alpha: 0.5),
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        context.tr('playlist_empty'),
                                        style: theme.textTheme.bodyMedium
                                            ?.copyWith(
                                              color: theme
                                                  .colorScheme
                                                  .onSurfaceVariant,
                                            ),
                                      ),
                                    ],
                                  ),
                                )
                              : ReorderableListView.builder(
                                  buildDefaultDragHandles: false,
                                  itemCount: playlist.length,
                                  onReorder: (oldIndex, newIndex) {
                                    fluidService.reorderPlaylist(
                                      oldIndex,
                                      newIndex,
                                    );
                                  },
                                  itemBuilder: (context, index) {
                                    final trackPath = playlist[index];
                                    final isPlaying = (index == currentIndex);
                                    final filename = p.basename(trackPath);

                                    return Material(
                                      key: ValueKey('$trackPath-$index'),
                                      color: isPlaying
                                          ? theme.colorScheme.primaryContainer
                                                .withValues(alpha: 0.35)
                                          : Colors.transparent,
                                      child: ListTile(
                                        dense: true,
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                              horizontal: 16,
                                              vertical: 0,
                                            ),
                                        leading: isPlaying
                                            ? CircleAvatar(
                                                radius: 13,
                                                backgroundColor:
                                                    theme.colorScheme.primary,
                                                child: Icon(
                                                  Icons.equalizer_rounded,
                                                  size: 15,
                                                  color: theme
                                                      .colorScheme
                                                      .onPrimary,
                                                ),
                                              )
                                            : SizedBox(
                                                width: 26,
                                                child: Center(
                                                  child: Text(
                                                    '${index + 1}',
                                                    style: theme
                                                        .textTheme
                                                        .bodySmall
                                                        ?.copyWith(
                                                          color: theme
                                                              .colorScheme
                                                              .onSurfaceVariant,
                                                          fontWeight:
                                                              FontWeight.w500,
                                                        ),
                                                  ),
                                                ),
                                              ),
                                        title: Text(
                                          filename,
                                          style: theme.textTheme.bodyMedium
                                              ?.copyWith(
                                                fontWeight: isPlaying
                                                    ? FontWeight.bold
                                                    : FontWeight.normal,
                                                color: isPlaying
                                                    ? theme.colorScheme.primary
                                                    : null,
                                              ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        trailing: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(
                                              icon: const Icon(
                                                Icons.close_rounded,
                                                size: 18,
                                              ),
                                              tooltip: context.tr(
                                                'sf_btn_remove',
                                              ),
                                              visualDensity:
                                                  VisualDensity.compact,
                                              onPressed: () {
                                                fluidService.removeFromPlaylist(
                                                  index,
                                                );
                                              },
                                            ),
                                            ReorderableDragStartListener(
                                              index: index,
                                              child: Padding(
                                                padding: const EdgeInsets.only(
                                                  left: 4,
                                                  right: 4,
                                                ),
                                                child: Icon(
                                                  Icons.drag_handle_rounded,
                                                  size: 20,
                                                  color: theme
                                                      .colorScheme
                                                      .onSurfaceVariant,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        onTap: () {
                                          fluidService.playPlaylistItem(index);
                                        },
                                      ),
                                    );
                                  },
                              ),
                      ),
                    ],
                  ),
                );
              },
            );
          }
        }
