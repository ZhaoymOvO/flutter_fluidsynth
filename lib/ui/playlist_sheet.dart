import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../i18n/i18n_service.dart';
import '../services/fluidsynth_service.dart';

class PlaylistSheet extends StatelessWidget {
  final FluidSynthService fluidService;

  const PlaylistSheet({
    super.key,
    required this.fluidService,
  });

  static void show(BuildContext context, FluidSynthService fluidService) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
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

        return Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 640,
              maxHeight: MediaQuery.of(context).size.height * 0.75,
            ),
            child: Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 16,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Pull / Drag handle indicator
                    Container(
                      margin: const EdgeInsets.only(top: 10, bottom: 4),
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),

                    // Header Row
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(
                        children: [
                          Icon(
                            Icons.queue_music_rounded,
                            color: theme.colorScheme.primary,
                            size: 24,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${context.tr('playlist_title')} (${playlist.length} ${context.tr('playlist_tracks_count')})',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Spacer(),
                          if (playlist.isNotEmpty)
                            TextButton.icon(
                              icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                              label: Text(context.tr('playlist_clear')),
                              style: TextButton.styleFrom(
                                foregroundColor: theme.colorScheme.error,
                                visualDensity: VisualDensity.compact,
                              ),
                              onPressed: () => fluidService.clearPlaylist(),
                            ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded),
                            tooltip: context.tr('common_cancel'),
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
                                    color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    context.tr('playlist_empty'),
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : ReorderableListView.builder(
                              buildDefaultDragHandles: false,
                              itemCount: playlist.length,
                              onReorder: (oldIndex, newIndex) {
                                fluidService.reorderPlaylist(oldIndex, newIndex);
                              },
                              itemBuilder: (context, index) {
                                final trackPath = playlist[index];
                                final isPlaying = (index == currentIndex);
                                final filename = p.basename(trackPath);

                                return Material(
                                  key: ValueKey('$trackPath-$index'),
                                  color: isPlaying
                                      ? theme.colorScheme.primaryContainer.withValues(alpha: 0.35)
                                      : Colors.transparent,
                                  child: ListTile(
                                    dense: true,
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                                    leading: isPlaying
                                        ? CircleAvatar(
                                            radius: 13,
                                            backgroundColor: theme.colorScheme.primary,
                                            child: Icon(
                                              Icons.equalizer_rounded,
                                              size: 15,
                                              color: theme.colorScheme.onPrimary,
                                            ),
                                          )
                                        : SizedBox(
                                            width: 26,
                                            child: Center(
                                              child: Text(
                                                '${index + 1}',
                                                style: theme.textTheme.bodySmall?.copyWith(
                                                  color: theme.colorScheme.onSurfaceVariant,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ),
                                          ),
                                    title: Text(
                                      filename,
                                      style: theme.textTheme.bodyMedium?.copyWith(
                                        fontWeight: isPlaying ? FontWeight.bold : FontWeight.normal,
                                        color: isPlaying ? theme.colorScheme.primary : null,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: const Icon(Icons.close_rounded, size: 18),
                                          tooltip: context.tr('sf_btn_remove'),
                                          visualDensity: VisualDensity.compact,
                                          onPressed: () {
                                            fluidService.removeFromPlaylist(index);
                                          },
                                        ),
                                        ReorderableDragStartListener(
                                          index: index,
                                          child: Padding(
                                            padding: const EdgeInsets.only(left: 4, right: 4),
                                            child: Icon(
                                              Icons.drag_handle_rounded,
                                              size: 20,
                                              color: theme.colorScheme.onSurfaceVariant,
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
              ),
            ),
          ),
        );
      },
    );
  }
}
