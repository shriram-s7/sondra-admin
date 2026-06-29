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
import '../widgets/playlist_search_bar.dart';
import '../widgets/playlist_header.dart';
import '../widgets/song_picker.dart';

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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF111019),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text("Delete Playlist", style: TextStyle(color: Colors.white)),
        content: Text(
          'Are you sure you want to delete "${_playlist['name']}"?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text("Cancel", style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text("Delete", style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final songs = List<Map<String, dynamic>>.from(_playlist['songs'] ?? []);
    if (_playlist['type'] == 'offline') {
      await _downloadManager.deleteAllPlaylistFiles(songs);
    }
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

  void _playSong(Map<String, dynamic> songEntry, List<Map<String, dynamic>> activeList) {
    final song = _buildSongMap(songEntry);
    final playlist = activeList.map((s) => _buildSongMap(s)).toList();
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
  Widget build(BuildContext context) {
    final songs = List<Map<String, dynamic>>.from(_playlist['songs'] ?? []);
    final query = _searchQuery.toLowerCase().trim();
    final filteredSongs = query.isEmpty
        ? songs
        : songs.where((s) => PlaylistSearchBar.matchSong(s, query)).toList();

    final playerState = ref.watch(playerProvider);
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
        elevation: 0,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.only(left: 8, right: 8, top: 8, bottom: bottomPad + 16),
                itemCount: filteredSongs.length + 1,
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
                              return CommonPlaylistHeader(
                                name: _playlist['name'] ?? '',
                                songCount: filteredSongs.length,
                                extraInfo: sizeStr,
                                isShuffled: playerState.shuffle,
                                onPlayAll: filteredSongs.isEmpty ? null : () => _playAll(filteredSongs),
                                onToggleShuffle: () {
                                  ref.read(playerProvider.notifier).toggleShuffle();
                                },
                                searchBar: PlaylistSearchBar(
                                  controller: _searchController,
                                  query: _searchQuery,
                                  onChanged: (val) {
                                    setState(() { _searchQuery = val; });
                                  },
                                  onClear: () {
                                    setState(() {
                                      _searchQuery = '';
                                      _searchController.clear();
                                    });
                                  },
                                ),
                                trailingActions: PopupMenuButton<String>(
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
                                  itemBuilder: (_) => _buildHeaderMenuItems(),
                                ),
                              );
                            },
                          )
                        else
                          CommonPlaylistHeader(
                            name: _playlist['name'] ?? '',
                            songCount: filteredSongs.length,
                            isShuffled: playerState.shuffle,
                            onPlayAll: filteredSongs.isEmpty ? null : () => _playAll(filteredSongs),
                            onToggleShuffle: () {
                              ref.read(playerProvider.notifier).toggleShuffle();
                            },
                            searchBar: PlaylistSearchBar(
                              controller: _searchController,
                              query: _searchQuery,
                              onChanged: (val) {
                                setState(() { _searchQuery = val; });
                              },
                              onClear: () {
                                setState(() {
                                  _searchQuery = '';
                                  _searchController.clear();
                                });
                              },
                            ),
                            trailingActions: PopupMenuButton<String>(
                              icon: const Icon(Icons.more_horiz_rounded, color: Colors.white70),
                              color: const Color(0xFF1C1A25),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              onSelected: (value) async {
                                if (value == 'add') {
                                  _showAddSongsSheet();
                                } else if (value == 'rename') {
                                  _renamePlaylist();
                                } else if (value == 'delete') {
                                  _deletePlaylist();
                                }
                              },
                              itemBuilder: (_) => _buildHeaderMenuItems(),
                            ),
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
                            padding: EdgeInsets.symmetric(vertical: 60.0),
                            child: Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text("🔍 No songs found", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                                  SizedBox(height: 8),
                                  Text("Try another title or artist.", style: TextStyle(color: Colors.white38, fontSize: 14)),
                                ],
                              ),
                            ),
                          ),
                      ],
                    );
                  }
                  final entry = filteredSongs[idx - 1];
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
                      onTap: () => _playSong(entry, filteredSongs),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      leading: SongCoverWidget(
                        song: _buildSongMap(entry),
                        width: 48,
                        height: 48,
                        borderRadius: 6.0,
                      ),
                      title: Text(
                        entry['title'] ?? 'Unknown Track',
                        style: TextStyle(
                          color: isCurrent ? const Color(0xFF8B5CF6) : Colors.white,
                          fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                        ),
                      ),
                      subtitle: Text(
                        entry['artist'] ?? 'Unknown Artist',
                        style: const TextStyle(color: Colors.white38, fontSize: 12),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isCurrent && playerState.isPlaying)
                            const Icon(Icons.equalizer_rounded, color: Color(0xFF8B5CF6), size: 20)
                          else ...[
                            if (status == 'downloading')
                              SizedBox(
                                width: 16, height: 16,
                                child: CircularProgressIndicator(
                                  value: progress,
                                  strokeWidth: 2,
                                  color: const Color(0xFF10B981),
                                ),
                              )
                            else if (status == 'completed')
                              const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 16)
                            else if (status == 'error')
                              const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 16)
                            else
                              Text(
                                "${(entry['duration_seconds'] ?? 0) ~/ 60}:${((entry['duration_seconds'] ?? 0) % 60).toString().padLeft(2, '0')}",
                                style: const TextStyle(color: Colors.white30, fontSize: 11),
                              ),
                          ],
                          const SizedBox(width: 4),
                          if ((_playlist['type'] == 'personal' || _playlist['type'] == 'offline') && _searchQuery.isEmpty) ...[
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
                          SongOptionsButton(
                            song: _buildSongMap(entry),
                            playlistId: _playlist['id'],
                            songEntryId: entry['id'],
                            onPlaylistChanged: _refreshPlaylist,
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

  List<PopupMenuEntry<String>> _buildHeaderMenuItems() {
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

  void _playAll(List<Map<String, dynamic>> activeList) {
    if (activeList.isEmpty) return;
    _playSong(activeList.first, activeList);
  }


  Future<void> _showAddSongsSheet() async {
    final scaffoldContext = context;
    final currentSongs = List<Map<String, dynamic>>.from(_playlist['songs'] ?? []);
    final currentIds = currentSongs.map((s) => s['song_id'] as int).toSet();
    final pickerKey = GlobalKey<SongPickerWidgetState>();

    await showModalBottomSheet<Map<String, dynamic>>(
      context: scaffoldContext,
      backgroundColor: const Color(0xFF111019),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(ctx).size.height * 0.85,
            child: Column(
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
                        onPressed: () {
                          final selected = pickerKey.currentState?.selectedSongs ?? [];
                          Navigator.of(ctx).pop(<String, dynamic>{
                            'songs': selected,
                          });
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
                  child: SongPickerWidget(
                    key: pickerKey,
                    disabledIds: currentIds,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ).then((res) async {
      if (res != null) {
        final songs = List<Map<String, dynamic>>.from(res['songs'] as List);
        if (songs.isEmpty) return;
        final storage = OfflineStorage();
        await storage.addSongsToPlaylist(_playlist['id'] as int, songs);
        
        if (_playlist['type'] == 'offline') {
          for (final song in songs) {
            await _downloadManager.downloadSong(_playlist['id'] as int, song);
          }
        }
        _refreshPlaylist();
      }
    });
  }
}
