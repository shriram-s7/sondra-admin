import 'package:flutter/material';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/player_provider.dart';
import '../services/api_service.dart';

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
    final coverUrl = "${ApiService().baseUrl}/api/songs/${song["id"]}/cover";

    return Scaffold(
      backgroundColor: const Color(0xFF0F0E17),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white, size: 28),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text("Now Playing", style: TextStyle(color: Colors.white, fontSize: 16)),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            // Album Art
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: CachedNetworkImage(
                  imageUrl: coverUrl,
                  height: MediaQuery.of(context).size.width * 0.75,
                  width: MediaQuery.of(context).size.width * 0.75,
                  fit: BoxFit.cover,
                  errorWidget: (c, e, s) => Container(
                    color: Colors.white10,
                    height: MediaQuery.of(context).size.width * 0.75,
                    width: MediaQuery.of(context).size.width * 0.75,
                    child: const Icon(Icons.music_note, size: 80, color: Colors.white24),
                  ),
                ),
              ),
            ),
            
            // Song Meta
            Column(
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

            // Seek Bar
            Column(
              children: [
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 4,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                    activeTrackColor: const Color(0xFF7C3AED),
                    inactiveTrackColor: Colors.white12,
                    thumbColor: const Color(0xFF7C3AED),
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
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_formatDuration(playerState.position), style: const TextStyle(color: Colors.white38, fontSize: 12)),
                      Text(_formatDuration(playerState.duration), style: const TextStyle(color: Colors.white38, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),

            // Controls
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Shuffle Button
                IconButton(
                  icon: Icon(
                    Icons.shuffle_rounded,
                    color: playerState.shuffle ? const Color(0xFF7C3AED) : Colors.white38,
                    size: 24,
                  ),
                  onPressed: () => notifier.toggleShuffle(),
                ),
                
                // Previous
                IconButton(
                  icon: const Icon(Icons.skip_previous_rounded, color: Colors.white, size: 36),
                  onPressed: () => notifier.handlePrev(),
                ),

                // Play / Pause
                GestureDetector(
                  onTap: () => notifier.togglePlay(),
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: const BoxDecoration(
                      color: Color(0xFF7C3AED),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      playerState.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
                ),

                // Next
                IconButton(
                  icon: const Icon(Icons.skip_next_rounded, color: Colors.white, size: 36),
                  onPressed: () => notifier.handleNext(),
                ),

                // Repeat Mode Button
                IconButton(
                  icon: Icon(
                    playerState.repeat == "one" 
                        ? Icons.repeat_one_rounded 
                        : Icons.repeat_rounded,
                    color: playerState.repeat != "none" ? const Color(0xFF7C3AED) : Colors.white38,
                    size: 24,
                  ),
                  onPressed: () => notifier.cycleRepeat(),
                ),
              ],
            ),

            // Volume Control
            Row(
              children: [
                const Icon(Icons.volume_mute_rounded, color: Colors.white38, size: 18),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 2,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
                      activeTrackColor: Colors.white60,
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
                const Icon(Icons.volume_up_rounded, color: Colors.white38, size: 18),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
