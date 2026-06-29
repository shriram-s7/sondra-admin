import 'package:flutter/material.dart';

class PlaylistSearchBar extends StatelessWidget {
  final TextEditingController controller;
  final String query;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  const PlaylistSearchBar({
    super.key,
    required this.controller,
    required this.query,
    required this.onChanged,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: "Search by title, artist...",
        hintStyle: const TextStyle(color: Colors.white24, fontSize: 14),
        prefixIcon: const Icon(Icons.search_rounded, color: Colors.white38),
        suffixIcon: query.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear_rounded, color: Colors.white38, size: 20),
                onPressed: onClear,
              )
            : null,
        filled: true,
        fillColor: Colors.white.withOpacity(0.05),
        contentPadding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 16.0),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF8B5CF6)),
        ),
      ),
      onChanged: onChanged,
    );
  }

  static bool matchSong(Map<String, dynamic> s, String query) {
    if (query.isEmpty) return true;
    final q = query.toLowerCase().trim();

    final title = (s['title'] ?? '').toString().toLowerCase();
    final artist = (s['artist'] ?? '').toString().toLowerCase();
    final album = (s['album'] ?? '').toString().toLowerCase();
    final genre = (s['genre'] ?? '').toString().toLowerCase();

    // Check filename from any path/URL/file ID field
    final filePath = (s['local_file_path'] ?? s['file_path'] ?? s['url'] ?? s['gdrive_file_id'] ?? '').toString();
    final filename = filePath.split(RegExp(r'[/\\]')).last.toLowerCase();

    // Tags check if custom tags field exists in the map
    final tagsStr = s.containsKey('tags') ? s['tags'].toString().toLowerCase() : '';

    return title.contains(q) ||
           artist.contains(q) ||
           album.contains(q) ||
           filename.contains(q) ||
           genre.contains(q) ||
           tagsStr.contains(q);
  }
}
