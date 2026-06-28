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

    // Android reserves bottom space for the global stacked mini-player overlay
    final bottomPad = !Platform.isWindows && hasSong ? 76.0 : 0.0;

    return Scaffold(
      backgroundColor: const Color(0xFF08070D),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(bottom: bottomPad),
                child: Platform.isWindows
                    ? _buildDesktopLayout(showNowPlayingWindows)
                    : IndexedStack(
                        index: _currentIndex,
                        children: [
                          _buildHomeTab(),
                          _buildLibraryTab(),
                          _buildPlaylistsTab(),
                          _buildSearchTab(),
                          _buildSettingsTab(),
                        ],
                      ),
              ),
            ),
            // Windows mini-player always visible at bottom (even with right panel open)
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
                BottomNavigationBarItem(icon: Icon(Icons.search_rounded), label: "Search"),
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
              _buildSearchTab(),
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
      width: 200,
      color: const Color(0xFF111019),
      child: Column(
        children: [
          const SizedBox(height: 24),
          Row(
            children: [
              const SizedBox(width: 16),
              const Icon(Icons.music_note_rounded, color: Color(0xFF8B5CF6), size: 28),
              const SizedBox(width: 10),
              const Text("Sondra", style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 32),
          _sidebarItem(Icons.home_rounded, "Home", 0),
          _sidebarItem(Icons.music_note_rounded, "Library", 1),
          _sidebarItem(Icons.list_rounded, "Playlists", 2),
          _sidebarItem(Icons.search_rounded, "Search", 3),
          const Spacer(),
          _sidebarItem(Icons.settings_rounded, "Settings", 4),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            child: TextButton.icon(
              onPressed: () async {
                await ApiService().logout();
                if (mounted) {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => const SetupScreen()),
                  );
                }
              },
              icon: const Icon(Icons.logout_rounded, color: Colors.white38, size: 18),
              label: const Text("Log Out", style: TextStyle(color: Colors.white38, fontSize: 13)),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _sidebarItem(IconData icon, String label, int index) {
    final selected = _currentIndex == index;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: selected ? const Color(0xFF8B5CF6).withOpacity(0.15) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        dense: true,
        leading: Icon(icon, color: selected ? const Color(0xFF8B5CF6) : Colors.white60, size: 20),
        title: Text(label, style: TextStyle(color: selected ? Colors.white : Colors.white60, fontSize: 14, fontWeight: selected ? FontWeight.w600 : FontWeight.normal)),
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
          const Text("Welcome Back",
              style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          const Text("Recently Played",
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
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
                        onTap: () => ref.read(playerProvider.notifier).playSong(
                          s,
                          List<Map<String, dynamic>>.from(songs.map((e) => e["song"])),
                        ),
                        leading: SongCoverWidget(song: s, width: 44, height: 44, borderRadius: 6.0),
                        title: Text(s["title"] ?? "Unknown Track",
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                        subtitle: Text(s["artist"] ?? "Unknown Artist",
                            style: const TextStyle(color: Colors.white38, fontSize: 12)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
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
          Expanded(
            child: songsAsync.when(
              data: (songs) {
                final list = List<Map<String, dynamic>>.from(songs);
                return ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (context, index) {
                    final song = list[index];
                    final isCurrent = playerState.currentSong?["id"] == song["id"];
                    return GestureDetector(
                      onSecondaryTapDown: (details) {
                        if (Platform.isWindows) {
                          SongOptionsButton.showRightClickMenu(context, details.globalPosition, ref, song);
                        }
                      },
                      child: ListTile(
                        onTap: () => ref.read(playerProvider.notifier).playSong(song, list),
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
        onBack: () {
          setState(() {
            _selectedPlaylistWindows = null;
          });
        },
      );
    }
    // Windows: show inline detail for offline playlist
    if (Platform.isWindows && _selectedOfflinePlaylistWindows != null) {
      final pl = _selectedOfflinePlaylistWindows!;
      return OfflinePlaylistScreen(
        playlist: pl,
        onBack: () {
          setState(() {
            _selectedOfflinePlaylistWindows = null;
          });
        },
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
          // Header row with title and create button
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Playlists",
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold)),
              IconButton(
                onPressed: _showCreatePlaylistDialog,
                icon: const Icon(Icons.add_rounded, color: Color(0xFF8B5CF6)),
                tooltip: "Create Playlist",
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView(
              children: [
                // ── Online Playlists Section ──
                if (playlistsAsync is AsyncData && playlistsAsync.value!.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        const Icon(Icons.cloud_outlined,
                            color: Colors.white54, size: 16),
                        const SizedBox(width: 6),
                        const Text("Online Playlists",
                            style: TextStyle(
                                color: Colors.white54,
                                fontSize: 13,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                  ...playlistsAsync.when(
                    data: (lists) => lists.map<Widget>((pl) {
                      final pSongs =
                          List<Map<String, dynamic>>.from(pl["songs"] ?? []);
                      return ListTile(
                        onTap: () {
                          if (Platform.isWindows) {
                            setState(() {
                              _selectedPlaylistWindows = pl;
                            });
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
                        leading: const Icon(Icons.playlist_play_rounded,
                            color: Color(0xFF8B5CF6), size: 36),
                        title: Text(pl["name"] ?? "Unnamed",
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600)),
                        subtitle: Text("${pl["song_count"] ?? 0} Songs",
                            style:
                                const TextStyle(color: Colors.white38, fontSize: 12)),
                      );
                    }),
                    loading: () => [const Center(child: CircularProgressIndicator(color: Color(0xFF8B5CF6)))],
                    error: (e, s) => [
                      Text("Error: $e",
                          style: const TextStyle(color: Colors.redAccent))
                    ],
                  ),
                  const Divider(color: Colors.white10, height: 24),
                ],
                // ── Personal Playlists Section ──
                if (personalPlaylists.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        const Icon(Icons.playlist_play_rounded,
                            color: Color(0xFF8B5CF6), size: 18),
                        const SizedBox(width: 6),
                        const Text("Personal Playlists",
                            style: TextStyle(
                                color: Color(0xFF8B5CF6),
                                fontSize: 13,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                  ...personalPlaylists.map<Widget>((pl) {
                    final songs =
                        List<Map<String, dynamic>>.from(pl["songs"] ?? []);
                    return ListTile(
                      onTap: () async {
                        if (Platform.isWindows) {
                          setState(() {
                            _selectedOfflinePlaylistWindows = pl;
                          });
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
                      leading: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF8B5CF6).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.playlist_play_rounded,
                            color: Color(0xFF8B5CF6), size: 24),
                      ),
                      title: Text(pl["name"] ?? "Unnamed",
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600)),
                      subtitle: Text("${songs.length} Songs",
                          style: const TextStyle(
                              color: Colors.white38, fontSize: 12)),
                    );
                  }),
                  const Divider(color: Colors.white10, height: 24),
                ],
                // ── Offline Playlists Section ──
                if (offlinePlaylists.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        const Icon(Icons.offline_pin_rounded,
                            color: Color(0xFF8B5CF6), size: 16),
                        const SizedBox(width: 6),
                        const Text("Offline Playlists",
                            style: TextStyle(
                                color: Color(0xFF8B5CF6),
                                fontSize: 13,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                  ...offlinePlaylists.map<Widget>((pl) {
                    final songs =
                        List<Map<String, dynamic>>.from(pl["songs"] ?? []);
                    return ListTile(
                      onTap: () async {
                        if (Platform.isWindows) {
                          setState(() {
                            _selectedOfflinePlaylistWindows = pl;
                          });
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
                      leading: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF8B5CF6).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.offline_pin_rounded,
                            color: Color(0xFF8B5CF6), size: 24),
                      ),
                      title: Text(pl["name"] ?? "Unnamed",
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600)),
                      subtitle: Row(
                        children: [
                          Text("${songs.length} Songs",
                              style: const TextStyle(
                                  color: Colors.white38, fontSize: 12)),
                          if (songs.any(
                              (s) => s['status'] == 'downloading')) ...[
                            const SizedBox(width: 8),
                            const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(
                                  strokeWidth: 1.5,
                                  color: Color(0xFF8B5CF6)),
                            ),
                          ],
                          if (songs.every(
                              (s) => s['status'] == 'completed')) ...[
                            const SizedBox(width: 8),
                            const Icon(Icons.check_circle,
                                size: 12, color: Color(0xFF10B981)),
                          ],
                        ],
                      ),
                    );
                  }),
                ],
                // ── Empty state ──
                if ((playlistsAsync is AsyncData &&
                        playlistsAsync.value!.isEmpty) &&
                    allLocalPlaylists.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 40),
                    child: Center(
                      child: Column(
                        children: [
                          Icon(Icons.playlist_add_rounded,
                              color: Colors.white24, size: 48),
                          SizedBox(height: 12),
                          Text("No playlists yet",
                              style: TextStyle(color: Colors.white38)),
                          SizedBox(height: 4),
                          Text("Tap + to create one",
                              style: TextStyle(
                                  color: Colors.white24, fontSize: 13)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showCreatePlaylistDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF111019),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text("Create New Playlist",
            style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              onTap: () {
                Navigator.of(ctx).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("Online playlists are synced from Google Drive"),
                    backgroundColor: Color(0xFF8B5CF6),
                  ),
                );
              },
              leading: const Icon(Icons.cloud_outlined,
                  color: Color(0xFF8B5CF6), size: 28),
              title: const Text("Online Playlist",
                  style: TextStyle(color: Colors.white)),
              subtitle: const Text("Synced with backend, streams from Google Drive",
                  style: TextStyle(color: Colors.white54, fontSize: 12)),
              contentPadding: EdgeInsets.zero,
            ),
            const Divider(color: Colors.white10),
            ListTile(
              onTap: () async {
                Navigator.of(ctx).pop();
                _createPersonalPlaylist();
              },
              leading: const Icon(Icons.playlist_play_rounded,
                  color: Color(0xFF8B5CF6), size: 28),
              title: const Text("Personal Playlist",
                  style: TextStyle(color: Colors.white)),
              subtitle: const Text("Local stream playlist, streams online songs",
                  style: TextStyle(color: Colors.white54, fontSize: 12)),
              contentPadding: EdgeInsets.zero,
            ),
            const Divider(color: Colors.white10),
            ListTile(
              onTap: () async {
                Navigator.of(ctx).pop();
                final created = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => const CreateOfflinePlaylistScreen(),
                  ),
                );
                if (created == true && mounted) {
                  setState(() {});
                }
              },
              leading: const Icon(Icons.offline_pin_rounded,
                  color: Color(0xFF8B5CF6), size: 28),
              title: const Text("Offline Playlist",
                  style: TextStyle(color: Colors.white)),
              subtitle: const Text("Stored locally, download songs for offline playback",
                  style: TextStyle(color: Colors.white54, fontSize: 12)),
              contentPadding: EdgeInsets.zero,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text("Cancel",
                style: TextStyle(color: Colors.white54)),
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
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Color(0xFF8B5CF6)),
            ),
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
            child: const Text("Create", style: TextStyle(color: Color(0xFF8B5CF6))),
          ),
        ],
      ),
    );

    if (name != null && name.isNotEmpty) {
      await OfflineStorage().createPlaylist(name, type: 'personal');
      if (mounted) {
        setState(() {});
      }
    }
  }

  Widget _buildSearchTab() {
    final playerState = ref.watch(playerProvider);
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Search", style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          TextField(
            controller: _searchController,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: "Search by title, artist, album...",
              hintStyle: const TextStyle(color: Colors.white24),
              prefixIcon: const Icon(Icons.search_rounded, color: Colors.white38),
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
              setState(() {
                _searchQuery = val;
              });
            },
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _searchQuery.isEmpty
                ? const Center(child: Text("Type to search", style: TextStyle(color: Colors.white38)))
                : FutureBuilder<List<dynamic>>(
                    future: ApiService().getSongsSearch(_searchQuery),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator(color: Color(0xFF8B5CF6)));
                      }
                      if (snapshot.hasError) {
                        return Center(child: Text("Error: ${snapshot.error}", style: const TextStyle(color: Colors.redAccent)));
                      }
                      final songs = List<Map<String, dynamic>>.from(snapshot.data ?? []);
                      if (songs.isEmpty) {
                        return const Center(child: Text("No tracks found", style: TextStyle(color: Colors.white38)));
                      }
                      return ListView.builder(
                        itemCount: songs.length,
                        itemBuilder: (context, index) {
                          final song = songs[index];
                          final isCurrent = playerState.currentSong?["id"] == song["id"];
                          return GestureDetector(
                            onSecondaryTapDown: (details) {
                              if (Platform.isWindows) {
                                SongOptionsButton.showRightClickMenu(context, details.globalPosition, ref, song);
                              }
                            },
                            child: ListTile(
                              onTap: () => ref.read(playerProvider.notifier).playSong(song, songs),
                              leading: SongCoverWidget(
                                song: song,
                                width: 40,
                                height: 40,
                                borderRadius: 4.0,
                              ),
                              title: Text(
                                song["title"] ?? "Unknown Track", 
                                style: TextStyle(
                                  color: isCurrent ? const Color(0xFF8B5CF6) : Colors.white,
                                  fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
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
                  ),
          ),
        ],
      ),
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

          // Offline Storage Card
          FutureBuilder<int>(
            future: OfflineStorage.getTotalDownloadSize(),
            builder: (context, snapshot) {
              final sizeBytes = snapshot.data ?? 0;
              return Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF111019),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withOpacity(0.06)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF8B5CF6).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.offline_pin_rounded,
                          color: Color(0xFF8B5CF6), size: 24),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Offline Storage",
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            snapshot.connectionState == ConnectionState.waiting
                                ? "Calculating..."
                                : "${OfflineStorage().getPlaylists().length} offline playlists using ${OfflineStorage.formatBytes(sizeBytes)}",
                            style: const TextStyle(
                                color: Colors.white60, fontSize: 13),
                          ),
                        ],
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
              onTap: () => ref.read(playerProvider.notifier).playSong(s, songs),
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
              onTap: () => ref.read(playerProvider.notifier).playSong(s, songs),
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


