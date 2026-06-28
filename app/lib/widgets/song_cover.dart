import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/api_service.dart';

class SongCoverWidget extends StatelessWidget {
  final Map<String, dynamic> song;
  final double width;
  final double height;
  final double borderRadius;
  final double? iconSize;

  const SongCoverWidget({
    super.key,
    required this.song,
    required this.width,
    required this.height,
    this.borderRadius = 8.0,
    this.iconSize,
  });

  @override
  Widget build(BuildContext context) {
    final songTitle = song["title"] ?? "Unknown";
    final initial = songTitle.isNotEmpty ? songTitle[0].toUpperCase() : "♫";

    // No cover_url → show gradient immediately without a network request.
    // This also covers offline songs that have no cover art.
    if (song["cover_url"] == null || (song["cover_url"] is String && (song["cover_url"] as String).isEmpty)) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: _buildPlaceholder(initial),
      );
    }

    final coverUrl = "${ApiService().baseUrl}/api/songs/${song["id"]}/cover";

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: CachedNetworkImage(
        imageUrl: coverUrl,
        width: width,
        height: height,
        fit: BoxFit.cover,
        errorWidget: (_, __, ___) => _buildPlaceholder(initial),
        placeholder: (_, __) => Container(
          width: width,
          height: height,
          color: Colors.white.withOpacity(0.05),
          child: const Center(
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF8B5CF6)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceholder(String initial) {
    final songTitle = song["title"] ?? "";
    
    // Consistent hash function
    int hash = 0;
    for (int i = 0; i < songTitle.length; i++) {
      hash = songTitle.codeUnitAt(i) + ((hash << 5) - hash);
    }
    
    // Vibrantly curated gradient palettes (analogous to Web Admin interface)
    final List<List<Color>> palettes = [
      [const Color(0xFFF43F5E), const Color(0xFFFB7185)], // Rose
      [const Color(0xFFEC4899), const Color(0xFFF472B6)], // Pink
      [const Color(0xFFD946EF), const Color(0xFFE879F9)], // Fuchsia
      [const Color(0xFFA855F7), const Color(0xFFC084FC)], // Purple
      [const Color(0xFF8B5CF6), const Color(0xFFA78BFA)], // Violet
      [const Color(0xFF6366F1), const Color(0xFF818CF8)], // Indigo
      [const Color(0xFF3B82F6), const Color(0xFF60A5FA)], // Blue
      [const Color(0xFF0EA5E9), const Color(0xFF38BDF8)], // Light Blue
      [const Color(0xFF06B6D4), const Color(0xFF22D3EE)], // Cyan
      [const Color(0xFF14B8A6), const Color(0xFF2DD4BF)], // Teal
      [const Color(0xFF10B981), const Color(0xFF34D399)], // Emerald
      [const Color(0xFF22C55E), const Color(0xFF4ADE80)], // Green
      [const Color(0xFFEAB308), const Color(0xFFFACC15)], // Yellow
      [const Color(0xFFF97316), const Color(0xFFFB923C)], // Orange
      [const Color(0xFFEF4444), const Color(0xFFF87171)], // Red
    ];

    final index = hash.abs() % palettes.length;
    final colors = palettes[index];

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Text(
          initial,
          style: TextStyle(
            color: Colors.white,
            fontSize: iconSize ?? (width * 0.4),
            fontWeight: FontWeight.bold,
            shadows: [
              Shadow(
                color: Colors.black.withOpacity(0.35),
                offset: const Offset(1, 2),
                blurRadius: 4,
              )
            ]
          ),
        ),
      ),
    );
  }
}
