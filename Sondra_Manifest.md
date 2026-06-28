# Sondra Music Codebase Status & Achievements

Sondra Music is a premium cross-platform music streaming player built with Flutter (for Windows and Android apps) and React/TypeScript/Vite (for the Admin panel). It integrates with a custom Python/FastAPI backend to stream music files directly from Google Drive via secure authentication proxies.

---

## Achievements & Key Features Implemented

1. **Instant Spotify-like Playback:** Tapping any song stops current playback immediately and starts the new song instantly without showing a paused state. Returning to a previously played song restarts it from the beginning unless seeked manually.
2. **Interactive Play Queue:** Supports manual "Add to Queue" priority placement. Queue screen features reorderable drag-and-drop tracks and swipe-to-delete gestures. Falls back smoothly to the active playlist once the queue is exhausted.
3. **Offline Mode & Local Downloads:** Users can create offline playlists and download tracks directly to local device AppData storage (`getApplicationSupportDirectory`). Supports real-time download progress tracking, offline playback, and disk space usage management under settings.
4. **Platform Integrations & Keyboard Controls:** 
   - **Windows SMTC:** Full System Media Transport Controls integration (locks media keys, displays title/artist/album on screen, and allows background controls when minimized).
   - **Hotkeys:** Space/P toggles playback, Left/Right arrows seek 10s, and Media buttons work natively.
   - **Android Foreground Service:** Integrates `audio_service` to run background playback, manages a sticky notification drawer (Spotify-like styling with media controls), and handles Bluetooth earbud commands (single-click play/pause, double-click skips, left earbud prev/restart).
5. **Admin Panel Queue:** The Vercel admin dashboard includes a collapsible sidebar showing the upcoming play queue.

---

## Directory Structure

```
PROJECT SONDRA/
├── admin/                     # React/Vite Admin Dashboard
│   ├── src/
│   │   ├── App.tsx            # Main UI, collapsible queue panel, song manager
│   │   └── api.ts             # Axios backend client interceptors
│   └── package.json
│
├── app/                       # Flutter Cross-Platform Client
│   ├── android/               # Android Platform Settings
│   │   ├── app/
│   │   │   ├── build.gradle.kts
│   │   │   └── src/main/AndroidManifest.xml
│   │   ├── gradle/wrapper/gradle-wrapper.properties
│   │   ├── settings.gradle.kts
│   │   └── gradle.properties
│   │
│   ├── lib/                   # Flutter Application Source
│   │   ├── main.dart          # Entry point & global focus/hotkeys
│   │   ├── providers/
│   │   │   └── player_provider.dart
│   │   ├── screens/
│   │   │   ├── create_offline_playlist_screen.dart
│   │   │   ├── home_screen.dart
│   │   │   ├── now_playing_screen.dart
│   │   │   ├── offline_playlist_screen.dart
│   │   │   └── queue_screen.dart
│   │   ├── services/
│   │   │   ├── api_service.dart
│   │   │   ├── audio_handler.dart
│   │   │   ├── download_manager.dart
│   │   │   └── offline_storage.dart
│   │   └── widgets/
│   │       ├── mini_player.dart
│   │       ├── song_cover.dart
│   │       └── song_options_menu.dart
│   └── pubspec.yaml
│
└── backend/                   # FastAPI Backend Server
    └── routers/
        └── stream.py          # Google Drive stream proxy & MIME-type resolver
```

---

## Complete Core Codebase Files

Here is the complete source code for the files we authored and modified during implementation:

