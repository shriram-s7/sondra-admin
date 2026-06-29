import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../widgets/song_cover.dart';

class SongPickerWidget extends StatefulWidget {
  final Set<int> disabledIds;
  final Set<int> initialSelectedIds;
  final ValueChanged<Set<int>>? onSelectionChanged;
  final bool showLoading;

  const SongPickerWidget({
    super.key,
    this.disabledIds = const {},
    this.initialSelectedIds = const {},
    this.onSelectionChanged,
    this.showLoading = true,
  });

  @override
  State<SongPickerWidget> createState() => SongPickerWidgetState();
}

class SongPickerWidgetState extends State<SongPickerWidget> {
  final Set<int> _selectedIds = {};
  final _searchController = TextEditingController();
  String _searchQuery = "";
  List<Map<String, dynamic>> _allSongs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _selectedIds.addAll(widget.initialSelectedIds);
    _loadSongs();
  }

  Future<void> _loadSongs() async {
    try {
      final songs = await ApiService().getSongs();
      if (mounted) {
        setState(() {
          _allSongs = List<Map<String, dynamic>>.from(songs);
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  List<Map<String, dynamic>> get _filteredSongs {
    final query = _searchQuery.toLowerCase().trim();
    if (query.isEmpty) return _allSongs;
    return _allSongs.where((s) {
      final title = (s['title'] as String? ?? '').toLowerCase();
      final artist = (s['artist'] as String? ?? '').toLowerCase();
      return title.contains(query) || artist.contains(query);
    }).toList();
  }

  List<Map<String, dynamic>> get selectedSongs =>
      _allSongs.where((s) => _selectedIds.contains(s['id'])).toList();

  void _toggleSelectAll() {
    final selectable = _filteredSongs.where((s) => !widget.disabledIds.contains(s['id'])).toList();
    final allSelected = selectable.every((s) => _selectedIds.contains(s['id']));
    setState(() {
      if (allSelected) {
        _selectedIds.removeAll(selectable.map((s) => s['id'] as int));
      } else {
        _selectedIds.addAll(selectable.map((s) => s['id'] as int));
      }
    });
    widget.onSelectionChanged?.call(_selectedIds);
  }

  void _toggleSong(int songId) {
    setState(() {
      if (_selectedIds.contains(songId)) {
        _selectedIds.remove(songId);
      } else {
        _selectedIds.add(songId);
      }
    });
    widget.onSelectionChanged?.call(_selectedIds);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && widget.showLoading) {
      return const SizedBox(
        height: 200,
        child: Center(
          child: CircularProgressIndicator(color: Color(0xFF8B5CF6)),
        ),
      );
    }

    final filtered = _filteredSongs;
    final selectableCount = filtered.where((s) => !widget.disabledIds.contains(s['id'])).length;
    final selectedCount = _selectedIds.length;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: TextField(
            controller: _searchController,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Search songs...',
              hintStyle: const TextStyle(color: Colors.white24),
              prefixIcon: const Icon(Icons.search_rounded, color: Colors.white38, size: 20),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded, color: Colors.white38, size: 18),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                    )
                  : null,
              filled: true,
              fillColor: Colors.white.withOpacity(0.05),
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFF8B5CF6)),
              ),
            ),
            onChanged: (val) => setState(() => _searchQuery = val),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Text(
                '$selectedCount selected',
                style: const TextStyle(color: Colors.white54, fontSize: 13),
              ),
              const Spacer(),
              if (selectableCount > 0)
                TextButton(
                  onPressed: _toggleSelectAll,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    selectableCount > 0 && filtered.every((s) =>
                        widget.disabledIds.contains(s['id']) || _selectedIds.contains(s['id']))
                        ? 'Deselect All'
                        : 'Select All',
                    style: const TextStyle(color: Color(0xFF8B5CF6), fontSize: 13),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: filtered.length,
            itemBuilder: (context, index) {
              final song = filtered[index];
              final songId = song['id'] as int;
              final isDisabled = widget.disabledIds.contains(songId);
              final isSelected = _selectedIds.contains(songId);

              final durSec = song['duration_seconds'] ?? 0;
              final durText = '${durSec ~/ 60}:${(durSec % 60).toString().padLeft(2, '0')}';

              return ListTile(
                leading: SongCoverWidget(
                  song: song,
                  width: 40,
                  height: 40,
                  borderRadius: 4.0,
                ),
                title: Text(
                  song['title'] ?? 'Unknown Track',
                  style: TextStyle(
                    color: isDisabled ? Colors.white30 : Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Row(
                  children: [
                    Expanded(
                      child: Text(
                        song['artist'] ?? 'Unknown Artist',
                        style: TextStyle(
                          color: isDisabled ? Colors.white24 : Colors.white38,
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      durText,
                      style: TextStyle(
                        color: isDisabled ? Colors.white24 : Colors.white30,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
                trailing: isDisabled
                    ? const Icon(Icons.check_circle_rounded, color: Colors.white24, size: 22)
                    : Icon(
                        isSelected
                            ? Icons.check_circle_rounded
                            : Icons.radio_button_unchecked_rounded,
                        color: isSelected
                            ? const Color(0xFF8B5CF6)
                            : Colors.white24,
                        size: 22,
                      ),
                onTap: isDisabled
                    ? null
                    : () => _toggleSong(songId),
              );
            },
          ),
        ),
      ],
    );
  }
}
