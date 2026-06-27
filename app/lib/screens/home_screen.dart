import 'package:flutter/material';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/api_service.dart';
import '../providers/player_provider.dart';
import '../widgets/mini_player.dart';
import 'now_playing_screen.dart';

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

  @override
  void initState() {
    super.initState();
    // Listen to SSE Events
    ApiService().sseController.stream.listen((event) {
      if (event["type"] == "library_updated") {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Library updated"),
              backgroundColor: Color(0xFF7C3AED),
            ),
          );
          // Invalidate Riverpod providers to trigger silent reload
          ref.invalidate(songsProvider);
          ref.invalidate(playlistsProvider);
          ref.invalidate(historyRecentProvider);
          ref.invalidate(historyContinueProvider);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final playerState = ref.watch(playerProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0F0E17),
      body: Stack(
        children: [
          SafeArea(
            child: Padding(
              padding: EdgeInsets.only(bottom: playerState.currentSong != null ? 72.0 : 0.0),
              child: IndexedStack(
                index: _currentIndex,
                children: [
                  _buildHomeTab(),
                  _buildLibraryTab(),
                  _buildPlaylistsTab(),
                  _buildSearchTab(),
                ],
              ),
            ),
          ),
          
          // Floating Mini Player
          if (playerState.currentSong != null)
            Positioned(
              left: 8,
              right: 8,
              bottom: 8 + 56.0 + 8, // Just above bottom navigation bar height (approx 56) + padding
              child: MiniPlayer(
                onTap: () {
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (_) => const NowPlayingScreen(),
                  );
                },
              ),
            ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (idx) {
          setState(() {
            _currentIndex = idx;
          });
        },
        backgroundColor: const Color(0xFF15141F),
        selectedItemColor: const Color(0xFF7C3AED),
        unselectedItemColor: Colors.white60,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_rounded), label: "Home"),
          BottomNavigationBarItem(icon: Icon(Icons.music_note_rounded), label: "Library"),
          BottomNavigationBarItem(icon: Icon(Icons.list_rounded), label: "Playlists"),
          BottomNavigationBarItem(icon: Icon(Icons.search_rounded), label: "Search"),
        ],
      ),
    );
  }

  // --- TAB BUILDERS ---

  Widget _buildHomeTab() {
    final continueAsync = ref.watch(historyContinueProvider);
    final recentAsync = ref.watch(historyRecentProvider);
    final playlistsAsync = ref.watch(playlistsProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Welcome Back",
            style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),

          // Continue Listening Row
          continueAsync.when(
            data: (songs) {
              if (songs.isEmpty) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Continue Listening", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 120,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: songs.length,
                      itemBuilder: (context, index) {
                        final entry = songs[index];
                        final song = entry["song"];
                        if (song == null) return const SizedBox.shrink();
                        return GestureDetector(
                          onTap: () => ref.read(playerProvider.notifier).playSong(
                            Map<String, dynamic>.from(song),
                            List<Map<String, dynamic>>.from(songs.map((e) => e["song"])),
                            startSeconds: entry["position_seconds"],
                          ),
                          child: Container(
                            width: 100,
                            margin: const EdgeInsets.only(right: 16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: CachedNetworkImage(
                                    imageUrl: "${ApiService().baseUrl}/api/songs/${song["id"]}/cover",
                                    height: 80,
                                    width: 100,
                                    fit: BoxFit.cover,
                                    errorWidget: (c, e, s) => Container(color: Colors.white10, child: const Icon(Icons.music_note)),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  song["title"] ?? "Unknown Track",
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (e, s) => const SizedBox.shrink(),
          ),

          // Recently Played Row
          recentAsync.when(
            data: (songs) {
              if (songs.isEmpty) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Recently Played", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 120,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: songs.length,
                      itemBuilder: (context, index) {
                        final entry = songs[index];
                        final song = entry["song"];
                        if (song == null) return const SizedBox.shrink();
                        return GestureDetector(
                          onTap: () => ref.read(playerProvider.notifier).playSong(
                            Map<String, dynamic>.from(song),
                            List<Map<String, dynamic>>.from(songs.map((e) => e["song"])),
                          ),
                          child: Container(
                            width: 100,
                            margin: const EdgeInsets.only(right: 16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: CachedNetworkImage(
                                    imageUrl: "${ApiService().baseUrl}/api/songs/${song["id"]}/cover",
                                    height: 80,
                                    width: 100,
                                    fit: BoxFit.cover,
                                    errorWidget: (c, e, s) => Container(color: Colors.white10, child: const Icon(Icons.music_note)),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  song["title"] ?? "Unknown Track",
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (e, s) => const SizedBox.shrink(),
          ),

          // Playlists Grid
          playlistsAsync.when(
            data: (lists) {
              if (lists.isEmpty) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Playlists", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                      childAspectRatio: 1.4,
                    ),
                    itemCount: lists.length,
                    itemBuilder: (context, index) {
                      final playlist = lists[index];
                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            _currentIndex = 2; // Jump to playlists tab
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.04),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white.withOpacity(0.06)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Icon(Icons.folder_rounded, color: Color(0xFF7C3AED), size: 28),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    playlist["name"] ?? "Unnamed",
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    "${playlist["song_count"] ?? 0} Songs",
                                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ],
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, s) => Text("Error: $e", style: const TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  Widget _buildLibraryTab() {
    final songsAsync = ref.watch(songsProvider);
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
                    return ListTile(
                      onTap: () => ref.read(playerProvider.notifier).playSong(song, list),
                      contentPadding: const EdgeInsets.symmetric(vertical: 4),
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: CachedNetworkImage(
                          imageUrl: "${ApiService().baseUrl}/api/songs/${song["id"]}/cover",
                          width: 48,
                          height: 48,
                          fit: BoxFit.cover,
                          errorWidget: (c, e, s) => Container(color: Colors.white10, child: const Icon(Icons.music_note, color: Colors.white24)),
                        ),
                      ),
                      title: Text(song["title"] ?? "Unknown Track", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                      subtitle: Text(song["artist"] ?? "Unknown Artist", style: const TextStyle(color: Colors.white38, fontSize: 12)),
                      trailing: Text(
                        "${(song["duration_seconds"] ~/ 60).toString().padLeft(2, '0')}:${(song["duration_seconds"] % 60).toString().padLeft(2, '0')}",
                        style: const TextStyle(color: Colors.white30, fontSize: 11),
                      ),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, s) => Center(child: Text("Error: $e", style: const TextStyle(color: Colors.redAccent))),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaylistsTab() {
    final playlistsAsync = ref.watch(playlistsProvider);
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Playlists", style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          Expanded(
            child: playlistsAsync.when(
              data: (lists) {
                return ListView.builder(
                  itemCount: lists.length,
                  itemBuilder: (context, index) {
                    final pl = lists[index];
                    final pSongs = List<Map<String, dynamic>>.from(pl["songs"] ?? []);
                    return ListTile(
                      onTap: () {
                        // Display Songs inside this playlist
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => Scaffold(
                              backgroundColor: const Color(0xFF0F0E17),
                              appBar: AppBar(
                                backgroundColor: const Color(0xFF15141F),
                                title: Text(pl["name"] ?? "Playlist"),
                              ),
                              body: ListView.builder(
                                padding: const EdgeInsets.all(16),
                                itemCount: pSongs.length,
                                itemBuilder: (c, idx) {
                                  final s = pSongs[idx];
                                  return ListTile(
                                    onTap: () => ref.read(playerProvider.notifier).playSong(s, pSongs),
                                    title: Text(s["title"] ?? "Unknown Track", style: const TextStyle(color: Colors.white)),
                                    subtitle: Text(s["artist"] ?? "Unknown Artist", style: const TextStyle(color: Colors.white38)),
                                  );
                                },
                              ),
                            ),
                          ),
                        );
                      },
                      leading: const Icon(Icons.playlist_play_rounded, color: Color(0xFF7C3AED), size: 36),
                      title: Text(pl["name"] ?? "Unnamed", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                      subtitle: Text("${pl["song_count"] ?? 0} Songs", style: const TextStyle(color: Colors.white38, fontSize: 12)),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, s) => Center(child: Text("Error: $e", style: const TextStyle(color: Colors.redAccent))),
            ),
          ),
        ],
      ),
    );
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
                borderSide: const BorderSide(color: Color(0xFF7C3AED)),
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
                        return const Center(child: CircularProgressIndicator());
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
                          return ListTile(
                            onTap: () => ref.read(playerProvider.notifier).playSong(song, songs),
                            title: Text(song["title"] ?? "Unknown Track", style: const TextStyle(color: Colors.white)),
                            subtitle: Text(song["artist"] ?? "Unknown Artist", style: const TextStyle(color: Colors.white38)),
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

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}