### 1. `app/lib/providers/player_provider.dart`
[player_provider.dart](file:///e:/PROJECT%20SONDRA/sondra/app/lib/providers/player_provider.dart)
```dart
import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import '../services/api_service.dart';
import '../services/audio_handler.dart';

late SondraAudioHandler globalAudioHandler;

class PlayerState {
  final Map<String, dynamic>? currentSong;
  final bool isPlaying;
  final bool isBuffering;
  final Duration position;
  final Duration duration;
  final bool shuffle;
  final String repeat; // "none" | "one" | "all"
  final double volume;
  final List<Map<String, dynamic>> originalPlaylist;
  final List<Map<String, dynamic>> activePlaylist;
  final List<Map<String, dynamic>> queue;

  PlayerState({
    this.currentSong,
    this.isPlaying = false,
    this.isBuffering = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.shuffle = false,
    this.repeat = "none",
    this.volume = 0.8,
    this.originalPlaylist = const [],
    this.activePlaylist = const [],
    this.queue = const [],
  });

  PlayerState copyWith({
    Map<String, dynamic>? currentSong,
    bool? isPlaying,
    bool? isBuffering,
    Duration? position,
    Duration? duration,
    bool? shuffle,
    String? repeat,
    double? volume,
    List<Map<String, dynamic>>? originalPlaylist,
    List<Map<String, dynamic>>? activePlaylist,
    List<Map<String, dynamic>>? queue,
  }) {
    return PlayerState(
      currentSong: currentSong ?? this.currentSong,
      isPlaying: isPlaying ?? this.isPlaying,
      isBuffering: isBuffering ?? this.isBuffering,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      shuffle: shuffle ?? this.shuffle,
      repeat: repeat ?? this.repeat,
      volume: volume ?? this.volume,
      originalPlaylist: originalPlaylist ?? this.originalPlaylist,
      activePlaylist: activePlaylist ?? this.activePlaylist,
      queue: queue ?? this.queue,
    );
  }
}

class PlayerNotifier extends StateNotifier<PlayerState> {
  final ApiService _api = ApiService();
  Timer? _positionLogTimer;
  StreamSubscription? _posSub;
  StreamSubscription? _durSub;
  StreamSubscription? _stateSub;

  PlayerNotifier() : super(PlayerState()) {
    _posSub = globalAudioHandler.player.positionStream.listen((pos) {
      state = state.copyWith(position: pos);
    });

    _durSub = globalAudioHandler.player.durationStream.listen((dur) {
      if (dur != null) {
        state = state.copyWith(duration: dur);
      }
    });

    _stateSub = globalAudioHandler.player.playerStateStream.listen((pState) {
      state = state.copyWith(
        isPlaying: pState.playing,
        isBuffering: pState.processingState == ProcessingState.buffering ||
                     pState.processingState == ProcessingState.loading,
      );
      if (pState.processingState == ProcessingState.completed) {
        if (state.repeat == "one") {
          state = state.copyWith(position: Duration.zero);
          seek(Duration.zero);
          globalAudioHandler.play();
        } else {
          handleNext();
        }
      }
    });

    _positionLogTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (state.isPlaying && state.currentSong != null) {
        _api.logHistory(state.currentSong!["id"], state.position.inSeconds);
      }
    });

    globalAudioHandler.onSkipToNext = () async {
      handleNext();
    };
    globalAudioHandler.onSkipToPrevious = () async {
      handlePrev();
    };
  }

  Future<void> playSong(Map<String, dynamic> song, List<Map<String, dynamic>> playlist, {int? startSeconds}) async {
    await globalAudioHandler.player.stop();
    await globalAudioHandler.player.seek(Duration.zero);

    bool isNewQueue = false;
    if (state.originalPlaylist.length != playlist.length) {
      isNewQueue = true;
    } else {
      for (int i = 0; i < playlist.length; i++) {
        if (state.originalPlaylist[i]["id"] != playlist[i]["id"]) {
          isNewQueue = true;
          break;
        }
      }
    }

    List<Map<String, dynamic>> newOriginal = isNewQueue ? playlist : state.originalPlaylist;
    List<Map<String, dynamic>> newActive = isNewQueue ? List.from(playlist) : state.activePlaylist;

    if (isNewQueue && state.shuffle) {
      newActive.shuffle();
      newActive.removeWhere((s) => s["id"] == song["id"]);
      newActive.insert(0, song);
    }

    state = state.copyWith(
      currentSong: song,
      originalPlaylist: newOriginal,
      activePlaylist: newActive,
      position: startSeconds != null ? Duration(seconds: startSeconds) : Duration.zero,
      isBuffering: true,
    );

    try {
      String directUrl;
      final localPath = song["local_file_path"];
      if (localPath != null && await File(localPath).exists()) {
        directUrl = localPath;
      } else {
        directUrl = "${_api.baseUrl}/api/stream/${song["id"]}/proxy?token=${_api.token}";
      }

      final mediaItem = MediaItem(
        id: song["id"].toString(),
        album: song["album"] ?? "Unknown Album",
        title: song["title"] ?? "Unknown Title",
        artist: song["artist"] ?? "Unknown Artist",
        duration: Duration(seconds: song["duration_seconds"] ?? 0),
        artUri: Uri.parse("${_api.baseUrl}/api/songs/${song["id"]}/cover"),
      );

      await globalAudioHandler.playUri(directUrl, mediaItem);
      
      if (startSeconds != null) {
        await globalAudioHandler.seek(Duration(seconds: startSeconds));
      }
    } catch (e) {
      print("Error loading song in provider: $e");
    }
  }

  Future<void> togglePlay() async {
    if (state.currentSong == null) return;
    if (state.isPlaying) {
      await globalAudioHandler.pause();
    } else {
      await globalAudioHandler.play();
    }
  }

  Future<void> seek(Duration pos) async {
    await globalAudioHandler.seek(pos);
  }

  void toggleShuffle() {
    final nextShuffle = !state.shuffle;
    List<Map<String, dynamic>> newActive = List.from(state.originalPlaylist);
    
    if (nextShuffle) {
      newActive.shuffle();
      if (state.currentSong != null) {
        newActive.removeWhere((s) => s["id"] == state.currentSong!["id"]);
        newActive.insert(0, state.currentSong!);
      }
    }

    state = state.copyWith(
      shuffle: nextShuffle,
      activePlaylist: newActive,
    );
  }

  void cycleRepeat() {
    String nextRepeat = "none";
    if (state.repeat == "none") {
      nextRepeat = "all";
    } else if (state.repeat == "all") {
      nextRepeat = "one";
    }
    
    state = state.copyWith(repeat: nextRepeat);
    globalAudioHandler.player.setLoopMode(LoopMode.off);
  }

  void setVolume(double vol) {
    state = state.copyWith(volume: vol);
    globalAudioHandler.player.setVolume(vol);
  }

  void handleNext() {
    if (state.currentSong == null) return;

    if (state.queue.isNotEmpty) {
      final nextSong = state.queue.first;
      final remainingQueue = List<Map<String, dynamic>>.from(state.queue)..removeAt(0);
      state = state.copyWith(queue: remainingQueue);
      playSong(nextSong, state.originalPlaylist);
      return;
    }

    if (state.activePlaylist.isEmpty) return;
    int idx = state.activePlaylist.indexWhere((s) => s["id"] == state.currentSong!["id"]);
    
    if (idx != -1) {
      int nextIdx = idx + 1;
      if (nextIdx >= state.activePlaylist.length) {
        if (state.repeat == "all") {
          nextIdx = 0;
        } else {
          globalAudioHandler.pause();
          seek(Duration.zero);
          return;
        }
      }
      playSong(state.activePlaylist[nextIdx], state.originalPlaylist);
    }
  }

  void handlePrev() {
    if (state.activePlaylist.isEmpty || state.currentSong == null) return;
    
    if (state.position.inSeconds > 3) {
      seek(Duration.zero);
      return;
    }

    int idx = state.activePlaylist.indexWhere((s) => s["id"] == state.currentSong!["id"]);
    if (idx != -1) {
      int prevIdx = idx - 1;
      if (prevIdx < 0) {
        if (state.repeat == "all") {
          prevIdx = state.activePlaylist.length - 1;
        } else {
          prevIdx = 0;
        }
      }
      playSong(state.activePlaylist[prevIdx], state.originalPlaylist);
    }
  }

  void addToQueue(Map<String, dynamic> song) {
    final updatedQueue = List<Map<String, dynamic>>.from(state.queue)..add(song);
    state = state.copyWith(queue: updatedQueue);
  }

  void playNext(Map<String, dynamic> song) {
    final updatedQueue = List<Map<String, dynamic>>.from(state.queue)..insert(0, song);
    state = state.copyWith(queue: updatedQueue);
  }

  void reorderQueue(int oldIndex, int newIndex) {
    final updatedQueue = List<Map<String, dynamic>>.from(state.queue);
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    final item = updatedQueue.removeAt(oldIndex);
    updatedQueue.insert(newIndex, item);
    state = state.copyWith(queue: updatedQueue);
  }

  void removeFromQueue(int index) {
    final updatedQueue = List<Map<String, dynamic>>.from(state.queue)..removeAt(index);
    state = state.copyWith(queue: updatedQueue);
  }

  void clearQueue() {
    state = state.copyWith(queue: const []);
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _durSub?.cancel();
    _stateSub?.cancel();
    _positionLogTimer?.cancel();
    super.dispose();
  }
}

final playerProvider = StateNotifierProvider<PlayerNotifier, PlayerState>((ref) {
  return PlayerNotifier();
});

final showNowPlayingProvider = StateProvider<bool>((ref) => false);
```

### 2. `app/lib/screens/queue_screen.dart`
[queue_screen.dart](file:///e:/PROJECT%20SONDRA/sondra/app/lib/screens/queue_screen.dart)
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/player_provider.dart';
import '../widgets/song_cover.dart';

class QueueScreen extends ConsumerWidget {
  const QueueScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playerState = ref.watch(playerProvider);
    final notifier = ref.read(playerProvider.notifier);

    final currentSong = playerState.currentSong;
    final manualQueue = playerState.queue;

    final remainingPlaylistSongs = <Map<String, dynamic>>[];
    if (currentSong != null && playerState.activePlaylist.isNotEmpty) {
      final currentIdx = playerState.activePlaylist.indexWhere((s) => s["id"] == currentSong["id"]);
      if (currentIdx != -1) {
        for (int i = currentIdx + 1; i < playerState.activePlaylist.length; i++) {
          remainingPlaylistSongs.add(playerState.activePlaylist[i]);
        }
      }
    }

    return Scaffold(
      backgroundColor: const Color(0xFF08070D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111019),
        foregroundColor: Colors.white,
        title: const Text("Play Queue", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        actions: [
          if (manualQueue.isNotEmpty)
            TextButton(
              onPressed: () => notifier.clearQueue(),
              child: const Text("Clear Queue", style: TextStyle(color: Color(0xFF8B5CF6))),
            ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          if (currentSong != null) ...[
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.only(left: 16.0, right: 16.0, top: 16.0, bottom: 8.0),
                child: Text("Now playing", style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.bold)),
              ),
            ),
            SliverToBoxAdapter(
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                leading: SongCoverWidget(
                  song: currentSong,
                  width: 48,
                  height: 48,
                  borderRadius: 6.0,
                ),
                title: Text(
                  currentSong["title"] ?? "Unknown Track",
                  style: const TextStyle(color: Color(0xFF8B5CF6), fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  currentSong["artist"] ?? "Unknown Artist",
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),
              ),
            ),
          ],

          if (manualQueue.isNotEmpty) ...[
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.only(left: 16.0, right: 16.0, top: 24.0, bottom: 8.0),
                child: Text("Next in Queue", style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.bold)),
              ),
            ),
            SliverReorderableList(
              itemCount: manualQueue.length,
              onReorder: (oldIndex, newIndex) {
                notifier.reorderQueue(oldIndex, newIndex);
              },
              itemBuilder: (context, index) {
                final s = manualQueue[index];
                return ReorderableDelayedDragStartListener(
                  key: ValueKey("queue_${s['id']}_$index"),
                  index: index,
                  child: Dismissible(
                    key: ValueKey("dismiss_${s['id']}_$index"),
                    direction: DismissDirection.endToStart,
                    onDismissed: (_) {
                      notifier.removeFromQueue(index);
                    },
                    background: Container(
                      color: Colors.redAccent.withOpacity(0.2),
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 24),
                      child: const Icon(Icons.delete_rounded, color: Colors.redAccent),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                      leading: SongCoverWidget(
                        song: s,
                        width: 44,
                        height: 44,
                        borderRadius: 6.0,
                      ),
                      title: Text(
                        s["title"] ?? "Unknown Track",
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
                      ),
                      subtitle: Text(
                        s["artist"] ?? "Unknown Artist",
                        style: const TextStyle(color: Colors.white38, fontSize: 11),
                      ),
                      trailing: const Icon(Icons.drag_handle_rounded, color: Colors.white24),
                    ),
                  ),
                );
              },
            ),
          ],

          if (remainingPlaylistSongs.isNotEmpty) ...[
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.only(left: 16.0, right: 16.0, top: 24.0, bottom: 8.0),
                child: Text("Next up from active list", style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.bold)),
              ),
            ),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final s = remainingPlaylistSongs[index];
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    leading: SongCoverWidget(
                      song: s,
                      width: 44,
                      height: 44,
                      borderRadius: 6.0,
                    ),
                    title: Text(
                      s["title"] ?? "Unknown Track",
                      style: const TextStyle(color: Colors.white60, fontSize: 14),
                    ),
                    subtitle: Text(
                      s["artist"] ?? "Unknown Artist",
                      style: const TextStyle(color: Colors.white38, fontSize: 11),
                    ),
                  );
                },
                childCount: remainingPlaylistSongs.length,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
