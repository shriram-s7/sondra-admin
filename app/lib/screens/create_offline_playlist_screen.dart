import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_service.dart';
import '../services/offline_storage.dart';
import '../widgets/song_cover.dart';

class CreateOfflinePlaylistScreen extends ConsumerStatefulWidget {
  const CreateOfflinePlaylistScreen({super.key});

  @override
  ConsumerState<CreateOfflinePlaylistScreen> createState() =>
      _CreateOfflinePlaylistScreenState();
}

class _CreateOfflinePlaylistScreenState
    extends ConsumerState<CreateOfflinePlaylistScreen> {
  final _nameController = TextEditingController();
  final Set<int> _selectedSongIds = {};
  List<Map<String, dynamic>> _allSongs = [];
  bool _loadingSongs = true;
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    _nameController.addListener(() => setState(() {}));
    _loadSongs();
  }

  Future<void> _loadSongs() async {
    try {
      final songs = await ApiService().getSongs();
      if (mounted) {
        setState(() {
          _allSongs = List<Map<String, dynamic>>.from(songs);
          _loadingSongs = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingSongs = false;
        });
      }
    }
  }

  Future<void> _createPlaylist() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    setState(() {
      _creating = true;
    });

    final selectedSongs =
        _allSongs.where((s) => _selectedSongIds.contains(s['id'])).toList();

    final storage = OfflineStorage();
    final playlist = await storage.createPlaylist(name, type: 'offline');
    await storage.addSongsToPlaylist(playlist['id'] as int, selectedSongs);

    if (mounted) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF08070D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111019),
        foregroundColor: Colors.white,
        title: const Text('Create Offline Playlist',
            style: TextStyle(color: Colors.white)),
        elevation: 0,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _nameController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Playlist name',
                hintStyle: const TextStyle(color: Colors.white24),
                filled: true,
                fillColor: Colors.white.withOpacity(0.05),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF8B5CF6)),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Select Songs (${_selectedSongIds.length})',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                ElevatedButton(
                  onPressed:
                      _nameController.text.trim().isEmpty || _selectedSongIds.isEmpty || _creating
                          ? null
                          : _createPlaylist,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF8B5CF6),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor:
                        const Color(0xFF8B5CF6).withOpacity(0.3),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 10),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  child: _creating
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Create'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _loadingSongs
                ? const Center(
                    child: CircularProgressIndicator(
                        color: Color(0xFF8B5CF6)))
                : ListView.builder(
                    itemCount: _allSongs.length,
                    itemBuilder: (context, index) {
                      final song = _allSongs[index];
                      final isSelected =
                          _selectedSongIds.contains(song['id']);
                      return ListTile(
                        onTap: () {
                          setState(() {
                            if (isSelected) {
                              _selectedSongIds.remove(song['id']);
                            } else {
                              _selectedSongIds.add(song['id'] as int);
                            }
                          });
                        },
                        leading: SongCoverWidget(
                          song: song,
                          width: 40,
                          height: 40,
                          borderRadius: 4.0,
                        ),
                        title: Text(
                          song['title'] ?? 'Unknown Track',
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w500),
                        ),
                        subtitle: Text(
                          song['artist'] ?? 'Unknown Artist',
                          style:
                              const TextStyle(color: Colors.white38, fontSize: 12),
                        ),
                        trailing: Icon(
                          isSelected
                              ? Icons.check_circle_rounded
                              : Icons.radio_button_unchecked_rounded,
                          color: isSelected
                              ? const Color(0xFF8B5CF6)
                              : Colors.white24,
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
