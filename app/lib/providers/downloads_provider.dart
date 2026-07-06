import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/download_manager.dart';
import '../services/offline_storage.dart';

class DownloadState {
  final String status; // 'notDownloaded', 'downloading', 'completed'
  final double progress;

  DownloadState({required this.status, required this.progress});
}

class DownloadsNotifier extends StateNotifier<Map<int, DownloadState>> {
  DownloadsNotifier() : super({}) {
    // Load initial statuses from offline storage
    _syncFromStorage();

    // Listen to download manager progress stream
    DownloadManager().progressStream.listen((event) {
      final songId = event['songId'] as int;
      final status = event['status'] as String;
      final progress = event['progress'] as double;
      
      state = {
        ...state,
        songId: DownloadState(status: status, progress: progress),
      };
    });
  }

  void _syncFromStorage() {
    final playlists = OfflineStorage().getPlaylists();
    final Map<int, DownloadState> initial = {};
    for (final pl in playlists) {
      final songs = List<Map<String, dynamic>>.from(pl['songs'] ?? []);
      for (final s in songs) {
        final songId = s['song_id'] as int;
        final status = s['status'] as String;
        final progress = (s['progress'] as num?)?.toDouble() ?? 0.0;
        
        // If already completed in at least one playlist, keep completed status
        if (initial[songId]?.status == 'completed') continue;
        initial[songId] = DownloadState(status: status, progress: progress);
      }
    }
    state = initial;
  }

  void refresh() {
    _syncFromStorage();
  }
}

final downloadsProvider = StateNotifierProvider<DownloadsNotifier, Map<int, DownloadState>>((ref) {
  return DownloadsNotifier();
});
