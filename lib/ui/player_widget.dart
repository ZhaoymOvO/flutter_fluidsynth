import 'package:flutter/material.dart';
import '../i18n/i18n_service.dart';
import '../services/fluidsynth_service.dart';
import '../services/soundfont_service.dart';
import 'playlist_sheet.dart';

class PlayerWidget extends StatelessWidget {
  final FluidSynthService fluidService;
  final SoundFontService soundFontService;

  const PlayerWidget({
    super.key,
    required this.fluidService,
    required this.soundFontService,
  });


  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final hasTrack = fluidService.currentMidiTitle != null;
    final isPlaying = fluidService.isPlaying;

    final activeSfName = fluidService.loadedSfName ??
        soundFontService.activeSoundFont?.name ??
        context.tr('player_no_soundfont');

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E2C) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Track & SoundFont Info Row
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isPlaying
                        ? Icons.equalizer_rounded
                        : hasTrack
                            ? Icons.music_note_rounded
                            : Icons.music_off_rounded,
                    color: theme.colorScheme.onPrimaryContainer,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        fluidService.currentMidiTitle ??
                            context.tr('player_no_track'),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(
                            Icons.album_outlined,
                            size: 13,
                            color: theme.colorScheme.secondary,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              activeSfName,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.secondary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // Progress Slider (Always displayed so player height remains fixed)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 6),
                      overlayShape:
                          const RoundSliderOverlayShape(overlayRadius: 12),
                    ),
                    child: Slider(
                      value: (hasTrack && fluidService.totalTicks > 0)
                          ? fluidService.currentTick
                              .clamp(0, fluidService.totalTicks)
                              .toDouble()
                          : 0.0,
                      min: 0.0,
                      max: (hasTrack && fluidService.totalTicks > 0)
                          ? fluidService.totalTicks.toDouble()
                          : 1.0,
                      onChanged: (hasTrack && fluidService.totalTicks > 0)
                          ? (val) {
                              fluidService.seek(val.toInt());
                            }
                          : null,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          hasTrack ? fluidService.formattedCurrentTime : '00:00',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        Text(
                          hasTrack && fluidService.bpm > 0
                              ? 'BPM: ${fluidService.bpm}'
                              : 'BPM: --',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        Text(
                          hasTrack ? fluidService.formattedTotalTime : '00:00',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Controls Row: Centered Playback Controls + Right-Aligned Playlist Button
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Centered Playback Controls: Shuffle (small), Previous, Play/Pause, Next, Loop (small)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // 1. 隨機播放 (Shuffle) - 縮小並移至上一首外側
                        IconButton(
                          tooltip: fluidService.isShuffle
                              ? context.tr('player_btn_shuffle_on')
                              : context.tr('player_btn_shuffle_off'),
                          iconSize: 20,
                          style: IconButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.all(6),
                          ),
                          icon: Icon(
                            Icons.shuffle_rounded,
                            color: fluidService.isShuffle
                                ? theme.colorScheme.primary
                                : theme.disabledColor,
                          ),
                          onPressed: () => fluidService.toggleShuffle(),
                        ),
                        const SizedBox(width: 6),

                        // 2. 上一首 (Previous)
                        IconButton(
                          tooltip: context.tr('player_btn_prev'),
                          icon: const Icon(Icons.skip_previous_rounded),
                          onPressed: hasTrack && fluidService.hasPrevious
                              ? () => fluidService.playPrevious()
                              : null,
                        ),
                        const SizedBox(width: 8),

                        // 3. 暫停 | 播放 (Play / Pause)
                        IconButton.filled(
                          tooltip: isPlaying
                              ? context.tr('player_btn_pause')
                              : context.tr('player_btn_play'),
                          iconSize: 32,
                          icon: Icon(isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
                          onPressed: hasTrack
                              ? () {
                                  if (isPlaying) {
                                    fluidService.pause();
                                  } else if (fluidService.isPaused) {
                                    fluidService.resume();
                                  } else if (fluidService.currentMidiPath != null) {
                                    fluidService
                                        .playMidi(fluidService.currentMidiPath!);
                                  }
                                }
                              : null,
                        ),
                        const SizedBox(width: 8),

                        // 4. 下一首 (Next)
                        IconButton(
                          tooltip: context.tr('player_btn_next'),
                          icon: const Icon(Icons.skip_next_rounded),
                          onPressed: hasTrack && fluidService.hasNext
                              ? () => fluidService.playNext()
                              : null,
                        ),
                        const SizedBox(width: 6),

                        // 5. 循環模式 (Loop Mode) - 縮小並移至下一首外側
                        IconButton(
                          tooltip: fluidService.loopMode == LoopMode.none
                              ? context.tr('player_loop_none')
                              : fluidService.loopMode == LoopMode.playlist
                                  ? context.tr('player_loop_playlist')
                                  : context.tr('player_loop_single'),
                          iconSize: 20,
                          style: IconButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.all(6),
                          ),
                          icon: Icon(
                            fluidService.loopMode == LoopMode.single
                                ? Icons.repeat_one_rounded
                                : Icons.repeat_rounded,
                            color: fluidService.loopMode == LoopMode.none
                                ? theme.disabledColor
                                : theme.colorScheme.primary,
                          ),
                          onPressed: () => fluidService.cycleLoopMode(),
                        ),
                      ],
                    ),

                    // 6. 播放列表按鈕（右對齊）
                    Positioned(
                      right: 8,
                      child: IconButton(
                        tooltip: context.tr('player_btn_playlist'),
                        icon: Badge(
                          isLabelVisible: fluidService.playlist.isNotEmpty,
                          label: Text('${fluidService.playlist.length}'),
                          child: Icon(
                            Icons.queue_music_rounded,
                            color: fluidService.playlist.isNotEmpty
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        onPressed: () => PlaylistSheet.show(context, fluidService),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
