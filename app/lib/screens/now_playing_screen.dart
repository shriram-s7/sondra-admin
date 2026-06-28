import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/player_provider.dart';
import '../widgets/song_cover.dart';
import 'queue_screen.dart';

class NowPlayingScreen extends ConsumerWidget {
  const NowPlayingScreen({super.key});

  String _formatDuration(Duration d) {
    final mins = d.inMinutes;
    final secs = d.inSeconds % 60;
    return "${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}";
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playerState = ref.watch(playerProvider);
    final notifier = ref.read(playerProvider.notifier);
    
    if (playerState.currentSong == null) {
      return const SizedBox.shrink();
    }

    final song = playerState.currentSong!;

    if (Platform.isWindows) {
      return _buildWindowsLayout(context, ref, playerState, notifier, song);
    } else {
      return _buildAndroidLayout(context, ref, playerState, notifier, song);
    }
  }

  // ──────────────────────────────────────────────────────────────────
  // ANDROID MOBILE LAYOUT (Full-screen slide-up like Spotify)
  // ──────────────────────────────────────────────────────────────────
  Widget _buildAndroidLayout(BuildContext context, WidgetRef ref, PlayerState playerState, PlayerNotifier notifier, Map<String, dynamic> song) {
    return Scaffold(
      backgroundColor: const Color(0xFF08070D),
      body: SafeArea(
        child: Column(
          children: [
            // Top bar with down-arrow dismiss
            SizedBox(
              height: 48,
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white, size: 28),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.queue_music_rounded, color: Colors.white70, size: 22),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const QueueScreen()),
                      );
                    },
                  ),
                ],
              ),
            ),
            // Album art takes ~50% of remaining space (flex:5)
            Expanded(
              flex: 5,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: SongCoverWidget(
                      song: song,
                      width: 400,
                      height: 400,
                      borderRadius: 16.0,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Song title & artist
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                children: [
                  Text(
                    song["title"] ?? "Unknown Title",
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    song["artist"] ?? "Unknown Artist",
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white60, fontSize: 16),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Seek bar with time labels
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                children: [
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 4,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                      activeTrackColor: const Color(0xFF8B5CF6),
                      inactiveTrackColor: Colors.white12,
                      thumbColor: const Color(0xFF8B5CF6),
                    ),
                    child: Slider(
                      min: 0.0,
                      max: playerState.duration.inMilliseconds.toDouble(),
                      value: playerState.position.inMilliseconds.toDouble().clamp(
                        0.0, 
                        playerState.duration.inMilliseconds.toDouble()
                      ),
                      onChanged: (value) {
                        notifier.seek(Duration(milliseconds: value.toInt()));
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(_formatDuration(playerState.position), style: const TextStyle(color: Colors.white38, fontSize: 11)),
                        Text(_formatDuration(playerState.duration), style: const TextStyle(color: Colors.white38, fontSize: 11)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // Controls
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  icon: Icon(Icons.shuffle_rounded, color: playerState.shuffle ? const Color(0xFF8B5CF6) : Colors.white38, size: 24),
                  onPressed: () => notifier.toggleShuffle(),
                ),
                IconButton(
                  icon: const Icon(Icons.skip_previous_rounded, color: Colors.white, size: 36),
                  onPressed: () => notifier.handlePrev(),
                ),
                GestureDetector(
                  onTap: () => notifier.togglePlay(),
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: const BoxDecoration(
                      color: Color(0xFF8B5CF6),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: playerState.isBuffering
                          ? const SizedBox(
                              width: 28,
                              height: 28,
                              child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white),
                            )
                          : Icon(
                              playerState.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                              color: Colors.white,
                              size: 32,
                            ),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.skip_next_rounded, color: Colors.white, size: 36),
                  onPressed: () => notifier.handleNext(),
                ),
                IconButton(
                  icon: Icon(
                    playerState.repeat == "one" ? Icons.repeat_one_rounded : Icons.repeat_rounded,
                    color: playerState.repeat != "none" ? const Color(0xFF8B5CF6) : Colors.white38,
                    size: 24,
                  ),
                  onPressed: () => notifier.cycleRepeat(),
                ),
              ],
            ),
            SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
          ],
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────
  // WINDOWS DESKTOP LAYOUT (Embedded page view)
  // ──────────────────────────────────────────────────────────────────
  Widget _buildWindowsLayout(BuildContext context, WidgetRef ref, PlayerState playerState, PlayerNotifier notifier, Map<String, dynamic> song) {
    // Get list of upcoming tracks (excluding currently playing)
    final upcomingList = <Map<String, dynamic>>[];
    if (playerState.activePlaylist.isNotEmpty) {
      final currentIdx = playerState.activePlaylist.indexWhere((s) => s["id"] == song["id"]);
      if (currentIdx != -1) {
        for (int i = currentIdx + 1; i < playerState.activePlaylist.length; i++) {
          if (upcomingList.length < 3) {
            upcomingList.add(playerState.activePlaylist[i]);
          } else {
            break;
          }
        }
      }
    }

    return Scaffold(
      backgroundColor: const Color(0xFF08070D),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 24),
          onPressed: () {
            ref.read(showNowPlayingProvider.notifier).state = false;
          },
        ),
        title: const Text("Now Playing", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
      ),
      body: Row(
        children: [
          // Left side: Large Album Art / seeded gradient
          Expanded(
            flex: 5,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: SongCoverWidget(
                    song: song,
                    width: 320,
                    height: 320,
                    borderRadius: 16.0,
                  ),
                ),
              ),
            ),
          ),

          // Vertical divider line
          Container(width: 1, color: Colors.white.withOpacity(0.06), margin: const EdgeInsets.symmetric(vertical: 24)),

          // Right side: Player details, seek, queue
          Expanded(
            flex: 7,
            child: Padding(
              padding: const EdgeInsets.all(40.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Title & Artist
                  Text(
                    song["title"] ?? "Unknown Track",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    song["artist"] ?? "Unknown Artist",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white60, fontSize: 18),
                  ),
                  const SizedBox(height: 32),

                  // Controls Row (Shuffle, Prev, Play, Next, Repeat)
                  Row(
                    children: [
                      IconButton(
                        icon: Icon(
                          Icons.shuffle_rounded,
                          color: playerState.shuffle ? const Color(0xFF8B5CF6) : Colors.white38,
                          size: 22,
                        ),
                        onPressed: () => notifier.toggleShuffle(),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.skip_previous_rounded, color: Colors.white, size: 28),
                        onPressed: () => notifier.handlePrev(),
                      ),
                      const SizedBox(width: 12),
                      GestureDetector(
                        onTap: () => notifier.togglePlay(),
                        child: Container(
                          width: 48,
                          height: 48,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: playerState.isBuffering
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Color(0xFF111019),
                                    ),
                                  )
                                : Icon(
                                    playerState.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                    color: const Color(0xFF111019),
                                    size: 26,
                                  ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      IconButton(
                        icon: const Icon(Icons.skip_next_rounded, color: Colors.white, size: 28),
                        onPressed: () => notifier.handleNext(),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: Icon(
                          playerState.repeat == "one" ? Icons.repeat_one_rounded : Icons.repeat_rounded,
                          color: playerState.repeat != "none" ? const Color(0xFF8B5CF6) : Colors.white38,
                          size: 22,
                        ),
                        onPressed: () => notifier.cycleRepeat(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Seek Bar
                  Row(
                    children: [
                      Text(_formatDuration(playerState.position), style: const TextStyle(color: Colors.white38, fontSize: 12)),
                      Expanded(
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 3,
                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                            activeTrackColor: const Color(0xFF8B5CF6),
                            inactiveTrackColor: Colors.white12,
                            thumbColor: const Color(0xFF8B5CF6),
                          ),
                          child: Slider(
                            min: 0.0,
                            max: playerState.duration.inMilliseconds.toDouble(),
                            value: playerState.position.inMilliseconds.toDouble().clamp(
                              0.0, 
                              playerState.duration.inMilliseconds.toDouble()
                            ),
                            onChanged: (value) {
                              notifier.seek(Duration(milliseconds: value.toInt()));
                            },
                          ),
                        ),
                      ),
                      Text(_formatDuration(playerState.duration), style: const TextStyle(color: Colors.white38, fontSize: 12)),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Accessories (Volume Control & Queue icon)
                  Row(
                    children: [
                      const Icon(Icons.volume_up_rounded, color: Colors.white60, size: 20),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 120,
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 3,
                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
                            activeTrackColor: Colors.white,
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
                      const Spacer(),
                      GestureDetector(
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const QueueScreen()),
                          );
                        },
                        behavior: HitTestBehavior.opaque,
                        child: Row(
                          children: [
                            const Icon(Icons.queue_music_rounded, color: Color(0xFF8B5CF6), size: 22),
                            const SizedBox(width: 8),
                            const Text("Open Full Queue", style: TextStyle(color: Color(0xFF8B5CF6), fontSize: 13, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),

                  // Next Up / Queue list section
                  if (upcomingList.isNotEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.04),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withOpacity(0.04)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Next Up",
                            style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                          ),
                          const SizedBox(height: 12),
                          ...upcomingList.map((nextSong) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8.0),
                              child: Row(
                                children: [
                                  SongCoverWidget(
                                    song: nextSong,
                                    width: 32,
                                    height: 32,
                                    borderRadius: 4.0,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          nextSong["title"] ?? "Unknown Track",
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                                        ),
                                        Text(
                                          nextSong["artist"] ?? "Unknown Artist",
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(color: Colors.white38, fontSize: 11),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────
// WINDOWS RIGHT PANEL — Compact now-playing overlay for right sidebar
// ──────────────────────────────────────────────────────────────────────
class NowPlayingRightPanel extends ConsumerWidget {
  final VoidCallback onClose;
  const NowPlayingRightPanel({super.key, required this.onClose});

  String _formatDuration(Duration d) {
    final mins = d.inMinutes;
    final secs = d.inSeconds % 60;
    return "${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}";
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playerState = ref.watch(playerProvider);
    final notifier = ref.read(playerProvider.notifier);

    if (playerState.currentSong == null) return const SizedBox.shrink();

    final song = playerState.currentSong!;

    // Next 3 upcoming tracks
    final upcomingList = <Map<String, dynamic>>[];
    if (playerState.activePlaylist.isNotEmpty) {
      final currentIdx = playerState.activePlaylist.indexWhere((s) => s["id"] == song["id"]);
      if (currentIdx != -1) {
        for (int i = currentIdx + 1; i < playerState.activePlaylist.length && upcomingList.length < 3; i++) {
          upcomingList.add(playerState.activePlaylist[i]);
        }
      }
    }

    return Container(
      width: 340,
      decoration: BoxDecoration(
        color: const Color(0xFF0E0C17),
        border: Border(left: BorderSide(color: Colors.white.withOpacity(0.06))),
      ),
      child: Column(
        children: [
          // Top bar: "Now Playing" label + close button
          SizedBox(
            height: 56,
            child: Row(
              children: [
                const SizedBox(width: 16),
                const Text("Now Playing", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white54, size: 22),
                  onPressed: onClose,
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Colors.white10),

          // Album art
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 32, 32, 16),
            child: AspectRatio(
              aspectRatio: 1,
              child: SongCoverWidget(song: song, width: 280, height: 280, borderRadius: 12),
            ),
          ),

          // Title + Artist
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(song["title"] ?? "Unknown Track",
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(song["artist"] ?? "Unknown Artist",
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white60, fontSize: 14)),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Seek bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                    activeTrackColor: const Color(0xFF8B5CF6),
                    inactiveTrackColor: Colors.white12,
                    thumbColor: const Color(0xFF8B5CF6),
                  ),
                  child: Slider(
                    min: 0.0,
                    max: playerState.duration.inMilliseconds.toDouble(),
                    value: playerState.position.inMilliseconds.toDouble().clamp(
                        0.0, playerState.duration.inMilliseconds.toDouble()),
                    onChanged: (value) => notifier.seek(Duration(milliseconds: value.toInt())),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_formatDuration(playerState.position), style: const TextStyle(color: Colors.white38, fontSize: 11)),
                      Text(_formatDuration(playerState.duration), style: const TextStyle(color: Colors.white38, fontSize: 11)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Controls (compact row)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: Icon(Icons.shuffle_rounded,
                    color: playerState.shuffle ? const Color(0xFF8B5CF6) : Colors.white38, size: 20),
                onPressed: () => notifier.toggleShuffle(),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.skip_previous_rounded, color: Colors.white, size: 26),
                onPressed: () => notifier.handlePrev(),
              ),
              GestureDetector(
                onTap: () => notifier.togglePlay(),
                child: Container(
                  width: 44, height: 44,
                  decoration: const BoxDecoration(color: Color(0xFF8B5CF6), shape: BoxShape.circle),
                  child: Center(
                    child: playerState.isBuffering
                        ? const SizedBox(width: 18, height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Icon(playerState.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                            color: Colors.white, size: 24),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.skip_next_rounded, color: Colors.white, size: 26),
                onPressed: () => notifier.handleNext(),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: Icon(
                  playerState.repeat == "one" ? Icons.repeat_one_rounded : Icons.repeat_rounded,
                  color: playerState.repeat != "none" ? const Color(0xFF8B5CF6) : Colors.white38,
                  size: 20,
                ),
                onPressed: () => notifier.cycleRepeat(),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Volume
          Row(
            children: [
              const SizedBox(width: 24),
              const Icon(Icons.volume_up_rounded, color: Colors.white60, size: 18),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
                    activeTrackColor: Colors.white,
                    inactiveTrackColor: Colors.white12,
                    thumbColor: Colors.white,
                  ),
                  child: Slider(
                    min: 0.0, max: 1.0,
                    value: playerState.volume,
                    onChanged: (vol) => notifier.setVolume(vol),
                  ),
                ),
              ),
              const SizedBox(width: 24),
            ],
          ),

          const Spacer(),

          // Queue / Next Up
          if (upcomingList.isNotEmpty)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.04),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text("Next Up",
                          style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                      const Spacer(),
                      GestureDetector(
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const QueueScreen()),
                        ),
                        child: const Icon(Icons.queue_music_rounded, color: Color(0xFF8B5CF6), size: 18),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ...upcomingList.map((nextSong) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        SongCoverWidget(song: nextSong, width: 28, height: 28, borderRadius: 4),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(nextSong["title"] ?? "Unknown Track",
                                  maxLines: 1, overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                              Text(nextSong["artist"] ?? "Unknown Artist",
                                  maxLines: 1, overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: Colors.white38, fontSize: 10)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  )).toList(),
                ],
              ),
            ),

          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
