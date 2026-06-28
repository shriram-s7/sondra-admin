import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class OfflineStorage {
  static final OfflineStorage _instance = OfflineStorage._();
  factory OfflineStorage() => _instance;
  OfflineStorage._();

  List<Map<String, dynamic>> _playlists = [];

  Future<String> get _storageDir async {
    final dir = await getApplicationDocumentsDirectory();
    final storage = Directory(p.join(dir.path, 'sondra_data'));
    if (!await storage.exists()) {
      await storage.create(recursive: true);
    }
    return storage.path;
  }

  Future<File> get _playlistsFile async {
    final d = await _storageDir;
    return File(p.join(d, 'offline_playlists.json'));
  }

  Future<String> get downloadsDir async {
    final dir = await getApplicationDocumentsDirectory();
    final dl = Directory(p.join(dir.path, 'sondra_downloads'));
    if (!await dl.exists()) {
      await dl.create(recursive: true);
    }
    return dl.path;
  }

  Future<void> init() async {
    final file = await _playlistsFile;
    if (await file.exists()) {
      final content = await file.readAsString();
      if (content.isNotEmpty) {
        _playlists = List<Map<String, dynamic>>.from(jsonDecode(content));
        // Reset any downloads stuck in 'downloading' state from a previous session
        bool changed = false;
        for (final pl in _playlists) {
          final songs = List<Map<String, dynamic>>.from(pl['songs'] ?? []);
          for (final song in songs) {
            if (song['status'] == 'downloading') {
              song['status'] = 'notDownloaded';
              song['progress'] = 0.0;
              changed = true;
            }
          }
        }
        if (changed) await _save();
      }
    }
  }

  Future<void> _save() async {
    final file = await _playlistsFile;
    await file.writeAsString(jsonEncode(_playlists));
  }

  Future<Map<String, dynamic>> createPlaylist(String name) async {
    final id = DateTime.now().millisecondsSinceEpoch;
    final entry = <String, dynamic>{
      'id': id,
      'name': name,
      'created_at': DateTime.now().toIso8601String(),
      'songs': <Map<String, dynamic>>[],
    };
    _playlists.insert(0, entry);
    await _save();
    return entry;
  }

  List<Map<String, dynamic>> getPlaylists() {
    return List.from(_playlists);
  }

  Map<String, dynamic>? getPlaylist(int id) {
    final matches = _playlists.where((p) => p['id'] == id);
    return matches.isNotEmpty ? Map<String, dynamic>.from(matches.first) : null;
  }

  Future<void> addSongsToPlaylist(int playlistId, List<Map<String, dynamic>> songs) async {
    final idx = _playlists.indexWhere((p) => p['id'] == playlistId);
    if (idx == -1) return;
    final existing = _playlists[idx];
    final existingSongs = List<Map<String, dynamic>>.from(existing['songs'] ?? []);
    final existingSongIds = existingSongs.map((s) => s['song_id'] as int).toSet();

    for (final song in songs) {
      final sid = song['id'] as int;
      if (!existingSongIds.contains(sid)) {
        existingSongs.add({
          'id': DateTime.now().millisecondsSinceEpoch + existingSongs.length,
          'playlist_id': playlistId,
          'song_id': sid,
          'title': song['title'] ?? 'Unknown Track',
          'artist': song['artist'],
          'album': song['album'],
          'duration_seconds': song['duration_seconds'],
          'cover_url': song['cover_url'],
          'local_file_path': null,
          'status': 'notDownloaded',
          'progress': 0.0,
        });
      }
    }

    _playlists[idx] = {
      ...existing,
      'songs': existingSongs,
    };
    await _save();
  }

  Future<void> updateSongStatus(int playlistId, int songEntryId, String status, {String? filePath, double? progress}) async {
    final plIdx = _playlists.indexWhere((p) => p['id'] == playlistId);
    if (plIdx == -1) return;
    final songs = List<Map<String, dynamic>>.from(_playlists[plIdx]['songs'] ?? []);
    final songIdx = songs.indexWhere((s) => s['id'] == songEntryId);
    if (songIdx == -1) return;

    songs[songIdx]['status'] = status;
    if (filePath != null) songs[songIdx]['local_file_path'] = filePath;
    if (progress != null) songs[songIdx]['progress'] = progress;

    _playlists[plIdx]['songs'] = songs;
    await _save();
  }

  Future<void> deleteSong(int playlistId, int songEntryId) async {
    final plIdx = _playlists.indexWhere((p) => p['id'] == playlistId);
    if (plIdx == -1) return;
    final songs = List<Map<String, dynamic>>.from(_playlists[plIdx]['songs'] ?? []);
    songs.removeWhere((s) => s['id'] == songEntryId);
    _playlists[plIdx]['songs'] = songs;
    await _save();
  }

  Future<void> deletePlaylist(int playlistId) async {
    _playlists.removeWhere((p) => p['id'] == playlistId);
    await _save();
  }

  static Future<int> getTotalDownloadSize() async {
    final dir = await getApplicationDocumentsDirectory();
    final downloadDir = Directory(p.join(dir.path, 'sondra_downloads'));
    if (!await downloadDir.exists()) return 0;
    int total = 0;
    await for (final entity in downloadDir.list()) {
      if (entity is File) {
        total += await entity.length();
      }
    }
    return total;
  }

  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}
