import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/downloads_provider.dart';
import '../services/offline_storage.dart';

class SongDownloadIndicator extends ConsumerWidget {
  final int songId;
  const SongDownloadIndicator({super.key, required this.songId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloads = ref.watch(downloadsProvider);
    final downloadState = downloads[songId];

    final status = downloadState?.status ?? OfflineStorage().getSongDownloadStatus(songId);
    final progress = downloadState?.progress ?? 0.0;

    if (status == 'notDownloaded') {
      return const SizedBox.shrink();
    }

    if (status == 'downloading') {
      return SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(
          value: progress > 0 ? progress : null,
          strokeWidth: 2.0,
          backgroundColor: Colors.white12,
          valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF8B5CF6)),
        ),
      );
    }

    if (status == 'completed') {
      return const Icon(
        Icons.download_done,
        color: Colors.green,
        size: 16,
      );
    }

    return const SizedBox.shrink();
  }
}
