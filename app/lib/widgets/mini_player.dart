import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/player_provider.dart';
import 'song_cover.dart';

class MiniPlayer extends ConsumerStatefulWidget {
  final VoidCallback onTap;
  const MiniPlayer({super.key, required this.onTap});

  @override
  ConsumerState<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends ConsumerState<MiniPlayer> {
  String _formatDuration(Duration d) {
    final mins = d.inMinutes;
    final secs = d.inSeconds % 60;
    return "${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}";
  }

  @override
  Widget build(BuildContext context) {
    final playerState = ref.watch(playerProvider);
    final notifier = ref.read(playerProvider.notifier);

    if (playerState.currentSong == null) {
      return const SizedBox.shrink();
    }

    final song = playerState.currentSong!;

    if (Platform.isWindows) {
      return _buildWindowsBar(context, playerState, notifier, song);
    } else {
      return _buildMobileBar(context, playerState, notifier, song);
    }
  }

  // ──────────────────────────────────────────────────────────────
  // ANDROID MOBILE BAR (compact: cover, title, play/pause, next)
  // ──────────────────────────────────────────────────────────────
  Widget _buildMobileBar(BuildContext context, PlayerState playerState, PlayerNotifier notifier, Map<String, dynamic> song) {
    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        height: 60,
        decoration: BoxDecoration(
          color: const Color(0xFF111019),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.06)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 12,
              offset: const Offset(0, 4),
            )
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            SongCoverWidget(
              song: song,
              width: 40,
              height: 40,
              borderRadius: 6.0,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    song["title"] ?? "Unknown Track",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    "${song["artist"] ?? "Unknown Artist"} · ${playerState.activePlaylistName}",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white54, fontSize: 10),
                  ),
                ],
              ),
            ),
            if (playerState.isBuffering)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: SizedBox(
                  width: 20, height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF8B5CF6)),
                ),
              ),
            IconButton(
              icon: Icon(
                Icons.shuffle_rounded,
                color: playerState.shuffle ? const Color(0xFF8B5CF6) : Colors.white70,
                size: 24,
              ),
              onPressed: () => notifier.toggleShuffle(),
              tooltip: playerState.shuffle ? "Disable Shuffle" : "Enable Shuffle",
            ),
            IconButton(
              icon: Icon(
                playerState.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: Colors.white, size: 26,
              ),
              onPressed: () => notifier.togglePlay(),
            ),
            IconButton(
              icon: const Icon(Icons.skip_next_rounded, color: Colors.white, size: 26),
              onPressed: () => notifier.handleNext(),
            ),
          ],
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────
  // WINDOWS DESKTOP BAR (three sections, Spotify-like)
  // ──────────────────────────────────────────────────────────────
  Widget _buildWindowsBar(BuildContext context, PlayerState playerState, PlayerNotifier notifier, Map<String, dynamic> song) {
    return Container(
      height: 72,
      decoration: const BoxDecoration(
        color: Color(0xFF111019),
        border: Border(top: BorderSide(color: Colors.white10, width: 0.5)),
      ),
      child: Row(
        children: [
          // ═══ LEFT SECTION: Cover, title, artist, heart ═══
          Expanded(
            flex: 3,
            child: Row(
              children: [
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: widget.onTap,
                  behavior: HitTestBehavior.opaque,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SongCoverWidget(song: song, width: 52, height: 52, borderRadius: 4.0),
                      const SizedBox(width: 10),
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 110,
                            child: Text(
                              song["title"] ?? "Unknown Track",
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                            ),
                          ),
                          const SizedBox(height: 2),
                          SizedBox(
                            width: 110,
                            child: Text(
                              song["artist"] ?? "Unknown Artist",
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 12),
                            ),
                          ),
                          const SizedBox(height: 2),
                          SizedBox(
                            width: 110,
                            child: Row(
                              children: [
                                const Icon(Icons.playlist_play_rounded, size: 10, color: Colors.white30),
                                const SizedBox(width: 2),
                                Expanded(
                                  child: Text(
                                    playerState.activePlaylistName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: Colors.white30, fontSize: 9),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ═══ CENTRE SECTION: Controls + seek bar ═══
          Expanded(
            flex: 5,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Control buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _compactBtn(
                      icon: Icons.shuffle_rounded,
                      color: playerState.shuffle ? const Color(0xFF8B5CF6) : Colors.white70,
                      size: 20,
                      onPressed: () => notifier.toggleShuffle(),
                      tooltip: playerState.shuffle ? "Disable Shuffle" : "Enable Shuffle",
                    ),
                    const SizedBox(width: 4),
                    _compactBtn(
                      icon: Icons.skip_previous_rounded,
                      color: Colors.white,
                      size: 20,
                      onPressed: () => notifier.handlePrev(),
                    ),
                    const SizedBox(width: 10),
                    // Play/Pause — larger circular button
                    GestureDetector(
                      onTap: () => notifier.togglePlay(),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: playerState.isBuffering
                              ? const SizedBox(
                                  width: 16, height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF111019)),
                                )
                              : Icon(
                                  playerState.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                  color: const Color(0xFF111019),
                                  size: 22,
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    _compactBtn(
                      icon: Icons.skip_next_rounded,
                      color: Colors.white,
                      size: 20,
                      onPressed: () => notifier.handleNext(),
                    ),
                    const SizedBox(width: 4),
                    _compactBtn(
                      icon: playerState.repeat == "one" ? Icons.repeat_one_rounded : Icons.repeat_rounded,
                      color: playerState.repeat != "none" ? const Color(0xFF8B5CF6) : Colors.white38,
                      size: 18,
                      onPressed: () => notifier.cycleRepeat(),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                // Seek bar
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      Text(
                        _formatDuration(playerState.position),
                        style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 10, fontFeatures: [FontFeature.tabularFigures()]),
                      ),
                      Expanded(
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 2,
                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
                            overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                            activeTrackColor: const Color(0xFF8B5CF6),
                            inactiveTrackColor: Colors.white12,
                            thumbColor: const Color(0xFF8B5CF6),
                          ),
                          child: Slider(
                            min: 0.0,
                            max: playerState.duration.inMilliseconds > 0
                                ? playerState.duration.inMilliseconds.toDouble()
                                : 1.0,
                            value: playerState.position.inMilliseconds.toDouble().clamp(
                                  0.0,
                                  playerState.duration.inMilliseconds > 0
                                      ? playerState.duration.inMilliseconds.toDouble()
                                      : 1.0,
                                ),
                            onChanged: (value) => notifier.seek(Duration(milliseconds: value.toInt())),
                          ),
                        ),
                      ),
                      Text(
                        _formatDuration(playerState.duration),
                        style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 10, fontFeatures: [FontFeature.tabularFigures()]),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ═══ RIGHT SECTION: Queue, volume icon, volume slider ═══
          Expanded(
            flex: 3,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _compactBtn(
                  icon: Icons.queue_music_rounded,
                  color: Colors.white60,
                  size: 18,
                  onPressed: widget.onTap,
                ),
                const SizedBox(width: 4),
                Icon(
                  playerState.volume == 0 ? Icons.volume_mute_rounded : Icons.volume_up_rounded,
                  color: Colors.white60,
                  size: 16,
                ),
                const SizedBox(width: 4),
                SizedBox(
                  width: 90,
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 4,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                      activeTrackColor: Colors.white70,
                      inactiveTrackColor: Colors.white12,
                      thumbColor: Colors.white,
                    ),
                    child: Slider(
                      min: 0.0,
                      max: 1.0,
                      value: playerState.volume,
                      onChanged: (vol) => notifier.setVolume(vol),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _compactBtn({
    required IconData icon,
    required Color color,
    required double size,
    required VoidCallback onPressed,
    String? tooltip,
  }) {
    return SizedBox(
      width: 36,
      height: 36,
      child: IconButton(
        icon: Icon(icon, color: color, size: size),
        onPressed: onPressed,
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        splashRadius: 18,
      ),
    );
  }
}
