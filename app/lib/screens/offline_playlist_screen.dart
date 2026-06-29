import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/offline_storage.dart';
import '../services/download_manager.dart';
import '../providers/player_provider.dart';
import '../widgets/song_cover.dart';
import '../widgets/song_options_menu.dart';
import '../widgets/mini_player.dart';
import 'now_playing_screen.dart';
import '../services/api_service.dart';

class OfflinePlaylistScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> playlist;
  final VoidCallback? onBack;
  final VoidCallback? onPlaylistChanged;

  const OfflinePlaylistScreen({
    super.key,
    required this.playlist,
    this.onBack,
    this.onPlaylistChanged,
  });

  @override
  ConsumerState<OfflinePlaylistScreen> createState() =>
      _OfflinePlaylistScreenState();
}

class _OfflinePlaylistScreenState
    extends ConsumerState<OfflinePlaylistScreen> {
  late Map<String, dynamic> _playlist;
  final DownloadManager _downloadManager = DownloadManager();
  StreamSubscription? _progressSub;
  String _searchQuery = "";
  final _searchController = TextEditingController();

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
      widget.onPlaylistChanged?.call();
    }
  }

  Future<void> _renamePlaylist() async {
    final controller = TextEditingController(text: _playlist['name'] ?? '');
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF111019),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text("Rename Playlist", style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: "Playlist Name",
            hintStyle: TextStyle(color: Colors.white30),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF8B5CF6))),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text("Cancel", style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text("Rename", style: TextStyle(color: Color(0xFF8B5CF6))),
          ),
        ],
      ),
    );

    if (newName != null && newName.isNotEmpty) {
      await OfflineStorage().renamePlaylist(_playlist['id'] as int, newName);
      _refreshPlaylist();
    }
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

  Future<void> _deletePlaylist() async {
    final songs = List<Map<String, dynamic>>.from(_playlist['songs'] ?? []);
    await _downloadManager.deleteAllPlaylistFiles(songs);
    await OfflineStorage().deletePlaylist(_playlist['id'] as int);
    widget.onPlaylistChanged?.call();
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
    ref.read(playerProvider.notifier).playSong(song, playlist, playlistName: _playlist['name']);
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
    _searchController.dispose();
    super.dispose();
  }

  @override
  @override
  Widget build(BuildContext context) {
    final songs = List<Map<String, dynamic>>.from(_playlist['songs'] ?? []);
    final query = _searchQuery.toLowerCase().trim();
    final filteredSongs = query.isEmpty
        ? songs
        : songs.where((s) {
            final title = (s["title"] ?? "").toString().toLowerCase();
            final artist = (s["artist"] ?? "").toString().toLowerCase();
            return title.contains(query) || artist.contains(query);
          }).toList();

    final playerState = ref.watch(playerProvider);
    final hasPendingDownloads = songs.any((s) => s['status'] == 'downloading');
    final hasNotDownloaded = songs.any((s) => s['status'] == 'notDownloaded');

    final bottomPad = playerState.currentSong != null ? (Platform.isWindows ? 90.0 : 76.0) : 0.0;

    return Scaffold(
      backgroundColor: const Color(0xFF08070D),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        leading: widget.onBack != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                onPressed: widget.onBack,
              )
            : null,
        actions: Platform.isWindows ? [] : [
          if (_playlist['type'] == 'personal' || _playlist['type'] == 'offline')
            IconButton(
              onPressed: _showAddSongsSheet,
              icon: const Icon(Icons.playlist_add_rounded, color: Color(0xFF8B5CF6)),
              tooltip: 'Add songs',
            ),
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
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
        padding: EdgeInsets.only(left: 8, right: 8, top: 8, bottom: bottomPad + 16),
        itemCount: filteredSongs.length + 2,
        itemBuilder: (ctx, idx) {
          if (idx == 0) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_playlist['type'] == 'offline')
                  FutureBuilder<int>(
                    future: OfflineStorage.getPlaylistDownloadSize(songs),
                    builder: (context, snapshot) {
                      final sizeStr = snapshot.connectionState == ConnectionState.waiting
                          ? "Calculating size..."
                          : OfflineStorage.formatBytes(snapshot.data ?? 0);
                      return _buildPlaylistHeader(
                        name: _playlist['name'] ?? '',
                        songs: songs,
                        extraInfo: sizeStr,
                      );
                    },
                  )
                else
                  _buildPlaylistHeader(
                    name: _playlist['name'] ?? '',
                    songs: songs,
                  ),
                if (songs.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 32.0),
                    child: Center(
                      child: Text('No songs in this playlist',
                          style: TextStyle(color: Colors.white38)),
                    ),
                  )
                else if (filteredSongs.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 32.0),
                    child: Center(
                      child: Text('No tracks found matching your search',
                          style: TextStyle(color: Colors.white38)),
                    ),
                  ),
              ],
            );
          }
          if (idx == 1) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
              child: TextField(
                controller: _searchController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: "Search in playlist...",
                  hintStyle: const TextStyle(color: Colors.white24),
                  prefixIcon: const Icon(Icons.search_rounded, color: Colors.white38),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, color: Colors.white38, size: 20),
                          onPressed: () {
                            setState(() {
                              _searchQuery = '';
                              _searchController.clear();
                            });
                          },
                        )
                      : null,
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
                onChanged: (val) {
                  setState(() { _searchQuery = val; });
                },
              ),
            );
          }
          final entry = filteredSongs[idx - 2];
                final status = entry['status'] as String? ?? 'notDownloaded';
                final progress = (entry['progress'] as num?)?.toDouble() ?? 0.0;
                final songId = entry['song_id'] as int;
                final isCurrent = playerState.currentSong?['id'] == songId;

                 return GestureDetector(
                    onSecondaryTapDown: (details) {
                      if (Platform.isWindows) {
                        SongOptionsButton.showRightClickMenu(
                          context,
                          details.globalPosition,
                          ref,
                          _buildSongMap(entry),
                          onPlaylistChanged: _refreshPlaylist,
                          playlistId: _playlist['id'],
                          songEntryId: entry['id'],
                        );
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
                          if (_playlist['type'] == 'personal' || _playlist['type'] == 'offline') ...[
                            if (idx - 1 > 0)
                              IconButton(
                                icon: const Icon(Icons.keyboard_arrow_up_rounded, color: Colors.white38, size: 20),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                onPressed: () async {
                                  await OfflineStorage().reorderSong(
                                    _playlist['id'] as int,
                                    idx - 1,
                                    idx - 2,
                                  );
                                  _refreshPlaylist();
                                },
                              ),
                            if (idx - 1 < songs.length - 1)
                              IconButton(
                                icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white38, size: 20),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                onPressed: () async {
                                  await OfflineStorage().reorderSong(
                                    _playlist['id'] as int,
                                    idx - 1,
                                    idx,
                                  );
                                  _refreshPlaylist();
                                },
                              ),
                            const SizedBox(width: 4),
                          ],
                          if (isCurrent && playerState.isPlaying)
                            const Icon(Icons.equalizer_rounded, color: Color(0xFF8B5CF6), size: 20)
                          else
                            Text(
                              "${(entry["duration_seconds"] ?? 0) ~/ 60}:${((entry["duration_seconds"] ?? 0) % 60).toString().padLeft(2, '0')}",
                              style: const TextStyle(color: Colors.white30, fontSize: 11),
                            ),
                          const SizedBox(width: 4),
                          SongOptionsButton(
                            song: _buildSongMap(entry),
                            onPlaylistChanged: _refreshPlaylist,
                            playlistId: _playlist['id'],
                            songEntryId: entry['id'],
                          ),
                        ],
                      ),
                   ),
                  );

              },
            ),
          ),
          if (!Platform.isWindows && playerState.currentSong != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
              child: MiniPlayer(
                onTap: () {
                  ref.read(showNowPlayingProvider.notifier).state = true;
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const NowPlayingScreen(),
                    ),
                  ).then((_) {
                    ref.read(showNowPlayingProvider.notifier).state = false;
                  });
                },
              ),
            ),
        ],
      ),
    ),
    );
  }

  List<PopupMenuEntry<String>> _buildWindowsHeaderMenuItems() {
    final isOffline = _playlist['type'] == 'offline';
    final songs = List<Map<String, dynamic>>.from(_playlist['songs'] ?? []);
    final hasPendingDownloads = songs.any((s) => s['status'] == 'downloading');
    final hasNotDownloaded = songs.any((s) => s['status'] == 'notDownloaded');

    return [
      const PopupMenuItem(
        value: 'add',
        child: ListTile(
          leading: Icon(Icons.playlist_add_rounded, color: Color(0xFF8B5CF6), size: 20),
          title: Text("Add Songs", style: TextStyle(color: Colors.white, fontSize: 13)),
          dense: true,
          contentPadding: EdgeInsets.zero,
        ),
      ),
      if (isOffline && hasNotDownloaded)
        PopupMenuItem(
          value: 'download_all',
          enabled: !hasPendingDownloads,
          child: ListTile(
            leading: Icon(
              hasPendingDownloads ? Icons.hourglass_empty_rounded : Icons.download_rounded,
              color: const Color(0xFF8B5CF6),
              size: 20,
            ),
            title: Text(
              hasPendingDownloads ? "Downloading..." : "Download All",
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
        ),
      const PopupMenuItem(
        value: 'rename',
        child: ListTile(
          leading: Icon(Icons.edit_rounded, color: Colors.white, size: 20),
          title: Text("Rename Playlist", style: TextStyle(color: Colors.white, fontSize: 13)),
          dense: true,
          contentPadding: EdgeInsets.zero,
        ),
      ),
      const PopupMenuItem(
        value: 'delete',
        child: ListTile(
          leading: Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
          title: Text("Delete Playlist", style: TextStyle(color: Colors.redAccent, fontSize: 13)),
          dense: true,
          contentPadding: EdgeInsets.zero,
        ),
      ),
    ];
  }

  Widget _buildPlaylistHeader({
    required String name,
    required List<Map<String, dynamic>> songs,
    String? extraInfo,
  }) {
    final playerState = ref.watch(playerProvider);
    final isShuffled = playerState.shuffle;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(
                "${songs.length} song${songs.length == 1 ? '' : 's'}",
                style: const TextStyle(color: Colors.white54, fontSize: 14),
              ),
              if (extraInfo != null && extraInfo.isNotEmpty) ...[
                const SizedBox(width: 8),
                const Text("•", style: TextStyle(color: Colors.white30)),
                const SizedBox(width: 8),
                Text(
                  extraInfo,
                  style: const TextStyle(color: Color(0xFF10B981), fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: songs.isEmpty ? null : _playAll,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF8B5CF6),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                ),
                icon: const Icon(Icons.play_arrow_rounded, size: 22),
                label: const Text("Play All", style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: () {
                   ref.read(playerProvider.notifier).toggleShuffle();
                 },
                style: OutlinedButton.styleFrom(
                  foregroundColor: isShuffled ? const Color(0xFF8B5CF6) : Colors.white,
                  side: BorderSide(
                    color: isShuffled ? const Color(0xFF8B5CF6) : Colors.white24,
                    width: 1.5,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                ),
                icon: Icon(
                  Icons.shuffle_rounded,
                  color: isShuffled ? const Color(0xFF8B5CF6) : Colors.white70,
                  size: 20,
                ),
                label: Text(
                  "Shuffle",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isShuffled ? const Color(0xFF8B5CF6) : Colors.white,
                  ),
                ),
              ),
              if (Platform.isWindows) ...[
                const SizedBox(width: 12),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_horiz_rounded, color: Colors.white70),
                  color: const Color(0xFF1C1A25),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  onSelected: (value) async {
                    if (value == 'add') {
                      _showAddSongsSheet();
                    } else if (value == 'download_all') {
                      _downloadAll();
                    } else if (value == 'rename') {
                      _renamePlaylist();
                    } else if (value == 'delete') {
                      _deletePlaylist();
                    }
                  },
                  itemBuilder: (_) => _buildWindowsHeaderMenuItems(),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  void _playAll() {
    final songs = List<Map<String, dynamic>>.from(_playlist['songs'] ?? []);
    if (songs.isEmpty) return;
    _playSong(songs.first);
  }

  void _shufflePlay() {
    final songs = List<Map<String, dynamic>>.from(_playlist['songs'] ?? []);
    if (songs.isEmpty) return;
    final playlist = songs.map((s) => _buildSongMap(s)).toList();
    ref.read(playerProvider.notifier).playPlaylistShuffled(playlist, _playlist['name'] ?? '');
  }

  Future<void> _showAddSongsSheet() async {
    final scaffoldContext = context;
    final currentSongs = List<Map<String, dynamic>>.from(_playlist['songs'] ?? []);
    final currentIds = currentSongs.map((s) => s['song_id'] as int).toSet();
    final selectedSongs = <Map<String, dynamic>>[];

    await showModalBottomSheet<List<Map<String, dynamic>>>(
      context: scaffoldContext,
      backgroundColor: const Color(0xFF111019),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setSheetState) {
            return FutureBuilder<List<dynamic>>(
              future: ApiService().getSongs(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const SizedBox(
                    height: 200,
                    child: Center(
                      child: CircularProgressIndicator(color: Color(0xFF8B5CF6)),
                    ),
                  );
                }
                if (snapshot.hasError || !snapshot.hasData) {
                  return const SizedBox(
                    height: 200,
                    child: Center(
                      child: Text("Error fetching songs", style: TextStyle(color: Colors.white54)),
                    ),
                  );
                }

                final allSongs = List<Map<String, dynamic>>.from(snapshot.data!);
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            "Add Songs to Playlist",
                            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          ElevatedButton(
                            onPressed: selectedSongs.isEmpty
                                ? null
                                : () {
                                    Navigator.of(ctx).pop(selectedSongs);
                                  },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF8B5CF6),
                              foregroundColor: Colors.white,
                              disabledBackgroundColor: const Color(0xFF8B5CF6).withOpacity(0.3),
                            ),
                            child: const Text("Add"),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: allSongs.length,
                        itemBuilder: (context, idx) {
                          final song = allSongs[idx];
                          final songId = song['id'] as int;
                          final isAlreadyIn = currentIds.contains(songId);
                          final isSelected = selectedSongs.any((s) => s['id'] == songId);

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
                                color: isAlreadyIn ? Colors.white30 : Colors.white,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            subtitle: Text(
                              song['artist'] ?? 'Unknown Artist',
                              style: TextStyle(
                                color: isAlreadyIn ? Colors.white24 : Colors.white38,
                                fontSize: 12,
                              ),
                            ),
                            trailing: isAlreadyIn
                                ? const Icon(Icons.check_circle_rounded, color: Colors.white24)
                                : Checkbox(
                                    value: isSelected,
                                    activeColor: const Color(0xFF8B5CF6),
                                    onChanged: (val) {
                                      setSheetState(() {
                                        if (val == true) {
                                          selectedSongs.add(song);
                                        } else {
                                          selectedSongs.removeWhere((s) => s['id'] == songId);
                                        }
                                      });
                                    },
                                  ),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    ).then((res) async {
      if (res != null && res.isNotEmpty) {
        final storage = OfflineStorage();
        await storage.addSongsToPlaylist(_playlist['id'] as int, res);
        
        if (_playlist['type'] == 'offline') {
          for (final song in res) {
            await _downloadManager.downloadSong(_playlist['id'] as int, song);
          }
        }
        _refreshPlaylist();
      }
    });
  }
}
