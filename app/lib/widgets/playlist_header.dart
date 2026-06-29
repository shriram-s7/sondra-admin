import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class CommonPlaylistHeader extends ConsumerWidget {
  final String name;
  final int songCount;
  final String? extraInfo;
  final VoidCallback? onPlayAll;
  final bool isShuffled;
  final VoidCallback? onToggleShuffle;
  final Widget? trailingActions;
  final Widget? searchBar;

  const CommonPlaylistHeader({
    super.key,
    required this.name,
    required this.songCount,
    this.extraInfo,
    this.onPlayAll,
    required this.isShuffled,
    this.onToggleShuffle,
    this.trailingActions,
    this.searchBar,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(
                "$songCount song${songCount == 1 ? '' : 's'}",
                style: const TextStyle(color: Colors.white54, fontSize: 14),
              ),
              if (extraInfo != null && extraInfo!.isNotEmpty) ...[
                const SizedBox(width: 8),
                const Text("•", style: TextStyle(color: Colors.white30)),
                const SizedBox(width: 8),
                Text(
                  extraInfo!,
                  style: const TextStyle(
                    color: Color(0xFF10B981),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
          if (searchBar != null) ...[
            const SizedBox(height: 12),
            searchBar!,
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: onPlayAll,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF8B5CF6),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                ),
                icon: const Icon(Icons.play_arrow_rounded, size: 22),
                label: const Text("Play All", style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: onToggleShuffle,
                style: OutlinedButton.styleFrom(
                  foregroundColor: isShuffled ? const Color(0xFF8B5CF6) : Colors.white,
                  side: BorderSide(
                    color: isShuffled ? const Color(0xFF8B5CF6) : Colors.white24,
                    width: 1.5,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                ),
                icon: Icon(
                  Icons.shuffle_rounded,
                  color: isShuffled ? const Color(0xFF8B5CF6) : Colors.white70,
                  size: 20,
                ),
                label: Text(
                  "Shuffle",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isShuffled ? const Color(0xFF8B5CF6) : Colors.white,
                  ),
                ),
              ),
              if (trailingActions != null) ...[
                const SizedBox(width: 12),
                trailingActions!,
              ],
            ],
          ),
        ],
      ),
    );
  }
}
