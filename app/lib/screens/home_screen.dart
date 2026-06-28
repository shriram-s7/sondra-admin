import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_service.dart';
import '../services/offline_storage.dart';
import '../providers/player_provider.dart';
import '../widgets/song_cover.dart';
import '../widgets/mini_player.dart';
import 'setup_screen.dart';
import 'now_playing_screen.dart';
import 'create_offline_playlist_screen.dart';
import 'offline_playlist_screen.dart';
import '../widgets/song_options_menu.dart';

// Riverpod Data Providers
final songsProvider = FutureProvider.autoDispose<List<dynamic>>((ref) async {
  return await ApiService().getSongs();
});

final playlistsProvider = FutureProvider.autoDispose<List<dynamic>>((ref) async {
  return await ApiService().getPlaylists();
});

final historyRecentProvider = FutureProvider.autoDispose<List<dynamic>>((ref) async {
  return await ApiService().getHistoryRecent();
});

final historyContinueProvider = FutureProvider.autoDispose<List<dynamic>>((ref) async {
  return await ApiService().getHistoryContinue();
});

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _currentIndex = 0;
  String _searchQuery = "";
  final _searchController = TextEditingController();
  bool _isSyncingLocal = false;
  Map<String, dynamic>? _selectedPlaylistWindows;
  Map<String, dynamic>? _selectedOfflinePlaylistWindows;

  @override
  void initState() {
    super.initState();

    // Listen to SSE Events
    ApiService().sseController.stream.listen((event) {
      if (event["type"] == "library_updated") {
        if (mounted) {
          // Invalidate Riverpod providers to trigger silent reload
          ref.invalidate(songsProvider);
          ref.invalidate(playlistsProvider);
          ref.invalidate(historyRecentProvider);
          ref.invalidate(historyContinueProvider);
        }
      }
    });
  }

  void _pollSyncStatus() async {
    Timer.periodic(const Duration(seconds: 2), (timer) async {
      try {
        final status = await ApiService().getSyncStatus();
        final isSyncing = status["is_syncing"] ?? false;
        if (!isSyncing) {
          timer.cancel();
          if (mounted) {
            setState(() {
              _isSyncingLocal = false;
            });
            // Force reload providers
            ref.invalidate(songsProvider);
            ref.invalidate(playlistsProvider);
            ref.invalidate(historyRecentProvider);
            ref.invalidate(historyContinueProvider);
          }
        }
      } catch (e) {
        timer.cancel();
        if (mounted) {
          setState(() {
            _isSyncingLocal = false;
          });
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final playerState = ref.watch(playerProvider);
    final showNowPlayingWindows = ref.watch(showNowPlayingProvider);
    final hasSong = playerState.currentSong != null;

    return Scaffold(
      backgroundColor: const Color(0xFF08070D),
      body: SafeArea(
        child: Column(
          children: [
            // Screen content — scrollable behind the mini-player
            Expanded(
              child: Platform.isWindows
                  ? _buildDesktopLayout(showNowPlayingWindows)
                  : IndexedStack(
                      index: _currentIndex,
                      children: [
                        _buildHomeTab(),
                        _buildLibraryTab(),
                        _buildPlaylistsTab(),
                        _buildSettingsTab(),
                      ],
                    ),
            ),
            // Android: mini-player always sits directly above the nav bar
            if (!Platform.isWindows && hasSong)
              MiniPlayer(
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
            // Windows: mini-player always visible at bottom (even with right panel open)
            if (hasSong && Platform.isWindows)
              MiniPlayer(
                onTap: () {
                  ref.read(showNowPlayingProvider.notifier).state = true;
                },
              ),
          ],
        ),
      ),
      bottomNavigationBar: Platform.isAndroid
          ? BottomNavigationBar(
              currentIndex: _currentIndex,
              onTap: (idx) {
                setState(() { _currentIndex = idx; });
              },
              backgroundColor: const Color(0xFF111019),
              selectedItemColor: const Color(0xFF8B5CF6),
              unselectedItemColor: Colors.white60,
              type: BottomNavigationBarType.fixed,
              items: const [
                BottomNavigationBarItem(icon: Icon(Icons.home_rounded), label: "Home"),
                BottomNavigationBarItem(icon: Icon(Icons.music_note_rounded), label: "Library"),
                BottomNavigationBarItem(icon: Icon(Icons.list_rounded), label: "Playlists"),
                BottomNavigationBarItem(icon: Icon(Icons.settings_rounded), label: "Settings"),
              ],
            )
          : null,
    );
  }

  // ── Desktop Layout: sidebar + content + optional right now-playing panel
  Widget _buildDesktopLayout(bool showNowPlayingWindows) {
    return Row(
      children: [
        _buildSidebar(),
        Expanded(
          child: IndexedStack(
            index: _currentIndex,
            children: [
              _buildHomeTab(),
              _buildLibraryTab(),
              _buildPlaylistsTab(),
              _buildSettingsTab(),
            ],
          ),
        ),
        if (showNowPlayingWindows)
          NowPlayingRightPanel(
            onClose: () {
              ref.read(showNowPlayingProvider.notifier).state = false;
            },
          ),
      ],
    );
  }

  // ── Left Sidebar (Windows only)
  Widget _buildSidebar() {
    return Container(
      width: 180,
      color: const Color(0xFF111019),
      child: Column(
        children: [
          const SizedBox(height: 20),
          Row(
            children: [
              const SizedBox(width: 14),
              const Icon(Icons.music_note_rounded, color: Color(0xFF8B5CF6), size: 24),
              const SizedBox(width: 8),
              const Text("Sondra", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 28),
          _sidebarItem(Icons.home_rounded, "Home", 0),
          _sidebarItem(Icons.music_note_rounded, "Library", 1),
          _sidebarItem(Icons.list_rounded, "Playlists", 2),
          const Spacer(),
          _sidebarItem(Icons.settings_rounded, "Settings", 3),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _sidebarItem(IconData icon, String label, int index) {
    final selected = _currentIndex == index;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: selected ? const Color(0xFF8B5CF6).withOpacity(0.15) : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
      ),
      child: ListTile(
        dense: true,
        visualDensity: VisualDensity.compact,
        leading: Icon(icon, color: selected ? const Color(0xFF8B5CF6) : Colors.white60, size: 20),
        title: Text(label, style: TextStyle(color: selected ? Colors.white : Colors.white60, fontSize: 13, fontWeight: selected ? FontWeight.w600 : FontWeight.normal)),
        onTap: () => setState(() { _currentIndex = index; }),
      ),
    );
  }

  // --- TAB BUILDERS ---

  Widget _buildHomeTab() {
    final recentAsync = ref.watch(historyRecentProvider);

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Recently Played",
              style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          Expanded(
            child: recentAsync.when(
              data: (songs) {
                if (songs.isEmpty) {
                  return const Center(
                      child: Text("No recently played tracks",
                          style: TextStyle(color: Colors.white38)));
                }
                return ListView.builder(
                  itemCount: songs.length,
                  itemBuilder: (context, index) {
                    final entry = songs[index];
                    final song = entry["song"];
                    if (song == null) return const SizedBox.shrink();
                    final s = Map<String, dynamic>.from(song);
                    return GestureDetector(
                      onSecondaryTapDown: (details) {
                        if (Platform.isWindows) {
                          SongOptionsButton.showRightClickMenu(context, details.globalPosition, ref, s);
                        }
                      },
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        onTap: () => ref.read(playerProvider.notifier).playSong(
                          s,
                          List<Map<String, dynamic>>.from(songs.map((e) => e["song"])),
                          playlistName: "Recently Played",
                        ),
                        leading: SongCoverWidget(song: s, width: 44, height: 44, borderRadius: 6.0),
                        title: Text(s["title"] ?? "Unknown Track",
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                        subtitle: Text(s["artist"] ?? "Unknown Artist",
                            style: const TextStyle(color: Colors.white38, fontSize: 12)),
                      ),
                    );
                  },
                );
              },
              loading: () =>
                  const Center(child: CircularProgressIndicator(color: Color(0xFF8B5CF6))),
              error: (e, s) =>
                  Center(child: Text("Error: $e", style: const TextStyle(color: Colors.redAccent))),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLibraryTab() {
    final songsAsync = ref.watch(songsProvider);
    final playerState = ref.watch(playerProvider);

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Music Library", style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          TextField(
            controller: _searchController,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: "Search by title, artist...",
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
          const SizedBox(height: 16),
          Expanded(
            child: songsAsync.when(
              data: (songs) {
                final allSongs = List<Map<String, dynamic>>.from(songs);
                final query = _searchQuery.toLowerCase().trim();
                final filtered = query.isEmpty
                    ? allSongs
                    : allSongs.where((s) {
                        final title = (s["title"] ?? "").toString().toLowerCase();
                        final artist = (s["artist"] ?? "").toString().toLowerCase();
                        return title.contains(query) || artist.contains(query);
                      }).toList();

                if (filtered.isEmpty) {
                  return Center(
                    child: Text(
                      query.isEmpty ? "No songs in your library" : "No tracks found",
                      style: const TextStyle(color: Colors.white38),
                    ),
                  );
                }

                return ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final song = filtered[index];
                    final isCurrent = playerState.currentSong?["id"] == song["id"];
                    return GestureDetector(
                      onSecondaryTapDown: (details) {
                        if (Platform.isWindows) {
                          SongOptionsButton.showRightClickMenu(context, details.globalPosition, ref, song);
                        }
                      },
                      child: ListTile(
                        onTap: () => ref.read(playerProvider.notifier).playSong(song, filtered, playlistName: "Music Library"),
                        contentPadding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                        leading: SongCoverWidget(
                          song: song,
                          width: 48,
                          height: 48,
                          borderRadius: 6.0,
                        ),
                        title: Text(
                          song["title"] ?? "Unknown Track", 
                          style: TextStyle(
                            color: isCurrent ? const Color(0xFF8B5CF6) : Colors.white, 
                            fontWeight: isCurrent ? FontWeight.bold : FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(song["artist"] ?? "Unknown Artist", style: const TextStyle(color: Colors.white38, fontSize: 12)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (isCurrent && playerState.isPlaying)
                              const Icon(Icons.equalizer_rounded, color: Color(0xFF8B5CF6), size: 20)
                            else
                              Text(
                                "${(song["duration_seconds"] ~/ 60).toString().padLeft(2, '0')}:${(song["duration_seconds"] % 60).toString().padLeft(2, '0')}",
                                style: const TextStyle(color: Colors.white30, fontSize: 11),
                              ),
                            const SizedBox(width: 4),
                            SongOptionsButton(song: song),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator(color: Color(0xFF8B5CF6))),
              error: (e, s) => Center(child: Text("Error: $e", style: const TextStyle(color: Colors.redAccent))),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaylistsTab() {
    // Windows: show inline detail for online playlist
    if (Platform.isWindows && _selectedPlaylistWindows != null) {
      final pl = _selectedPlaylistWindows!;
      final pSongs = List<Map<String, dynamic>>.from(pl["songs"] ?? []);
      return _PlaylistDetailScreenInline(
        name: pl["name"] ?? "Playlist",
        songs: pSongs,
        onBack: () => setState(() => _selectedPlaylistWindows = null),
      );
    }
    // Windows: show inline detail for offline/personal playlist
    if (Platform.isWindows && _selectedOfflinePlaylistWindows != null) {
      final pl = _selectedOfflinePlaylistWindows!;
      return OfflinePlaylistScreen(
        playlist: pl,
        onBack: () => setState(() => _selectedOfflinePlaylistWindows = null),
        key: ValueKey(pl['id']),
      );
    }

    final playlistsAsync = ref.watch(playlistsProvider);
    final allLocalPlaylists = OfflineStorage().getPlaylists();
    final personalPlaylists = allLocalPlaylists.where((p) => p['type'] == 'personal').toList();
    final offlinePlaylists = allLocalPlaylists.where((p) => p['type'] == 'offline').toList();

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Playlists",
              style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          Expanded(
            child: ListView(
              children: [
                // ═══════════════════════════════════════════════════
                // SECTION 1 — My Library Playlists (Google Drive)
                // ═══════════════════════════════════════════════════
                _SectionHeader(
                  icon: Icons.cloud_rounded,
                  label: "My Library Playlists",
                  color: const Color(0xFFFBBF24),
                  subtitle: "Synced from Google Drive folders · Read only",
                ),
                const SizedBox(height: 4),
                if (playlistsAsync is AsyncData && playlistsAsync.value!.isNotEmpty)
                  ...playlistsAsync.when(
                    data: (lists) => lists.map<Widget>((pl) {
                      final pSongs = List<Map<String, dynamic>>.from(pl["songs"] ?? []);
                      return _PlaylistCard(
                        icon: Icons.cloud_rounded,
                        iconColor: const Color(0xFFFBBF24),
                        name: pl["name"] ?? "Unnamed",
                        subtitle: "${pl["song_count"] ?? 0} songs",
                        onTap: () {
                          if (Platform.isWindows) {
                            setState(() => _selectedPlaylistWindows = pl);
                          } else {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => _PlaylistDetailScreen(
                                  name: pl["name"] ?? "Playlist",
                                  songs: pSongs,
                                ),
                              ),
                            );
                          }
                        },
                      );
                    }),
                    loading: () => [const Center(child: CircularProgressIndicator(color: Color(0xFF8B5CF6)))],
                    error: (e, s) => [Text("Error: $e", style: const TextStyle(color: Colors.redAccent))],
                  )
                else
                  _emptyHint("No library playlists yet"),
                const SizedBox(height: 28),
                const Divider(color: Colors.white10, height: 1),
                const SizedBox(height: 16),

                // ═══════════════════════════════════════════════════
                // SECTION 2 — Personal Playlists
                // ═══════════════════════════════════════════════════
                _SectionHeader(
                  icon: Icons.playlist_play_rounded,
                  label: "Personal Playlists",
                  color: const Color(0xFF8B5CF6),
                  subtitle: "Custom orderings of your library songs",
                  trailing: IconButton(
                    icon: const Icon(Icons.add_circle_rounded, color: Color(0xFF8B5CF6), size: 22),
                    onPressed: _createPersonalPlaylist,
                    tooltip: "Create Personal Playlist",
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ),
                const SizedBox(height: 4),
                if (personalPlaylists.isNotEmpty)
                  ...personalPlaylists.map<Widget>((pl) {
                    final songs = List<Map<String, dynamic>>.from(pl["songs"] ?? []);
                    return _PlaylistCard(
                      icon: Icons.playlist_play_rounded,
                      iconColor: const Color(0xFF8B5CF6),
                      name: pl["name"] ?? "Unnamed",
                      subtitle: "${songs.length} songs",
                      onTap: () async {
                        if (Platform.isWindows) {
                          setState(() => _selectedOfflinePlaylistWindows = pl);
                        } else {
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => OfflinePlaylistScreen(
                                playlist: pl,
                                key: ValueKey(pl['id']),
                              ),
                            ),
                          );
                          if (mounted) setState(() {});
                        }
                      },
                      trailing: PopupMenuButton<String>(
                        icon: const Icon(Icons.more_horiz_rounded, color: Colors.white38, size: 20),
                        color: const Color(0xFF1C1A25),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        onSelected: (value) async {
                          if (value == 'rename') {
                            await _renamePlaylist(pl['id'], pl['name'] ?? '');
                          } else if (value == 'delete') {
                            await _deletePlaylist(pl['id'], pl['name'] ?? '');
                          }
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(value: 'rename', child: ListTile(
                            leading: Icon(Icons.edit_rounded, color: Colors.white, size: 20),
                            title: Text('Rename', style: TextStyle(color: Colors.white, fontSize: 14)),
                            dense: true, contentPadding: EdgeInsets.zero,
                          )),
                          const PopupMenuItem(value: 'delete', child: ListTile(
                            leading: Icon(Icons.delete_rounded, color: Colors.redAccent, size: 20),
                            title: Text('Delete', style: TextStyle(color: Colors.redAccent, fontSize: 14)),
                            dense: true, contentPadding: EdgeInsets.zero,
                          )),
                        ],
                      ),
                    );
                  })
                else
                  _emptyHint("Tap + to create your first personal playlist"),
                const SizedBox(height: 28),
                const Divider(color: Colors.white10, height: 1),
                const SizedBox(height: 16),

                // ═══════════════════════════════════════════════════
                // SECTION 3 — Offline Playlists
                // ═══════════════════════════════════════════════════
                FutureBuilder<int>(
                  future: OfflineStorage.getTotalDownloadSize(),
                  builder: (context, snapshot) {
                    final sizeStr = snapshot.connectionState == ConnectionState.waiting
                        ? ""
                        : OfflineStorage.formatBytes(snapshot.data ?? 0);
                    final count = offlinePlaylists.length;
                    return _SectionHeader(
                      icon: Icons.offline_pin_rounded,
                      label: "Offline Playlists",
                      color: const Color(0xFF10B981),
                      subtitle: count > 0
                          ? "$count playlist${count == 1 ? '' : 's'} · $sizeStr"
                          : "Download songs for offline playback",
                      trailing: IconButton(
                        icon: const Icon(Icons.add_circle_rounded, color: Color(0xFF10B981), size: 22),
                        onPressed: () async {
                          final created = await Navigator.of(context).push<bool>(
                            MaterialPageRoute(builder: (_) => const CreateOfflinePlaylistScreen()),
                          );
                          if (created == true && mounted) setState(() {});
                        },
                        tooltip: "Create Offline Playlist",
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 4),
                if (offlinePlaylists.isNotEmpty)
                  ...offlinePlaylists.map<Widget>((pl) {
                    final songs = List<Map<String, dynamic>>.from(pl["songs"] ?? []);
                    final allCompleted = songs.isNotEmpty && songs.every((s) => s['status'] == 'completed');
                    final anyDownloading = songs.any((s) => s['status'] == 'downloading');

                    String sub = "${songs.length} songs";
                    if (anyDownloading) sub += " · downloading...";
                    else if (allCompleted) sub += " · fully downloaded";

                    return _PlaylistCard(
                      icon: Icons.offline_pin_rounded,
                      iconColor: const Color(0xFF10B981),
                      name: pl["name"] ?? "Unnamed",
                      subtitle: sub,
                      onTap: () async {
                        if (Platform.isWindows) {
                          setState(() => _selectedOfflinePlaylistWindows = pl);
                        } else {
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => OfflinePlaylistScreen(
                                playlist: pl,
                                key: ValueKey(pl['id']),
                              ),
                            ),
                          );
                          if (mounted) setState(() {});
                        }
                      },
                      trailing: allCompleted
                          ? const Icon(Icons.check_circle, color: Color(0xFF10B981), size: 18)
                          : (anyDownloading
                              ? const SizedBox(
                                  width: 16, height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF10B981)),
                                )
                              : PopupMenuButton<String>(
                                  icon: const Icon(Icons.more_horiz_rounded, color: Colors.white38, size: 20),
                                  color: const Color(0xFF1C1A25),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  onSelected: (value) async {
                                    if (value == 'delete') {
                                      await _deletePlaylist(pl['id'], pl['name'] ?? '');
                                    }
                                  },
                                  itemBuilder: (_) => [
                                    const PopupMenuItem(value: 'delete', child: ListTile(
                                      leading: Icon(Icons.delete_rounded, color: Colors.redAccent, size: 20),
                                      title: Text('Delete', style: TextStyle(color: Colors.redAccent, fontSize: 14)),
                                      dense: true, contentPadding: EdgeInsets.zero,
                                    )),
                                  ],
                                )),
                    );
                  })
                else
                  _emptyHint("Tap + to create your first offline playlist"),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _createPersonalPlaylist() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF111019),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text("Create Personal Playlist", style: TextStyle(color: Colors.white)),
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
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text("Cancel", style: TextStyle(color: Colors.white54))),
          TextButton(onPressed: () => Navigator.of(ctx).pop(controller.text.trim()), child: const Text("Create", style: TextStyle(color: Color(0xFF8B5CF6)))),
        ],
      ),
    );

    if (name != null && name.isNotEmpty) {
      await OfflineStorage().createPlaylist(name, type: 'personal');
      if (mounted) setState(() {});
    }
  }

  Future<void> _renamePlaylist(int id, String currentName) async {
    final controller = TextEditingController(text: currentName);
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
            hintText: "New name",
            hintStyle: TextStyle(color: Colors.white30),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF8B5CF6))),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text("Cancel", style: TextStyle(color: Colors.white54))),
          TextButton(onPressed: () => Navigator.of(ctx).pop(controller.text.trim()), child: const Text("Rename", style: TextStyle(color: Color(0xFF8B5CF6)))),
        ],
      ),
    );
    if (newName != null && newName.isNotEmpty) {
      await OfflineStorage().renamePlaylist(id, newName);
      if (mounted) setState(() {});
    }
  }

  Future<void> _deletePlaylist(int id, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF111019),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text("Delete Playlist", style: TextStyle(color: Colors.white)),
        content: Text('Are you sure you want to delete "$name"?', style: const TextStyle(color: Colors.white60)),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text("Cancel", style: TextStyle(color: Colors.white54))),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text("Delete", style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
    if (confirm == true) {
      await OfflineStorage().deletePlaylist(id);
      if (mounted) setState(() {});
    }
  }

  Widget _emptyHint(String message) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Text(message, style: const TextStyle(color: Colors.white24, fontSize: 13)),
    );
  }

  Widget _buildSettingsTab() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Settings", style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 24),

          // Storage Management Card
          FutureBuilder<Map<String, int>>(
            future: () async {
              final dlSize = await OfflineStorage.getTotalDownloadSize();
              final cacheSize = await OfflineStorage.getCacheSize();
              return {'downloads': dlSize, 'cache': cacheSize};
            }(),
            builder: (context, snapshot) {
              final sizes = snapshot.data ?? {'downloads': 0, 'cache': 0};
              final dlSizeFormatted = OfflineStorage.formatBytes(sizes['downloads'] ?? 0);
              final cacheSizeFormatted = OfflineStorage.formatBytes(sizes['cache'] ?? 0);
              return Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF111019),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withOpacity(0.06)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF8B5CF6).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.storage_rounded,
                              color: Color(0xFF8B5CF6), size: 24),
                        ),
                        const SizedBox(width: 16),
                        const Text(
                          "Storage Management",
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("JustAudio Cache Size", style: TextStyle(color: Colors.white70, fontSize: 13)),
                        Text(
                          snapshot.connectionState == ConnectionState.waiting
                              ? "Calculating..."
                              : cacheSizeFormatted,
                          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("Downloaded Offline Songs", style: TextStyle(color: Colors.white70, fontSize: 13)),
                        Text(
                          snapshot.connectionState == ConnectionState.waiting
                              ? "Calculating..."
                              : dlSizeFormatted,
                          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              await OfflineStorage.clearCache();
                              setState(() {});
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white.withOpacity(0.05),
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              side: BorderSide(color: Colors.white.withOpacity(0.1)),
                            ),
                            icon: const Icon(Icons.cleaning_services_rounded, size: 16),
                            label: const Text("Clear Cache", style: TextStyle(fontSize: 12)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              await OfflineStorage().clearAllDownloads();
                              setState(() {});
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.redAccent.withOpacity(0.1),
                              foregroundColor: Colors.redAccent,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              side: BorderSide(color: Colors.redAccent.withOpacity(0.2)),
                            ),
                            icon: const Icon(Icons.delete_sweep_rounded, size: 16),
                            label: const Text("Clear Downloads", style: TextStyle(fontSize: 12)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              backgroundColor: const Color(0xFF111019),
                              title: const Text("Clear All Data", style: TextStyle(color: Colors.white)),
                              content: const Text(
                                "This will permanently delete all downloaded songs, offline playlists, and cached files. Are you sure you want to proceed?",
                                style: TextStyle(color: Colors.white70),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.of(context).pop(false),
                                  child: const Text("Cancel", style: TextStyle(color: Colors.white60)),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.of(context).pop(true),
                                  style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
                                  child: const Text("Clear All"),
                                ),
                              ],
                            ),
                          );
                          if (confirm == true) {
                            await OfflineStorage().clearAllData();
                            setState(() {});
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent.withOpacity(0.1),
                          foregroundColor: Colors.redAccent,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          side: BorderSide(color: Colors.redAccent.withOpacity(0.2)),
                        ),
                        icon: const Icon(Icons.delete_forever_rounded, size: 16),
                        label: const Text("Clear All Data", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),

          // Sync with Google Drive Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF111019),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withOpacity(0.06)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Sync Library",
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  "Synchronize your music files and folder playlists directly from your connected Google Drive storage.",
                  style: TextStyle(color: Colors.white60, fontSize: 13),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isSyncingLocal ? null : () async {
                      setState(() {
                        _isSyncingLocal = true;
                      });
                      try {
                        await ApiService().triggerSync();
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text("Sync process triggered..."),
                            backgroundColor: Color(0xFF8B5CF6),
                          ),
                        );
                        // Poll sync status until done
                        _pollSyncStatus();
                      } catch (e) {
                        if (mounted) {
                          setState(() {
                            _isSyncingLocal = false;
                          });
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text("Sync failed: $e")),
                          );
                        }
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF8B5CF6),
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: const Color(0xFF8B5CF6).withOpacity(0.3),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: _isSyncingLocal 
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.sync_rounded),
                    label: Text(_isSyncingLocal ? "Syncing..." : "Sync with Google Drive"),
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Log Out Button
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF111019),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withOpacity(0.06)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Logout",
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  "Disconnect from the current Sondra private server.",
                  style: TextStyle(color: Colors.white60, fontSize: 13),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      await ApiService().logout();
                      if (mounted) {
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute(builder: (_) => const SetupScreen()),
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent.withOpacity(0.1),
                      foregroundColor: Colors.redAccent,
                      elevation: 0,
                      side: BorderSide(color: Colors.redAccent.withOpacity(0.2)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.logout_rounded),
                    label: const Text("Log Out"),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}

