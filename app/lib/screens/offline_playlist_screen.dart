import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/offline_storage.dart';
import '../services/download_manager.dart';
import '../providers/player_provider.dart';
import '../widgets/song_cover.dart';
import '../widgets/song_options_menu.dart';

class OfflinePlaylistScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> playlist;
  final VoidCallback? onBack;

  const OfflinePlaylistScreen({super.key, required this.playlist, this.onBack});

  @override
  ConsumerState<OfflinePlaylistScreen> createState() =>
      _OfflinePlaylistScreenState();
}

class _OfflinePlaylistScreenState
    extends ConsumerState<OfflinePlaylistScreen> {
  late Map<String, dynamic> _playlist;
  final DownloadManager _downloadManager = DownloadManager();
  StreamSubscription? _progressSub;

  @override
  void initState() {
    super.initState();
    _playlist = Map<String, dynamic>.from(widget.playlist);
    _progressSub = _downloadManager.progressStream.listen((event) {
      if (event['playlistId'] == _playlist['id']) {
        _refreshPlaylist();
      }
    });
  }

  void _refreshPlaylist() {
    final updated = OfflineStorage().getPlaylist(_playlist['id'] as int);
    if (updated != null && mounted) {
      setState(() {
        _playlist = updated;
      });
    }
  }

  Future<void> _downloadSong(Map<String, dynamic> songEntry) async {
    await _downloadManager
        .downloadSong(_playlist['id'] as int, songEntry);
    _refreshPlaylist();
  }

  Future<void> _downloadAll() async {
    final songs = List<Map<String, dynamic>>.from(_playlist['songs'] ?? []);
    for (final entry in songs) {
      if (entry['status'] == 'notDownloaded') {
        await _downloadManager
            .downloadSong(_playlist['id'] as int, entry);
      }
    }
    _refreshPlaylist();
  }

  Future<void> _deleteSongFile(Map<String, dynamic> songEntry) async {
    final songId = songEntry['song_id'] as int;
    final songEntryId = songEntry['id'] as int;
    await _downloadManager.deleteDownloadedFile(songId);
    await OfflineStorage().updateSongStatus(
        _playlist['id'] as int, songEntryId, 'notDownloaded',
        filePath: null, progress: 0.0);
    _refreshPlaylist();
  }

  Future<void> _deletePlaylist() async {
    final songs = List<Map<String, dynamic>>.from(_playlist['songs'] ?? []);
    await _downloadManager.deleteAllPlaylistFiles(songs);
    await OfflineStorage().deletePlaylist(_playlist['id'] as int);
    if (mounted) {
      if (widget.onBack != null) {
        widget.onBack!();
      } else {
        Navigator.of(context).pop();
      }
    }
  }

  void _playSong(Map<String, dynamic> songEntry) {
    final allSongs = List<Map<String, dynamic>>.from(_playlist['songs'] ?? []);
    final song = _buildSongMap(songEntry);
    final playlist = allSongs.map((s) => _buildSongMap(s)).toList();
    ref.read(playerProvider.notifier).playSong(song, playlist);
  }

  Map<String, dynamic> _buildSongMap(Map<String, dynamic> entry) {
    return {
      'id': entry['song_id'],
      'title': entry['title'],
      'artist': entry['artist'],
      'album': entry['album'],
      'duration_seconds': entry['duration_seconds'],
      'cover_url': entry['cover_url'],
      'local_file_path': entry['local_file_path'],
    };
  }

  @override
  void dispose() {
    _progressSub?.cancel();
    _downloadManager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final songs = List<Map<String, dynamic>>.from(_playlist['songs'] ?? []);
    final playerState = ref.watch(playerProvider);
    final hasPendingDownloads = songs.any((s) => s['status'] == 'downloading');
    final hasNotDownloaded = songs.any((s) => s['status'] == 'notDownloaded');

    return Scaffold(
      backgroundColor: const Color(0xFF08070D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111019),
        foregroundColor: Colors.white,
        leading: widget.onBack != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                onPressed: widget.onBack,
              )
            : null,
        title: Row(
          children: [
            Icon(
                _playlist['type'] == 'personal'
                    ? Icons.playlist_play_rounded
                    : Icons.offline_pin_rounded,
                color: const Color(0xFF8B5CF6),
                size: 20),
            const SizedBox(width: 8),
            Text(_playlist['name'] ?? '',
                style: const TextStyle(color: Colors.white)),
          ],
        ),
        actions: [
          if (hasNotDownloaded && _playlist['type'] != 'personal')
            IconButton(
              onPressed: hasPendingDownloads ? null : _downloadAll,
              icon: hasPendingDownloads
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Color(0xFF8B5CF6)),
                    )
                  : const Icon(Icons.download_rounded,
                      color: Color(0xFF8B5CF6)),
              tooltip: 'Download all',
            ),
          IconButton(
            onPressed: _deletePlaylist,
            icon: const Icon(Icons.delete_outline_rounded,
                color: Colors.redAccent),
            tooltip: 'Delete playlist',
          ),
        ],
        elevation: 0,
      ),
      body: songs.isEmpty
          ? const Center(
              child: Text('No songs in this playlist',
                  style: TextStyle(color: Colors.white38)))
          : ListView.builder(
              padding: const EdgeInsets.only(left: 8, right: 8, top: 8, bottom: 16),
              itemCount: songs.length,
              itemBuilder: (ctx, idx) {
                final entry = songs[idx];
                final status = entry['status'] as String? ?? 'notDownloaded';
                final progress = (entry['progress'] as num?)?.toDouble() ?? 0.0;
                final songId = entry['song_id'] as int;
                final isCurrent = playerState.currentSong?['id'] == songId;

                 return GestureDetector(
                   onSecondaryTapDown: (details) {
                     if (Platform.isWindows) {
                       SongOptionsButton.showRightClickMenu(context, details.globalPosition, ref, _buildSongMap(entry));
                     }
                   },
                   child: ListTile(
                     onTap: () => _playSong(entry),
                     contentPadding:
                         const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                     leading: Stack(
                       children: [
                         SongCoverWidget(
                           song: _buildSongMap(entry),
                           width: 48,
                           height: 48,
                           borderRadius: 6.0,
                         ),
                         if (status == 'completed')
                           Positioned(
                             bottom: 0,
                             right: 0,
                             child: Container(
                               padding: const EdgeInsets.all(2),
                               decoration: const BoxDecoration(
                                 color: Color(0xFF10B981),
                                 shape: BoxShape.circle,
                               ),
                               child: const Icon(Icons.check,
                                   size: 12, color: Colors.white),
                             ),
                           ),
                         if (status == 'notDownloaded')
                           Positioned(
                             bottom: 0,
                             right: 0,
                             child: Container(
                               padding: const EdgeInsets.all(2),
                               decoration: BoxDecoration(
                                 color: Colors.white.withOpacity(0.2),
                                 shape: BoxShape.circle,
                               ),
                               child: const Icon(Icons.cloud_outlined,
                                   size: 12, color: Colors.white54),
                             ),
                           ),
                       ],
                     ),
                     title: Row(
                       children: [
                         Expanded(
                           child: Text(
                             entry['title'] ?? 'Unknown Track',
                             style: TextStyle(
                               color: isCurrent
                                   ? const Color(0xFF8B5CF6)
                                   : Colors.white,
                               fontWeight: isCurrent
                                   ? FontWeight.bold
                                   : FontWeight.w500,
                             ),
                             overflow: TextOverflow.ellipsis,
                           ),
                         ),
                       ],
                     ),
                     subtitle: Column(
                       crossAxisAlignment: CrossAxisAlignment.start,
                       children: [
                         Text(
                           entry['artist'] ?? 'Unknown Artist',
                           style: const TextStyle(
                               color: Colors.white38, fontSize: 12),
                         ),
                         if (status == 'downloading') ...[
                           const SizedBox(height: 4),
                           ClipRRect(
                             borderRadius: BorderRadius.circular(2),
                             child: LinearProgressIndicator(
                               value: progress,
                               backgroundColor: Colors.white.withOpacity(0.1),
                               valueColor: const AlwaysStoppedAnimation<Color>(
                                   Color(0xFF8B5CF6)),
                               minHeight: 3,
                             ),
                           ),
                           Text(
                             '${(progress * 100).toStringAsFixed(0)}%',
                             style: const TextStyle(
                                 color: Color(0xFF8B5CF6), fontSize: 10),
                           ),
                         ],
                       ],
                     ),
                     trailing: Row(
                       mainAxisSize: MainAxisSize.min,
                       children: [
                         if (isCurrent && playerState.isPlaying)
                           const Icon(Icons.equalizer_rounded, color: Color(0xFF8B5CF6), size: 20)
                         else
                           Text(
                             "${(entry["duration_seconds"] ?? 0) ~/ 60}:${((entry["duration_seconds"] ?? 0) % 60).toString().padLeft(2, '0')}",
                             style: const TextStyle(color: Colors.white30, fontSize: 11),
                           ),
                         const SizedBox(width: 4),
                         SongOptionsButton(song: _buildSongMap(entry)),
                       ],
                     ),
                   ),
                 );

              },
            ),
    );
  }
}
