import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import '../services/api_service.dart';
import '../services/offline_storage.dart';

class DownloadManager {
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
    final filePath = p.join(dlDir, '$songId.mp3');

    final url = '${_api.baseUrl}/api/stream/$songId/proxy?token=${_api.token}';
    final cancelToken = CancelToken();
    _activeDownloads[songId.toString()] = cancelToken;

    final storage = OfflineStorage();

    try {
      await storage.updateSongStatus(playlistId, songEntryId, 'downloading',
          progress: 0.0);

      await _api.dio.download(
        url,
        filePath,
        onReceiveProgress: (received, total) {
          final progress = total != -1 ? received / total : 0.0;
          storage.updateSongStatus(playlistId, songEntryId, 'downloading',
              progress: progress);
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

      await storage.updateSongStatus(playlistId, songEntryId, 'completed',
          filePath: filePath, progress: 1.0);
      _progressController.add({
        'playlistId': playlistId,
        'songEntryId': songEntryId,
        'songId': songId,
        'status': 'completed',
        'progress': 1.0,
      });
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        await storage.updateSongStatus(playlistId, songEntryId, 'notDownloaded',
            progress: 0.0);
      } else {
        print('Download failed for song $songId: $e');
        await storage.updateSongStatus(playlistId, songEntryId, 'notDownloaded',
            progress: 0.0);
      }
    } catch (e) {
      print('Download error for song $songId: $e');
      await storage.updateSongStatus(playlistId, songEntryId, 'notDownloaded',
          progress: 0.0);
    } finally {
      _activeDownloads.remove(songId.toString());
    }
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
    _progressController.close();
  }
}
