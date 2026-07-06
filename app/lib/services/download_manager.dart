import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import '../services/api_service.dart';
import '../services/offline_storage.dart';

class DownloadManager {
  static final DownloadManager _instance = DownloadManager._();
  factory DownloadManager() => _instance;
  DownloadManager._();

  final ApiService _api = ApiService();
  final Map<String, CancelToken> _activeDownloads = {};
  final StreamController<Map<String, dynamic>> _progressController =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get progressStream => _progressController.stream;

  Future<void> downloadSong(
    int playlistId,
    Map<String, dynamic> songEntry,
  ) async {
    final songEntryId = songEntry['id'] as int;
    final songId = songEntry['song_id'] as int;
    final dlDir = await OfflineStorage().downloadsDir;
    
    // Verify downloads directory is created before downloading
    final directory = Directory(dlDir);
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    
    final filePath = p.join(dlDir, '$songId.mp3');
    final cancelToken = CancelToken();
    _activeDownloads[songId.toString()] = cancelToken;

    final storage = OfflineStorage();

    int attempts = 0;
    const maxAttempts = 3;
    bool success = false;

    // Set initial status in storage & progress stream
    await storage.updateSongStatus(playlistId, songEntryId, 'downloading', progress: 0.0);
    _progressController.add({
      'playlistId': playlistId,
      'songEntryId': songEntryId,
      'songId': songId,
      'status': 'downloading',
      'progress': 0.0,
    });

    while (attempts < maxAttempts && !success) {
      attempts++;
      print("Download attempt $attempts of $maxAttempts for song $songId. Destination: $filePath");
      
      try {
        if (attempts > 1) {
          print("Refreshing credentials before retry...");
          await _api.init(); // Re-authenticates and refreshes the token on Render
        }

        String url;
        try {
          url = await _api.getDirectStreamUrl(songId);
        } catch (e, stack) {
          print('[DIRECT-FAIL-DL] getDirectStreamUrl threw for song $songId: $e');
          print('[DIRECT-FAIL-DL] stack: $stack');
          url = _api.getProxyStreamUrl(songId);
        }
        print("Download request details: URL=$url, method=GET, headers={Authorization: Bearer ${_api.token}}");

        await _api.dio.download(
          url,
          filePath,
          onReceiveProgress: (received, total) {
            final progress = total != -1 ? (received / total).clamp(0.0, 1.0) : 0.0;
            storage.updateSongStatus(playlistId, songEntryId, 'downloading', progress: progress);
            _progressController.add({
              'playlistId': playlistId,
              'songEntryId': songEntryId,
              'songId': songId,
              'status': 'downloading',
              'progress': progress,
            });
          },
          cancelToken: cancelToken,
        );

        final file = File(filePath);
        final exists = await file.exists();
        final size = exists ? await file.length() : 0;
        print("File existence check after download: path=$filePath, exists=$exists, size=$size bytes");

        if (exists && size > 0) {
          success = true;
          print("Download verified successfully on attempt $attempts. Size: $size bytes.");

          await storage.updateSongStatus(playlistId, songEntryId, 'completed',
              filePath: filePath, progress: 1.0);
          _progressController.add({
            'playlistId': playlistId,
            'songEntryId': songEntryId,
            'songId': songId,
            'status': 'completed',
            'progress': 1.0,
          });
        } else {
          // If it exists but is 0 bytes, delete it
          if (exists) {
            await file.delete();
          }
          throw Exception("Downloaded file is empty or missing on disk.");
        }
      } on DioException catch (e) {
        print("DioException on attempt $attempts for song $songId: type=${e.type}, message=${e.message}, statusCode=${e.response?.statusCode}");
        
        if (e.type == DioExceptionType.cancel) {
          print("Download cancelled by user.");
          await storage.updateSongStatus(playlistId, songEntryId, 'notDownloaded', progress: 0.0);
          _progressController.add({
            'playlistId': playlistId,
            'songEntryId': songEntryId,
            'songId': songId,
            'status': 'notDownloaded',
            'progress': 0.0,
          });
          break; // Don't retry if cancelled
        }

        if (attempts >= maxAttempts) {
          await storage.updateSongStatus(playlistId, songEntryId, 'notDownloaded', progress: 0.0);
          _progressController.add({
            'playlistId': playlistId,
            'songEntryId': songEntryId,
            'songId': songId,
            'status': 'notDownloaded',
            'progress': 0.0,
          });
        } else {
          // Wait and retry
          await Future.delayed(Duration(seconds: 2 * attempts));
        }
      } catch (e) {
        print("General Exception on attempt $attempts for song $songId: $e");
        if (attempts >= maxAttempts) {
          await storage.updateSongStatus(playlistId, songEntryId, 'notDownloaded', progress: 0.0);
          _progressController.add({
            'playlistId': playlistId,
            'songEntryId': songEntryId,
            'songId': songId,
            'status': 'notDownloaded',
            'progress': 0.0,
          });
        } else {
          // Wait and retry
          await Future.delayed(Duration(seconds: 2 * attempts));
        }
      }
    }

    _activeDownloads.remove(songId.toString());
  }

  void cancelDownload(int songId) {
    _activeDownloads[songId.toString()]?.cancel();
    _activeDownloads.remove(songId.toString());
  }

  Future<void> deleteDownloadedFile(int songId) async {
    final dlDir = await OfflineStorage().downloadsDir;
    final file = File(p.join(dlDir, '$songId.mp3'));
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<void> downloadAllSongs(int playlistId, List<Map<String, dynamic>> songEntries) async {
    for (final entry in songEntries) {
      if (entry['status'] == 'notDownloaded') {
        await downloadSong(playlistId, entry);
      }
    }
  }

  Future<void> deleteAllPlaylistFiles(List<Map<String, dynamic>> songEntries) async {
    for (final entry in songEntries) {
      final songId = entry['song_id'] as int;
      await deleteDownloadedFile(songId);
    }
  }

  void dispose() {
    // Keep broadcast controller alive as this is a singleton
  }
}
