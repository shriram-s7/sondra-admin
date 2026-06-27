import 'package:flutter/material';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/player_provider.dart';
import '../services/api_service.dart';

class MiniPlayer extends ConsumerWidget {
  final VoidCallback onTap;
  const MiniPlayer({super.key, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playerState = ref.watch(playerProvider);
    final notifier = ref.read(playerProvider.notifier);

    if (playerState.currentSong == null) {
      return const SizedBox.shrink();
    }

    final song = playerState.currentSong!;
    final coverUrl = "${ApiService().baseUrl}/api/songs/${song["id"]}/cover";

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 60,
        decoration: BoxDecoration(
          color: const Color(0xFF15141F),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.4),
              blurRadius: 10,
              offset: const Offset(0, 4),
            )
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            // Cover Thumb
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: CachedNetworkImage(
                imageUrl: coverUrl,
                width: 40,
                height: 40,
                fit: BoxFit.cover,
                errorWidget: (c, e, s) => Container(
                  color: Colors.white10,
                  width: 40,
                  height: 40,
                  child: const Icon(Icons.music_note, color: Colors.white24, size: 20),
                ),
              ),
            ),
            const SizedBox(width: 12),
            
            // Meta Info
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
                    song["artist"] ?? "Unknown Artist",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                ],
              ),
            ),
            
            // Controls
            IconButton(
              icon: Icon(
                playerState.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: Colors.white,
                size: 26,
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
}
