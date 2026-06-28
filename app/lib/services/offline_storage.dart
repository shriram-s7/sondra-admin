import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OfflineStorage {
  static final OfflineStorage _instance = OfflineStorage._();
  factory OfflineStorage() => _instance;
  OfflineStorage._();

  List<Map<String, dynamic>> _playlists = [];

  Future<String> get _storageDir async {
    try {
      final dir = await getApplicationSupportDirectory();
      final storage = Directory(p.join(dir.path, 'sondra_data'));
      if (!await storage.exists()) {
        await storage.create(recursive: true);
      }
      return storage.path;
    } catch (e) {
      print("Failed to use application support directory for storage, using temporary directory: $e");
      final tempDir = await getTemporaryDirectory();
      final storage = Directory(p.join(tempDir.path, 'sondra_data'));
      if (!await storage.exists()) {
        await storage.create(recursive: true);
      }
      return storage.path;
    }
  }

  Future<File> get _playlistsFile async {
    final d = await _storageDir;
    return File(p.join(d, 'offline_playlists.json'));
  }

  Future<String> get downloadsDir async {
    try {
      final dir = await getApplicationSupportDirectory();
      final dl = Directory(p.join(dir.path, 'sondra_downloads'));
      if (!await dl.exists()) {
        await dl.create(recursive: true);
      }
      return dl.path;
    } catch (e) {
      print("Failed to use application support directory for downloads, using temporary directory: $e");
      final tempDir = await getTemporaryDirectory();
      final dl = Directory(p.join(tempDir.path, 'sondra_downloads'));
      if (!await dl.exists()) {
        await dl.create(recursive: true);
      }
      return dl.path;
    }
  }

  Future<void> init() async {
    await checkVersionAndCleanup();
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

  Future<Map<String, dynamic>> createPlaylist(String name, {String type = 'offline'}) async {
    final id = DateTime.now().millisecondsSinceEpoch;
    final entry = <String, dynamic>{
      'id': id,
      'name': name,
      'type': type,
      'created_at': DateTime.now().toIso8601String(),
      'songs': <Map<String, dynamic>>[],
    };
    _playlists.insert(0, entry);
    await _save();
    return entry;
  }

  List<Map<String, dynamic>> getPlaylists() {
    return List.from(_playlists.map((pl) => {
      ...pl,
      'type': pl['type'] ?? 'offline',
    }));
  }

  Map<String, dynamic>? getPlaylist(int id) {
    final matches = _playlists.where((p) => p['id'] == id);
    if (matches.isEmpty) return null;
    final pl = matches.first;
    return {
      ...pl,
      'type': pl['type'] ?? 'offline',
    };
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

  Future<void> reorderSong(int playlistId, int fromIndex, int toIndex) async {
    final plIdx = _playlists.indexWhere((p) => p['id'] == playlistId);
    if (plIdx == -1) return;

    final songs = List<Map<String, dynamic>>.from(_playlists[plIdx]['songs'] ?? []);
    if (fromIndex < 0 || fromIndex >= songs.length || toIndex < 0 || toIndex >= songs.length) {
      return;
    }

    final item = songs.removeAt(fromIndex);
    songs.insert(toIndex, item);

    _playlists[plIdx]['songs'] = songs;
    await _save();
  }

  Future<void> deletePlaylist(int playlistId) async {
    _playlists.removeWhere((p) => p['id'] == playlistId);
    await _save();
  }

  Future<void> renamePlaylist(int playlistId, String newName) async {
    final idx = _playlists.indexWhere((p) => p['id'] == playlistId);
    if (idx == -1) return;
    _playlists[idx]['name'] = newName;
    await _save();
  }

  Future<void> removeSongDownload(int songId) async {
    bool changed = false;
    for (int i = 0; i < _playlists.length; i++) {
      final songs = List<Map<String, dynamic>>.from(_playlists[i]['songs'] ?? []);
      bool playlistChanged = false;
      for (int j = 0; j < songs.length; j++) {
        if (songs[j]['song_id'] == songId) {
          songs[j]['status'] = 'notDownloaded';
          songs[j]['local_file_path'] = null;
          songs[j]['progress'] = 0.0;
          playlistChanged = true;
          changed = true;
        }
      }
      if (playlistChanged) {
        _playlists[i]['songs'] = songs;
      }
    }
    if (changed) {
      await _save();
    }
  }

  Future<void> clearAllDownloads() async {
    try {
      final dPath = await downloadsDir;
      final downloadDir = Directory(dPath);
      if (await downloadDir.exists()) {
        await for (final entity in downloadDir.list(recursive: true)) {
          if (entity is File) {
            await entity.delete();
          }
        }
      }
      // Reset statuses in all playlists
      for (int i = 0; i < _playlists.length; i++) {
        final songs = List<Map<String, dynamic>>.from(_playlists[i]['songs'] ?? []);
        for (int j = 0; j < songs.length; j++) {
          songs[j]['status'] = 'notDownloaded';
          songs[j]['local_file_path'] = null;
          songs[j]['progress'] = 0.0;
        }
        _playlists[i]['songs'] = songs;
      }
      await _save();
    } catch (e) {
      print("Error clearing all downloads: $e");
    }
  }

  static Future<int> getCacheSize() async {
    int total = 0;
    try {
      final tempDir = await getTemporaryDirectory();
      // 1. just_audio_cache directory
      final justAudioCacheDir = Directory(p.join(tempDir.path, 'just_audio_cache'));
      if (await justAudioCacheDir.exists()) {
        await for (final entity in justAudioCacheDir.list(recursive: true)) {
          if (entity is File) {
            total += await entity.length();
          }
        }
      }
      // 2. sondra_cache_* files in tempDir
      await for (final entity in tempDir.list()) {
        if (entity is File && p.basename(entity.path).startsWith('sondra_cache_')) {
          total += await entity.length();
        }
      }
    } catch (e) {
      print("Error getting cache size: $e");
    }
    return total;
  }

  static Future<void> clearCache() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final justAudioCacheDir = Directory(p.join(tempDir.path, 'just_audio_cache'));
      if (await justAudioCacheDir.exists()) {
        await justAudioCacheDir.delete(recursive: true);
      }
      await for (final entity in tempDir.list()) {
        if (entity is File && p.basename(entity.path).startsWith('sondra_cache_')) {
          await entity.delete();
        }
      }
    } catch (e) {
      print("Error clearing cache: $e");
    }
  }

  static Future<int> getTotalDownloadSize() async {
    try {
      final dPath = await OfflineStorage().downloadsDir;
      final downloadDir = Directory(dPath);
      if (!await downloadDir.exists()) return 0;
      int total = 0;
      await for (final entity in downloadDir.list(recursive: true)) {
        if (entity is File) {
          total += await entity.length();
        }
      }
      return total;
    } catch (e) {
      print("Error getting total download size: $e");
      return 0;
    }
  }

  static Future<int> getPlaylistDownloadSize(List<dynamic> songs) async {
    try {
      final dPath = await OfflineStorage().downloadsDir;
      final downloadDir = Directory(dPath);
      if (!await downloadDir.exists()) return 0;
      int total = 0;
      for (final s in songs) {
        if (s['status'] == 'completed') {
          final songId = s['song_id'] ?? s['id'];
          final file = File(p.join(dPath, '$songId.mp3'));
          if (await file.exists()) {
            total += await file.length();
          }
        }
      }
      return total;
    } catch (e) {
      print("Error getting playlist download size: $e");
      return 0;
    }
  }

  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  Future<void> checkVersionAndCleanup() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      const String currentVersion = "1.0.0+1"; // Matches version in pubspec.yaml
      final storedVersion = prefs.getString("sondra_app_version");
      if (storedVersion != currentVersion) {
        print("Version mismatch: stored '$storedVersion', current '$currentVersion'. Performing full cleanup.");
        await clearAllData();
        await prefs.setString("sondra_app_version", currentVersion);
      }
    } catch (e) {
      print("Error in checkVersionAndCleanup: $e");
    }
  }

  Future<void> clearAllData() async {
    try {
      // 1. Delete all files in downloads directory
      final dPath = await downloadsDir;
      final downloadDir = Directory(dPath);
      if (await downloadDir.exists()) {
        await for (final entity in downloadDir.list(recursive: true)) {
          if (entity is File) {
            await entity.delete();
          }
        }
      }

      // 2. Delete offline_playlists.json
      final file = await _playlistsFile;
      if (await file.exists()) {
        await file.delete();
      }
      _playlists = []; // Clear in-memory cache

      // 3. Clear just_audio cache
      await clearCache();

      print("Full data cleanup completed.");
    } catch (e) {
      print("Error clearing all data: $e");
    }
  }
}
