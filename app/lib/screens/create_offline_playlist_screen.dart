import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/offline_storage.dart';
import '../widgets/song_picker.dart';

class CreateOfflinePlaylistScreen extends ConsumerStatefulWidget {
  final String type;

  const CreateOfflinePlaylistScreen({super.key, this.type = 'offline'});

  @override
  ConsumerState<CreateOfflinePlaylistScreen> createState() =>
      _CreateOfflinePlaylistScreenState();
}

class _CreateOfflinePlaylistScreenState
    extends ConsumerState<CreateOfflinePlaylistScreen> {
  final _nameController = TextEditingController();
  final _songPickerKey = GlobalKey<SongPickerWidgetState>();
  bool _creating = false;
  bool _showSongPicker = false;

  String get _typeLabel => widget.type == 'personal' ? 'Personal' : 'Offline';

  @override
  void initState() {
    super.initState();
    _nameController.addListener(() => setState(() {}));
  }

  Future<void> _onSongsConfirmed(List<Map<String, dynamic>> selectedSongs) async {
    if (_creating) return;
    setState(() => _creating = true);

    final name = _nameController.text.trim();
    final storage = OfflineStorage();
    final playlist = await storage.createPlaylist(name, type: widget.type);
    if (selectedSongs.isNotEmpty) {
      await storage.addSongsToPlaylist(playlist['id'] as int, selectedSongs);
    }

    if (mounted) {
      Navigator.of(context).pop(playlist);
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
        title: Text(
          _showSongPicker ? 'Select Songs' : 'Create $_typeLabel Playlist',
          style: const TextStyle(color: Colors.white),
        ),
        elevation: 0,
      ),
      body: _showSongPicker ? _buildSongPicker() : _buildNameStep(),
    );
  }

  Widget _buildNameStep() {
    return Column(
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
            autofocus: true,
          ),
        ),
        const Spacer(),
        Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _nameController.text.trim().isEmpty ? null : () {
                setState(() => _showSongPicker = true);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF8B5CF6),
                foregroundColor: Colors.white,
                disabledBackgroundColor: const Color(0xFF8B5CF6).withOpacity(0.3),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Next', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
        ),
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildSongPicker() {
    return Column(
      children: [
        Expanded(
          child: SongPickerWidget(
            key: _songPickerKey,
            showLoading: true,
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _creating
                  ? null
                  : () {
                      final selected = _songPickerKey.currentState?.selectedSongs ?? [];
                      _onSongsConfirmed(selected);
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF8B5CF6),
                foregroundColor: Colors.white,
                disabledBackgroundColor: const Color(0xFF8B5CF6).withOpacity(0.3),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _creating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Create Playlist', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
        ),
      ],
    );
  }
}