```

### 3. `app/lib/services/offline_storage.dart`
[offline_storage.dart](file:///e:/PROJECT%20SONDRA/sondra/app/lib/services/offline_storage.dart)
```dart
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class OfflineStorage {
  static final OfflineStorage _instance = OfflineStorage._();
  factory OfflineStorage() => _instance;
  OfflineStorage._();

  List<Map<String, dynamic>> _playlists = [];

  Future<String> get _storageDir async {
    final dir = await getApplicationSupportDirectory();
    final storage = Directory(p.join(dir.path, 'sondra_data'));
    if (!await storage.exists()) {
      await storage.create(recursive: true);
    }
    return storage.path;
  }

  Future<File> get _playlistsFile async {
    final d = await _storageDir;
    return File(p.join(d, 'offline_playlists.json'));
  }

  Future<String> get downloadsDir async {
    final dir = await getApplicationSupportDirectory();
    final dl = Directory(p.join(dir.path, 'sondra_downloads'));
    if (!await dl.exists()) {
      await dl.create(recursive: true);
    }
    return dl.path;
  }

  Future<void> init() async {
    final file = await _playlistsFile;
    if (await file.exists()) {
      final content = await file.readAsString();
      if (content.isNotEmpty) {
        _playlists = List<Map<String, dynamic>>.from(jsonDecode(content));
        bool changed = false;
        for (final pl in _playlists) {
          final songs = List<Map<String, dynamic>>.from(pl['songs'] ?? []);
          for (final song in songs) {
            if (song['status'] == 'downloading') {
              song['status'] = 'notDownloaded';
              song['progress'] = 0.0;
              changed = true;
            }
          }
        }
        if (changed) await _save();
      }
    }
  }

  Future<void> _save() async {
    final file = await _playlistsFile;
    await file.writeAsString(jsonEncode(_playlists));
  }

  List<Map<String, dynamic>> get playlists => _playlists;

  Map<String, dynamic>? getPlaylist(int id) {
    final idx = _playlists.indexWhere((p) => p['id'] == id);
    if (idx != -1) return _playlists[idx];
    return null;
  }

  Future<Map<String, dynamic>> createPlaylist(String name) async {
    final newPlaylist = {
      'id': DateTime.now().millisecondsSinceEpoch,
      'name': name,
      'songs': <Map<String, dynamic>>[],
    };
    _playlists.add(newPlaylist);
    await _save();
    return newPlaylist;
  }

  Future<void> deletePlaylist(int id) async {
    _playlists.removeWhere((p) => p['id'] == id);
    await _save();
  }

  Future<void> addSongsToPlaylist(int playlistId, List<Map<String, dynamic>> songs) async {
    final pIdx = _playlists.indexWhere((p) => p['id'] == playlistId);
    if (pIdx == -1) return;

    final existingSongs = List<Map<String, dynamic>>.from(_playlists[pIdx]['songs'] ?? []);
    for (final song in songs) {
      final duplicate = existingSongs.any((s) => s['song_id'] == song['id']);
      if (!duplicate) {
        existingSongs.add({
          'id': DateTime.now().millisecondsSinceEpoch + existingSongs.length,
          'song_id': song['id'],
          'title': song['title'],
          'artist': song['artist'],
          'album': song['album'],
          'duration_seconds': song['duration_seconds'],
          'cover_url': song['cover_url'],
          'status': 'notDownloaded', // 'notDownloaded' | 'downloading' | 'completed'
          'local_file_path': null,
          'progress': 0.0,
        });
      }
    }
    _playlists[pIdx]['songs'] = existingSongs;
    await _save();
  }

  Future<void> updateSongStatus(int playlistId, int songEntryId, String status, {String? filePath, double? progress}) async {
    final pIdx = _playlists.indexWhere((p) => p['id'] == playlistId);
    if (pIdx == -1) return;

    final songs = List<Map<String, dynamic>>.from(_playlists[pIdx]['songs'] ?? []);
    final sIdx = songs.indexWhere((s) => s['id'] == songEntryId);
    if (sIdx == -1) return;

    songs[sIdx]['status'] = status;
    if (filePath != null) songs[sIdx]['local_file_path'] = filePath;
    if (progress != null) songs[sIdx]['progress'] = progress;

    _playlists[pIdx]['songs'] = songs;
    await _save();
  }

  Future<int> getTotalDownloadsSize() async {
    final dirPath = await downloadsDir;
    final dir = Directory(dirPath);
    int total = 0;
    if (await dir.exists()) {
      await for (final file in dir.list(recursive: true, followLinks: false)) {
        if (file is File) {
          total += await file.length();
        }
      }
    }
    return total;
  }

  Future<void> clearAllDownloads() async {
    final dirPath = await downloadsDir;
    final dir = Directory(dirPath);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
    for (final pl in _playlists) {
      final songs = List<Map<String, dynamic>>.from(pl['songs'] ?? []);
      for (final song in songs) {
        song['status'] = 'notDownloaded';
        song['local_file_path'] = null;
        song['progress'] = 0.0;
      }
      pl['songs'] = songs;
    }
    await _save();
  }

  Future<void> removeSongDownload(int songId) async {
    bool changed = false;
    for (int i = 0; i < _playlists.length; i++) {
      final songs = List<Map<String, dynamic>>.from(_playlists[i]['songs'] ?? []);
      bool playlistChanged = false;
      for (int j = 0; j < songs.length; j++) {
        if (songs[j]['song_id'] == songId) {
          songs[j]['status'] = 'notDownloaded';
          songs[j]['local_file_path'] = null;
          songs[j]['progress'] = 0.0;
          playlistChanged = true;
          changed = true;
        }
      }
      if (playlistChanged) {
        _playlists[i]['songs'] = songs;
      }
    }
    if (changed) {
      await _save();
    }
  }
}
```

### 4. `app/lib/services/download_manager.dart`
[download_manager.dart](file:///e:/PROJECT%20SONDRA/sondra/app/lib/services/download_manager.dart)
```dart
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

  Future<void> downloadSong(int playlistId, Map<String, dynamic> songEntry) async {
    final songEntryId = songEntry['id'] as int;
    final songId = songEntry['song_id'] as int;
    final dlDir = await OfflineStorage().downloadsDir;
    final filePath = p.join(dlDir, '$songId.mp3');

    final url = '${_api.baseUrl}/api/stream/$songId/proxy?token=${_api.token}';
    final cancelToken = CancelToken();
    _activeDownloads[songId.toString()] = cancelToken;

    final storage = OfflineStorage();

    try {
      await storage.updateSongStatus(playlistId, songEntryId, 'downloading', progress: 0.0);

      await _api.dio.download(
        url,
        filePath,
        onReceiveProgress: (received, total) {
          final progress = total != -1 ? received / total : 0.0;
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

      await storage.updateSongStatus(playlistId, songEntryId, 'completed', filePath: filePath, progress: 1.0);
      _progressController.add({
        'playlistId': playlistId,
        'songEntryId': songEntryId,
        'songId': songId,
        'status': 'completed',
        'progress': 1.0,
      });
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        await storage.updateSongStatus(playlistId, songEntryId, 'notDownloaded', progress: 0.0);
      } else {
        print('Download failed for song $songId: $e');
        await storage.updateSongStatus(playlistId, songEntryId, 'notDownloaded', progress: 0.0);
      }
    } catch (e) {
      print('Download error for song $songId: $e');
      await storage.updateSongStatus(playlistId, songEntryId, 'notDownloaded', progress: 0.0);
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
```

### 5. `app/lib/services/api_service.dart`
[api_service.dart](file:///e:/PROJECT%20SONDRA/sondra/app/lib/services/api_service.dart)
```dart
import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  final Dio dio = Dio();
  String? baseUrl;
  String? token;
  StreamController<Map<String, dynamic>> sseController = StreamController.broadcast();
  StreamSubscription? sseSubscription;

  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal() {
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        if (token != null) {
          options.headers["Authorization"] = "Bearer $token";
        }
        return handler.next(options);
      },
      onError: (DioException e, handler) async {
        if (e.response?.statusCode == 401) {
          await logout();
        }
        return handler.next(e);
      },
    ));
  }

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    baseUrl = "https://sondra-backend.onrender.com";
    token = prefs.getString("sondra_token");
    dio.options.baseUrl = baseUrl!;
    if (token != null) {
      startSseConnection();
    }
  }

  Future<bool> login(String username, String password) async {
    String cleanUrl = "https://sondra-backend.onrender.com";
    
    try {
      final response = await dio.post(
        "$cleanUrl/auth/login",
        data: {"username": username, "password": password},
      );
      
      final String jwtToken = response.data["access_token"];
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString("sondra_server_url", cleanUrl);
      await prefs.setString("sondra_token", jwtToken);
      
      baseUrl = cleanUrl;
      token = jwtToken;
      dio.options.baseUrl = cleanUrl;
      
      startSseConnection();
      return true;
    } catch (e) {
      print("Login failed: $e");
      return false;
    }
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove("sondra_token");
    token = null;
    sseSubscription?.cancel();
  }

  void startSseConnection() {
    sseSubscription?.cancel();
    if (baseUrl == null || token == null) return;

    final sseUrl = "$baseUrl/api/events?token=$token";
    
    StreamSubscription? sub;
    sub = dio.get<ResponseBody>(
      sseUrl,
      options: Options(responseType: ResponseType.stream),
    ).asStream().listen((response) {
      final stream = response.data?.stream;
      if (stream == null) return;
      
      sseSubscription = stream.cast<List<int>>().transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
        if (line.startsWith("data: ")) {
          try {
            final jsonStr = line.substring(6);
            final data = Map<String, dynamic>.from(jsonDecode(jsonStr));
            sseController.add(data);
          } catch (e) {
            print("Error parsing SSE line: $e");
          }
        }
      }, onError: (err) {
        print("SSE stream error: $err. Reconnecting in 5s...");
        Future.delayed(const Duration(seconds: 5), startSseConnection);
      }, onDone: () {
        print("SSE stream closed. Reconnecting in 5s...");
        Future.delayed(const Duration(seconds: 5), startSseConnection);
      });
    }, onError: (err) {
      print("Failed to open SSE: $err. Retrying in 10s...");
      Future.delayed(const Duration(seconds: 10), startSseConnection);
    });
    
    sseSubscription = sub;
  }

  Future<List<dynamic>> getSongs() async {
    final res = await dio.get("/api/songs");
    return res.data;
  }

  Future<List<dynamic>> getSongsSearch(String query) async {
    final res = await dio.get("/api/songs/search", queryParameters: {"q": query});
    return res.data;
  }

  Future<List<dynamic>> getPlaylists() async {
    final res = await dio.get("/api/playlists");
    return res.data;
  }

  Future<List<dynamic>> getHistoryRecent() async {
    final res = await dio.get("/api/history/recent", queryParameters: {"limit": 20});
    return res.data;
  }

  Future<List<dynamic>> getHistoryContinue() async {
    final res = await dio.get("/api/history/continue");
    return res.data;
  }

  Future<void> logHistory(int songId, int positionSeconds) async {
    await dio.post("/api/history", data: {
      "song_id": songId,
      "position_seconds": positionSeconds,
    });
  }

  Future<String> getDirectStreamUrl(int songId) async {
    final res = await dio.get("/api/stream/$songId");
    return res.data["stream_url"];
  }

  Future<String> getDownloadUrl(int songId) async {
    return "$baseUrl/api/stream/$songId/proxy?token=$token";
  }

  Future<void> triggerSync() async {
    await dio.post("/api/sync");
  }

  Future<Map<String, dynamic>> getSyncStatus() async {
    final res = await dio.get("/api/sync/status");
    return Map<String, dynamic>.from(res.data);
  }
}
```

### 6. `app/lib/services/audio_handler.dart`
[audio_handler.dart](file:///e:/PROJECT%20SONDRA/sondra/app/lib/services/audio_handler.dart)
```dart
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:smtc_windows/smtc_windows.dart';
import 'package:audio_session/audio_session.dart';