// ──────────────────────────────────────────────────────────────────
// Shared section header widget used in the Playlists tab
// ──────────────────────────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final String? subtitle;
  final Widget? trailing;

  const _SectionHeader({
    required this.icon,
    required this.label,
    required this.color,
    this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 0.3)),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Text(subtitle!, style: const TextStyle(color: Colors.white38, fontSize: 11)),
                  ),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────
// Shared playlist card widget used in the Playlists tab
// ──────────────────────────────────────────────────────────────────
class _PlaylistCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String name;
  final String subtitle;
  final VoidCallback onTap;
  final Widget? trailing;

  const _PlaylistCard({
    required this.icon,
    required this.iconColor,
    required this.name,
    required this.subtitle,
    required this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: iconColor.withOpacity(0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: iconColor, size: 22),
        ),
        title: Text(name,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
        subtitle: Text(subtitle,
            style: const TextStyle(color: Colors.white38, fontSize: 12)),
        trailing: trailing,
        onTap: onTap,
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────
// Playlist detail screen – proper ConsumerWidget so the global
// mini-player overlay works and the list has correct bottom padding.
// ──────────────────────────────────────────────────────────────────
class _PlaylistDetailScreen extends ConsumerWidget {
  final String name;
  final List<Map<String, dynamic>> songs;

  const _PlaylistDetailScreen({required this.name, required this.songs});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playerState = ref.watch(playerProvider);
    final bottomPad = playerState.currentSong != null ? (Platform.isWindows ? 90.0 : 76.0) : 0.0;

    return Scaffold(
      backgroundColor: const Color(0xFF08070D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111019),
        foregroundColor: Colors.white,
        title: Text(name, style: const TextStyle(color: Colors.white)),
        elevation: 0,
      ),
      body: ListView.builder(
        padding: EdgeInsets.only(left: 8, right: 8, top: 8, bottom: bottomPad + 8),
        itemCount: songs.length,
        itemBuilder: (ctx, idx) {
          final s = songs[idx];
          final isCurrent = playerState.currentSong?["id"] == s["id"];
          return GestureDetector(
            onSecondaryTapDown: (details) {
              if (Platform.isWindows) {
                SongOptionsButton.showRightClickMenu(context, details.globalPosition, ref, s);
              }
            },
            child: ListTile(
              onTap: () => ref.read(playerProvider.notifier).playSong(s, songs, playlistName: name),
              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              leading: SongCoverWidget(
                song: s,
                width: 48,
                height: 48,
                borderRadius: 6.0,
              ),
              title: Text(
                s["title"] ?? "Unknown Track",
                style: TextStyle(
                  color: isCurrent ? const Color(0xFF8B5CF6) : Colors.white,
                  fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                ),
              ),
              subtitle: Text(
                s["artist"] ?? "Unknown Artist",
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isCurrent && playerState.isPlaying)
                    const Icon(Icons.equalizer_rounded, color: Color(0xFF8B5CF6), size: 20)
                  else
                    Text(
                      "${(s["duration_seconds"] ?? 0) ~/ 60}:${((s["duration_seconds"] ?? 0) % 60).toString().padLeft(2, '0')}",
                      style: const TextStyle(color: Colors.white30, fontSize: 11),
                    ),
                  const SizedBox(width: 4),
                  SongOptionsButton(song: s),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────
// Inline Windows playlist details screen keeping BottomNavigationBar visible.
// ──────────────────────────────────────────────────────────────────
class _PlaylistDetailScreenInline extends ConsumerWidget {
  final String name;
  final List<Map<String, dynamic>> songs;
  final VoidCallback onBack;

  const _PlaylistDetailScreenInline({
    required this.name,
    required this.songs,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playerState = ref.watch(playerProvider);
    final bottomPad = playerState.currentSong != null ? 90.0 : 0.0;

    return Scaffold(
      backgroundColor: const Color(0xFF08070D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111019),
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: onBack,
        ),
        title: Text(name, style: const TextStyle(color: Colors.white)),
        elevation: 0,
      ),
      body: ListView.builder(
        padding: EdgeInsets.only(left: 8, right: 8, top: 8, bottom: bottomPad + 8),
        itemCount: songs.length,
        itemBuilder: (ctx, idx) {
          final s = songs[idx];
          final isCurrent = playerState.currentSong?["id"] == s["id"];
          return GestureDetector(
            onSecondaryTapDown: (details) {
              if (Platform.isWindows) {
                SongOptionsButton.showRightClickMenu(context, details.globalPosition, ref, s);
              }
            },
            child: ListTile(
              onTap: () => ref.read(playerProvider.notifier).playSong(s, songs, playlistName: name),
              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              leading: SongCoverWidget(
                song: s,
                width: 48,
                height: 48,
                borderRadius: 6.0,
              ),
              title: Text(
                s["title"] ?? "Unknown Track",
                style: TextStyle(
                  color: isCurrent ? const Color(0xFF8B5CF6) : Colors.white,
                  fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                ),
              ),
              subtitle: Text(
                s["artist"] ?? "Unknown Artist",
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isCurrent && playerState.isPlaying)
                    const Icon(Icons.equalizer_rounded, color: Color(0xFF8B5CF6), size: 20)
                  else
                    Text(
                      "${(s["duration_seconds"] ?? 0) ~/ 60}:${((s["duration_seconds"] ?? 0) % 60).toString().padLeft(2, '0')}",
                      style: const TextStyle(color: Colors.white30, fontSize: 11),
                    ),
                  const SizedBox(width: 4),
                  SongOptionsButton(song: s),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}


