import 'package:flutter/material.dart';
import '../i18n/i18n_service.dart';
import '../services/fluidsynth_service.dart';
import '../services/soundfont_service.dart';
import 'playlist_sheet.dart';

class PlayerWidget extends StatelessWidget {
  final FluidSynthService fluidService;
  final SoundFontService soundFontService;

  static const double wideBreakpoint = 600.0;

  const PlayerWidget({
    super.key,
    required this.fluidService,
    required this.soundFontService,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasTrack = fluidService.currentMidiTitle != null;
    final isPlaying = fluidService.isPlaying;

    final activeSfName =
        fluidService.loadedSfName ??
        soundFontService.activeSoundFont?.name ??
        context.tr('player_no_soundfont');

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= wideBreakpoint;

        return Material(
          color: theme.colorScheme.surfaceContainer,
          elevation: 3,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Top Row:
                  // In wide mode, contains Track Info + Playback Controls + Playlist Button.
                  // In narrow mode, contains Track Info only.
                  if (isWide)
                    Row(
                      children: [
                        Expanded(
                          child: _buildTrackInfo(
                            context,
                            theme,
                            hasTrack,
                            isPlaying,
                            activeSfName,
                          ),
                        ),
                        _buildPlaybackControls(
                          context,
                          theme,
                          hasTrack,
                          isPlaying,
                        ),
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: _buildPlaylistButton(context, theme),
                            ),
                          ),
                        ),
                      ],
                    )
                  else
                    _buildTrackInfo(
                      context,
                      theme,
                      hasTrack,
                      isPlaying,
                      activeSfName,
                    ),

                  // Progress Slider (Always displayed so player height remains fixed)
                  _buildProgressSlider(context, theme, hasTrack),

                  // Controls Row: only shown in narrow mode
                  if (!isWide)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            _buildPlaybackControls(
                              context,
                              theme,
                              hasTrack,
                              isPlaying,
                            ),
                            Positioned(
                              right: 8,
                              child: _buildPlaylistButton(context, theme),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTrackInfo(
    BuildContext context,
    ThemeData theme,
    bool hasTrack,
    bool isPlaying,
    String activeSfName,
  ) {
    return Row(
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
                fluidService.currentMidiTitle ?? context.tr('player_no_track'),
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
    );
  }

  Widget _buildProgressSlider(
    BuildContext context,
    ThemeData theme,
    bool hasTrack,
  ) {
    return ValueListenableBuilder<int>(
      valueListenable: fluidService.progressNotifier,
      builder: (context, currentTick, _) {
        return Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 6,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 12,
                  ),
                ),
                child: Slider(
                  value: (hasTrack && fluidService.totalTicks > 0)
                      ? currentTick
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
                      hasTrack
                          ? fluidService.formattedCurrentTime
                          : '00:00',
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
        );
      },
    );
  }

  Widget _buildPlaybackControls(
    BuildContext context,
    ThemeData theme,
    bool hasTrack,
    bool isPlaying,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // 1. 隨機播放 (Shuffle) - 縮小並移至上一首外側
        IconButton(
          tooltip: fluidService.isShuffle
              ? context.tr('player_btn_shuffle_on')
              : context.tr('player_btn_shuffle_off'),
          iconSize: 20,
          visualDensity: VisualDensity.compact,
          style: IconButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.all(4),
          ),
          icon: Icon(
            Icons.shuffle_rounded,
            color: fluidService.isShuffle
                ? theme.colorScheme.primary
                : theme.disabledColor,
          ),
          onPressed: () => fluidService.toggleShuffle(),
        ),

        // 2. 上一首 (Previous)
        IconButton(
          tooltip: context.tr('player_btn_prev'),
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.skip_previous_rounded),
          onPressed: hasTrack && fluidService.hasPrevious
              ? () => fluidService.playPrevious()
              : null,
        ),
        const SizedBox(width: 4),

        // 3. 暫停 | 播放 (Play / Pause)
        IconButton.filled(
          tooltip: isPlaying
              ? context.tr('player_btn_pause')
              : context.tr('player_btn_play'),
          iconSize: 32,
          icon: Icon(
            isPlaying
                ? Icons.pause_rounded
                : Icons.play_arrow_rounded,
          ),
          onPressed: hasTrack
              ? () {
                  if (isPlaying) {
                    fluidService.pause();
                  } else if (fluidService.isPaused) {
                    fluidService.resume();
                  } else if (fluidService.currentMidiPath != null) {
                    fluidService.playMidi(
                      fluidService.currentMidiPath!,
                    );
                  }
                }
              : null,
        ),
        const SizedBox(width: 4),

        // 4. 下一首 (Next)
        IconButton(
          tooltip: context.tr('player_btn_next'),
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.skip_next_rounded),
          onPressed: hasTrack && fluidService.hasNext
              ? () => fluidService.playNext()
              : null,
        ),

        // 5. 循環模式 (Loop Mode) - 縮小並移至下一首外側
        IconButton(
          tooltip: fluidService.loopMode == LoopMode.none
              ? context.tr('player_loop_none')
              : fluidService.loopMode == LoopMode.playlist
              ? context.tr('player_loop_playlist')
              : context.tr('player_loop_single'),
          iconSize: 20,
          visualDensity: VisualDensity.compact,
          style: IconButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.all(4),
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
    );
  }

  Widget _buildPlaylistButton(BuildContext context, ThemeData theme) {
    return IconButton(
      tooltip: context.tr('player_btn_playlist'),
      icon: Badge(
        backgroundColor: theme.colorScheme.primary,
        textColor: theme.colorScheme.onPrimary,
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
    );
  }
}