class SondraAudioHandler extends BaseAudioHandler {
  final AudioPlayer _player = AudioPlayer();
  SMTCWindows? _smtc;
  Future<void>? _initFuture;

  Future<void> Function()? onSkipToNext;
  Future<void> Function()? onSkipToPrevious;

  SondraAudioHandler() {
    _player.playbackEventStream.map(_transformEvent).pipe(playbackState);

    if (kIsWeb ? false : Platform.isWindows) {
      _initWindowsSmtc();
    }

    ensureInitialized();
  }

  Future<void> ensureInitialized() async {
    _initFuture ??= _initAudioSession();
    await _initFuture;
  }

  Future<void> _initAudioSession() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
    } catch (e) {
      print("AudioSession configuration failed: $e");
    }
  }

  void _initWindowsSmtc() {
    _smtc = SMTCWindows();
    
    _smtc!.buttonPressStream.listen((event) async {
      switch (event) {
        case PressedButton.play:
          play();
          break;
        case PressedButton.pause:
          pause();
          break;
        case PressedButton.next:
          skipToNext();
          break;
        case PressedButton.previous:
          skipToPrevious();
          break;
        default:
          break;
      }
    });

    _player.playingStream.listen((playing) {
      _smtc?.setPlaybackStatus(
        playing ? PlaybackStatus.Playing : PlaybackStatus.Paused
      );
    });

    _player.positionStream.listen((pos) {
      _smtc?.setPosition(pos);
    });
    
    _player.durationStream.listen((dur) {
      if (dur != null) {
        _smtc?.setEndTime(dur);
      }
    });
  }

  Future<void> playUri(String uri, MediaItem item) async {
    await ensureInitialized();
    mediaItem.add(item);

    if (_smtc != null) {
      _smtc!.setTitle(item.title);
      _smtc!.setArtist(item.artist ?? "Unknown Artist");
      if (item.album != null) {
        _smtc!.setAlbum(item.album!);
      }
    }

    try {
      final isLocalFilePath = uri.startsWith('/') || 
          (uri.length > 2 && uri[1] == ':');
      
      if (isLocalFilePath) {
        await _player.setAudioSource(AudioSource.file(uri));
      } else {
        final parsedUri = Uri.parse(uri);
        if (parsedUri.scheme == 'file') {
          await _player.setAudioSource(AudioSource.file(parsedUri.toFilePath()));
        } else {
          await _player.setAudioSource(LockCachingAudioSource(parsedUri));
        }
      }
      await _player.play();
    } catch (e) {
      print("Audio player setSource error: $e");
      playbackState.add(playbackState.value.copyWith(
        errorMessage: e.toString(),
      ));
    }
  }

  @override
  Future<void> skipToNext() async {
    if (onSkipToNext != null) {
      await onSkipToNext!();
    }
  }

  @override
  Future<void> skipToPrevious() async {
    if (onSkipToPrevious != null) {
      await onSkipToPrevious!();
    }
  }

  @override
  Future<void> play() async {
    await ensureInitialized();
    await _player.play();
  }

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> stop() async {
    await _player.stop();
    await playbackState.firstWhere((state) => state.processingState == AudioProcessingState.idle);
  }

  AudioPlayer get player => _player;

  PlaybackState _transformEvent(PlaybackEvent event) {
    return PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        if (_player.playing) MediaControl.pause else MediaControl.play,
        MediaControl.stop,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      androidCompactActionIndices: const [0, 1, 3],
      processingState: const {
        ProcessingState.idle: AudioProcessingState.idle,
        ProcessingState.loading: AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready: AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[_player.processingState]!,
      playing: _player.playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: event.currentIndex,
    );
  }
}
```

### 7. `app/lib/screens/create_offline_playlist_screen.dart`
[create_offline_playlist_screen.dart](file:///e:/PROJECT%20SONDRA/sondra/app/lib/screens/create_offline_playlist_screen.dart)
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_service.dart';
import '../services/offline_storage.dart';
import '../widgets/song_cover.dart';

class CreateOfflinePlaylistScreen extends ConsumerStatefulWidget {
  const CreateOfflinePlaylistScreen({super.key});

  @override
  ConsumerState<CreateOfflinePlaylistScreen> createState() =>
      _CreateOfflinePlaylistScreenState();
}

class _CreateOfflinePlaylistScreenState
    extends ConsumerState<CreateOfflinePlaylistScreen> {
  final _nameController = TextEditingController();
  final Set<int> _selectedSongIds = {};
  List<Map<String, dynamic>> _allSongs = [];
  bool _loadingSongs = true;
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    _loadSongs();
  }

  Future<void> _loadSongs() async {
    try {
      final songs = await ApiService().getSongs();
      if (mounted) {
        setState(() {
          _allSongs = List<Map<String, dynamic>>.from(songs);
          _loadingSongs = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingSongs = false;
        });
      }
    }
  }

  Future<void> _createPlaylist() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    setState(() {
      _creating = true;
    });

    final selectedSongs =
        _allSongs.where((s) => _selectedSongIds.contains(s['id'])).toList();

    final storage = OfflineStorage();
    final playlist = await storage.createPlaylist(name);
    await storage.addSongsToPlaylist(playlist['id'] as int, selectedSongs);

    if (mounted) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF08070D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111019),
        foregroundColor: Colors.white,
        title: const Text('Create Offline Playlist',
            style: TextStyle(color: Colors.white)),
        elevation: 0,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _nameController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Playlist name',
                hintStyle: const TextStyle(color: Colors.white24),
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
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Select Songs (${_selectedSongIds.length})',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                ElevatedButton(
                  onPressed:
                      _nameController.text.trim().isEmpty || _selectedSongIds.isEmpty || _creating
                          ? null
                          : _createPlaylist,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF8B5CF6),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor:
                        const Color(0xFF8B5CF6).withOpacity(0.3),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 10),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  child: _creating
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Create'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _loadingSongs
                ? const Center(
                    child: CircularProgressIndicator(
                        color: Color(0xFF8B5CF6)))
                : ListView.builder(
                    itemCount: _allSongs.length,
                    itemBuilder: (context, index) {
                      final song = _allSongs[index];
                      final isSelected =
                          _selectedSongIds.contains(song['id']);
                      return ListTile(
                        onTap: () {
                          setState(() {
                            if (isSelected) {
                              _selectedSongIds.remove(song['id']);
                            } else {
                              _selectedSongIds.add(song['id'] as int);
                            }
                          });
                        },
                        leading: SongCoverWidget(
                          song: song,
                          width: 40,
                          height: 40,
                          borderRadius: 4.0,
                        ),
                        title: Text(
                          song['title'] ?? 'Unknown Track',
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w500),
                        ),
                        subtitle: Text(
                          song['artist'] ?? 'Unknown Artist',
                          style:
                              const TextStyle(color: Colors.white38, fontSize: 12),
                        ),
                        trailing: Icon(
                          isSelected
                              ? Icons.check_circle_rounded
                              : Icons.radio_button_unchecked_rounded,
                          color: isSelected
                              ? const Color(0xFF8B5CF6)
                              : Colors.white24,
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
```

### 8. `app/lib/widgets/song_cover.dart`
[song_cover.dart](file:///e:/PROJECT%20SONDRA/sondra/app/lib/widgets/song_cover.dart)
```dart
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/api_service.dart';

class SongCoverWidget extends StatelessWidget {
  final Map<String, dynamic> song;
  final double width;
  final double height;
  final double borderRadius;
  final double? iconSize;

  const SongCoverWidget({
    super.key,
    required this.song,
    required this.width,
    required this.height,
    this.borderRadius = 8.0,
    this.iconSize,
  });

  @override
  Widget build(BuildContext context) {
    final songTitle = song["title"] ?? "Unknown";
    final initial = songTitle.isNotEmpty ? songTitle[0].toUpperCase() : "♫";

    if (song["cover_url"] == null || (song["cover_url"] is String && (song["cover_url"] as String).isEmpty)) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: _buildPlaceholder(initial),
      );
    }

    final coverUrl = "${ApiService().baseUrl}/api/songs/${song["id"]}/cover";

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: CachedNetworkImage(
        imageUrl: coverUrl,
        width: width,
        height: height,
        fit: BoxFit.cover,
        errorWidget: (_, __, ___) => _buildPlaceholder(initial),
        placeholder: (_, __) => Container(
          width: width,
          height: height,
          color: Colors.white.withOpacity(0.05),
          child: const Center(
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF8B5CF6)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceholder(String initial) {
    final songTitle = song["title"] ?? "";
    
    int hash = 0;
    for (int i = 0; i < songTitle.length; i++) {
      hash = songTitle.codeUnitAt(i) + ((hash << 5) - hash);
    }
    
    final List<List<Color>> palettes = [
      [const Color(0xFFF43F5E), const Color(0xFFFB7185)],
      [const Color(0xFFEC4899), const Color(0xFFF472B6)],
      [const Color(0xFFD946EF), const Color(0xFFE879F9)],
      [const Color(0xFFA855F7), const Color(0xFFC084FC)],
      [const Color(0xFF8B5CF6), const Color(0xFFA78BFA)],
      [const Color(0xFF6366F1), const Color(0xFF818CF8)],
      [const Color(0xFF3B82F6), const Color(0xFF60A5FA)],
      [const Color(0xFF0EA5E9), const Color(0xFF38BDF8)],
      [const Color(0xFF06B6D4), const Color(0xFF22D3EE)],
      [const Color(0xFF14B8A6), const Color(0xFF2DD4BF)],
      [const Color(0xFF10B981), const Color(0xFF34D399)],
      [const Color(0xFF22C55E), const Color(0xFF4ADE80)],
      [const Color(0xFFEAB308), const Color(0xFFFACC15)],
      [const Color(0xFFF97316), const Color(0xFFFB923C)],
      [const Color(0xFFEF4444), const Color(0xFFF87171)],
    ];

    final index = hash.abs() % palettes.length;
    final colors = palettes[index];

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Text(
          initial,
          style: TextStyle(
            color: Colors.white,
            fontSize: iconSize ?? (width * 0.4),
            fontWeight: FontWeight.bold,
            shadows: [
              Shadow(
                color: Colors.black.withOpacity(0.35),
                offset: const Offset(1, 2),
                blurRadius: 4,
              )
            ]
          ),
        ),
      ),
    );
  }
}
```

### 9. `app/lib/widgets/song_options_menu.dart`
[song_options_menu.dart](file:///e:/PROJECT%20SONDRA/sondra/app/lib/widgets/song_options_menu.dart)
```dart
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/player_provider.dart';
import '../services/offline_storage.dart';
import '../services/download_manager.dart';

class SongOptionsButton extends ConsumerWidget {
  final Map<String, dynamic> song;
  final bool inQueue;
  final int? queueIndex;

  const SongOptionsButton({
    super.key,
    required this.song,
    this.inQueue = false,
    this.queueIndex,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (kIsWeb ? false : Platform.isWindows) {
      return GestureDetector(
        onTapDown: (details) {
          _showWindowsDropdown(context, details.globalPosition, ref);
        },
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8.0, vertical: 12.0),
          child: Icon(Icons.more_vert_rounded, color: Colors.white54, size: 20),
        ),
      );
    } else {
      return IconButton(
        icon: const Icon(Icons.more_vert_rounded, color: Colors.white54, size: 20),
        onPressed: () {
          _showAndroidBottomSheet(context, ref);
        },
      );
    }
  }

  void _showWindowsDropdown(BuildContext context, Offset globalPos, WidgetRef ref) {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(globalPos, globalPos),
      Offset.zero & overlay.size,
    );

    showMenu(
      context: context,
      position: position,
      color: const Color(0xFF111019),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      items: _buildMenuItems(context, ref, isWindows: true),
    );
  }

  static void showRightClickMenu(BuildContext context, Offset globalPos, WidgetRef ref, Map<String, dynamic> song, {bool inQueue = false, int? queueIndex}) {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(globalPos, globalPos),
      Offset.zero & overlay.size,
    );

    final button = SongOptionsButton(song: song, inQueue: inQueue, queueIndex: queueIndex);
    showMenu(
      context: context,
      position: position,
      color: const Color(0xFF111019),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      items: button._buildMenuItems(context, ref, isWindows: true),
    );
  }

  List<PopupMenuEntry<void>> _buildMenuItems(BuildContext context, WidgetRef ref, {required bool isWindows}) {
    return [
      _popupItem(
        icon: Icons.play_arrow_rounded,
        title: "Play Now",
        onTap: () {
          ref.read(playerProvider.notifier).playSong(song, [song]);
        },
      ),
      _popupItem(
        icon: Icons.playlist_play_rounded,
        title: "Play Next",
        onTap: () {
          ref.read(playerProvider.notifier).playNext(song);
        },
      ),
      _popupItem(
        icon: Icons.queue_music_rounded,
        title: "Add to Queue",
        onTap: () {
          ref.read(playerProvider.notifier).addToQueue(song);
        },
      ),
      _popupItem(
        icon: Icons.playlist_add_rounded,
        title: "Add to Personal Playlist",
        onTap: () {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _showPlaylistSelectionDialog(context, type: 'personal');
          });
        },
      ),
      _popupItem(
        icon: Icons.download_for_offline_rounded,
        title: "Download for Offline",
        onTap: () {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _showPlaylistSelectionDialog(context, type: 'offline');
          });
        },
      ),
      if (inQueue && queueIndex != null)
        _popupItem(
          icon: Icons.remove_circle_outline_rounded,
          title: "Remove from Queue",
          color: Colors.redAccent,
          onTap: () {
            ref.read(playerProvider.notifier).removeFromQueue(queueIndex!);
          },
        ),
    ];
  }

  PopupMenuItem<void> _popupItem({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    Color? color,
  }) {
    return PopupMenuItem<void>(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color ?? const Color(0xFF8B5CF6), size: 20),
          const SizedBox(width: 12),
          Text(
            title,
            style: TextStyle(
              color: color ?? Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  void _showAndroidBottomSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF111019),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white12,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(Icons.music_note_rounded, color: Colors.white30),
                ),
                title: Text(
                  song['title'] ?? 'Unknown Title',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  song['artist'] ?? 'Unknown Artist',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Divider(color: Colors.white10),
              _bottomSheetItem(
                context: ctx,
                icon: Icons.play_arrow_rounded,
                title: "Play Now",
                onTap: () {
                  ref.read(playerProvider.notifier).playSong(song, [song]);
                },
              ),
              _bottomSheetItem(
                context: ctx,
                icon: Icons.playlist_play_rounded,
                title: "Play Next",
                onTap: () {
                  ref.read(playerProvider.notifier).playNext(song);
                },
              ),
              _bottomSheetItem(
                context: ctx,
                icon: Icons.queue_music_rounded,
                title: "Add to Queue",
                onTap: () {
                  ref.read(playerProvider.notifier).addToQueue(song);
                },
              ),
              _bottomSheetItem(
                context: ctx,
                icon: Icons.playlist_add_rounded,
                title: "Add to Personal Playlist",
                onTap: () {
                  _showPlaylistSelectionDialog(context, type: 'personal');
                },
              ),
              _bottomSheetItem(
                context: ctx,
                icon: Icons.download_for_offline_rounded,
                title: "Download for Offline",
                onTap: () {
                  _showPlaylistSelectionDialog(context, type: 'offline');
                },
              ),
              if (inQueue && queueIndex != null)
                _bottomSheetItem(
                  context: ctx,
                  icon: Icons.remove_circle_outline_rounded,
                  title: "Remove from Queue",
                  color: Colors.redAccent,
                  onTap: () {
                    ref.read(playerProvider.notifier).removeFromQueue(queueIndex!);
                  },
                ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  Widget _bottomSheetItem({
    required BuildContext context,
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    Color? color,
  }) {
    return ListTile(
      leading: Icon(icon, color: color ?? const Color(0xFF8B5CF6)),
      title: Text(
        title,
        style: TextStyle(
          color: color ?? Colors.white,
          fontWeight: FontWeight.w500,
        ),
      ),
      onTap: () {
        Navigator.of(context).pop();
        onTap();
      },
    );
  }

  void _showPlaylistSelectionDialog(BuildContext context, {required String type}) {
    final storage = OfflineStorage();
    final playlists = storage.getPlaylists().where((p) => p['type'] == type).toList();

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF111019),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            type == 'personal' ? "Add to Personal Playlist" : "Download for Offline",
            style: const TextStyle(color: Colors.white),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: [
                ListTile(
                  leading: const Icon(Icons.add_rounded, color: Color(0xFF8B5CF6)),
                  title: Text(
                    type == 'personal' ? "Create New Personal Playlist" : "Create New Offline Playlist",
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                  onTap: () async {
                    Navigator.of(ctx).pop();
                    await _showCreatePlaylistPrompt(context, type: type);
                  },
                ),
                const Divider(color: Colors.white10),
                if (playlists.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text(
                        "No playlists of this type",
                        style: TextStyle(color: Colors.white38),
                      ),
                    ),
                  ),
                ...playlists.map((pl) {
                  return ListTile(
                    leading: Icon(
                      type == 'personal' ? Icons.playlist_play_rounded : Icons.offline_pin_rounded,
                      color: const Color(0xFF8B5CF6),
                    ),
                    title: Text(
                      pl['name'] ?? 'Unnamed',
                      style: const TextStyle(color: Colors.white),
                    ),
                    onTap: () async {
                      Navigator.of(ctx).pop();
                      await _addSongToPlaylist(context, pl['id'] as int, type: type);
                    },
                  );
                }),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text("Cancel", style: TextStyle(color: Colors.white54)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showCreatePlaylistPrompt(BuildContext context, {required String type}) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF111019),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          type == 'personal' ? "New Personal Playlist" : "New Offline Playlist",
          style: const TextStyle(color: Colors.white),
        ),
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
      final pl = await OfflineStorage().createPlaylist(name, type: type);
      if (context.mounted) {
        await _addSongToPlaylist(context, pl['id'] as int, type: type);
      }
    }
  }

  Future<void> _addSongToPlaylist(BuildContext context, int playlistId, {required String type}) async {
    final storage = OfflineStorage();
    await storage.addSongsToPlaylist(playlistId, [song]);

    if (type == 'offline') {
      final pl = storage.getPlaylist(playlistId);
      if (pl != null) {
        final songs = List<Map<String, dynamic>>.from(pl['songs'] ?? []);
        final entry = songs.firstWhere((s) => s['song_id'] == song['id']);
        DownloadManager().downloadSong(playlistId, entry);
      }
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            type == 'personal' 
                ? "Added to Personal Playlist"
                : "Added to Offline Playlist (Download started)",
          ),
          backgroundColor: const Color(0xFF8B5CF6),
        ),
      );
    }
  }
}
```
