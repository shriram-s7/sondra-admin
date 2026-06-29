# Sondra Music Codebase Status & Achievements

Sondra Music is a premium cross-platform music streaming player built with Flutter (for Windows and Android apps) and React/TypeScript/Vite (for the Admin panel). It integrates with a custom Python/FastAPI backend to stream music files directly from Google Drive via secure authentication proxies.

---

## Achievements & Key Features Implemented

1. **Instant Spotify-like Playback & Seek Resets:** Tapping any song stops current playback immediately and starts the new song instantly. Seeking resets the timeline dynamically.
2. **Interactive Play Queue:** Supports manual "Add to Queue" priority placement. Queue screen features reorderable drag-and-drop tracks and swipe-to-delete gestures. Falls back smoothly to the active playlist once the queue is exhausted.
3. **Offline Mode & Local Downloads:** Users can create offline playlists and download tracks directly to local device storage.
4. **App Version Check & Data Purging:** Automatically detects app updates/fresh installs on startup using version markers in SharedPreferences, running a full storage clean of old downloads, cached files, and database indexes if a mismatch is found.
5. **Storage Settings Controls:** Provides a "Storage Management" interface showing JustAudio cache sizes and offline downloads size, equipped with buttons to clear cache, clear downloads, and a manual "Clear All Data" safety action with confirmation dialog.
6. **Platform Integrations & Keyboard Controls:** 
   - **Windows SMTC:** Full System Media Transport Controls integration (locks media keys, displays title/artist/album on screen, and allows background controls when minimized).
   - **Hotkeys:** Space/P toggles playback, Left/Right arrows seek 10s, and Media buttons work natively.
   - **Android Foreground Service:** Integrates `audio_service` to run background playback, manages a sticky notification drawer, and handles Bluetooth earbud commands (single-click play/pause, double-click skips, left earbud prev/restart).

---

## Directory Structure

```
PROJECT SONDRA/
├── admin/                     # React/Vite Admin Dashboard
│   ├── src/
│   │   ├── App.tsx            # Main UI, collapsible queue panel, song manager
│   │   ├── api.ts             # Axios backend client interceptors
│   │   └── index.css          # Core CSS stylesheet
│   └── package.json
│
├── app/                       # Flutter Cross-Platform Client
│   ├── android/               # Android Platform Settings
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
    ├── routers/
    │   ├── auth.py            # User login & JWT validation
    │   ├── playlists.py       # Folder playlists sync endpoints
    │   ├── songs.py           # Songs list & metadata endpoints
    │   ├── stream.py          # Google Drive stream proxy & seek resolver
    │   └── sync.py            # SSE background sync worker
    ├── main.py                # Server entrypoint & middleware configuration
    ├── database.py            # SQLAlchemy session setup
    ├── models.py              # Relational database schemes
    └── gdrive.py              # Google API client auth wrappers
```

---

## Complete Core Codebase Files

Here is the complete source code for all the core files in the project:

### 1. `app/lib/main.dart`
[main.dart](file:///e:/PROJECT SONDRA/sondra/app/lib/main.dart)
```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:audio_service/audio_service.dart';
import 'services/audio_handler.dart';
import 'services/offline_storage.dart';
import 'providers/player_provider.dart';
import 'screens/setup_screen.dart';

// Global navigator key so the mini-player overlay can show modal sheets
// even when the context is above the navigator tree.
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize offline storage for offline playlists
  await OfflineStorage().init();

  // AudioService.init may fail silently on Windows/desktop; fall back to
  // direct handler so just_audio still works natively.
  try {
    globalAudioHandler = await AudioService.init(
      builder: () => SondraAudioHandler(),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.sondra.music.channel.audio',
        androidNotificationChannelName: 'Sondra Music Playback',
        androidNotificationOngoing: true,
        androidShowNotificationBadge: true,
      ),
    );
  } catch (e) {
    debugPrint('AudioService.init failed ($e) — using direct handler');
    globalAudioHandler = SondraAudioHandler();
  }

  runApp(
    const ProviderScope(
      child: SondraApp(),
    ),
  );
}

class SondraApp extends StatelessWidget {
  const SondraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sondra Music',
      debugShowCheckedModeBanner: false,
      navigatorKey: rootNavigatorKey,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF08070D),
        primaryColor: const Color(0xFF8B5CF6),
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF8B5CF6),
          brightness: Brightness.dark,
          background: const Color(0xFF08070D),
          surface: const Color(0xFF111019),
        ),
        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: Color(0xFFF3F4F6)),
          bodyMedium: TextStyle(color: Color(0xFF9CA3AF)),
        ),
      ),

      // builder wraps the entire navigator stack, so the MiniPlayer
      // is rendered above ALL routes (home, playlists, now-playing, etc.)
      builder: (context, child) {
        return Consumer(
          builder: (ctx, ref, _) {
            final playerState = ref.watch(playerProvider);

            // Wrap in a global Focus widget to handle global Spacebar & 'P' keyboard shortcuts
            return Focus(
              autofocus: true,
              focusNode: FocusNode(debugLabel: 'GlobalAppFocus'),
              onKeyEvent: (node, event) {
                final isKeyDown = event is KeyDownEvent;
                if (isKeyDown) {
                  // Bypass hotkeys if a text input currently has active focus
                  final primaryFocus = FocusManager.instance.primaryFocus;
                  final hasInputFocus = primaryFocus != null &&
                      (primaryFocus.context?.widget is EditableText ||
                       primaryFocus.context?.findAncestorWidgetOfExactType<EditableText>() != null);
                  if (hasInputFocus) return KeyEventResult.ignored;

                  final key = event.logicalKey;
                  if (key == LogicalKeyboardKey.space || 
                      key == LogicalKeyboardKey.mediaPlayPause ||
                      key == LogicalKeyboardKey.mediaPlay ||
                      key == LogicalKeyboardKey.mediaPause) {
                    ref.read(playerProvider.notifier).togglePlay();
                    return KeyEventResult.handled;
                  }
                  if (key == LogicalKeyboardKey.arrowRight) {
                    final currentPos = playerState.position;
                    final targetPos = currentPos + const Duration(seconds: 10);
                    ref.read(playerProvider.notifier).seek(
                      targetPos < playerState.duration ? targetPos : playerState.duration
                    );
                    return KeyEventResult.handled;
                  }
                  if (key == LogicalKeyboardKey.arrowLeft) {
                    final currentPos = playerState.position;
                    final targetPos = currentPos - const Duration(seconds: 10);
                    ref.read(playerProvider.notifier).seek(
                      targetPos > Duration.zero ? targetPos : Duration.zero
                    );
                    return KeyEventResult.handled;
                  }
                  if (key == LogicalKeyboardKey.mediaTrackNext) {
                    ref.read(playerProvider.notifier).handleNext();
                    return KeyEventResult.handled;
                  }
                  if (key == LogicalKeyboardKey.mediaTrackPrevious) {
                    ref.read(playerProvider.notifier).handlePrev();
                    return KeyEventResult.handled;
                  }
                }
                return KeyEventResult.ignored;
              },
              child: Stack(
                children: [
                  // All app routes live inside `child`
                  child!,

                  // Android mobile floating mini-player overlay.
                  // Windows uses its own inline layout in HomeScreen.

                ],
              ),
            );
          },
        );
      },

      home: const SetupScreen(),
    );
  }
}
```

### 2. `app/lib/providers/player_provider.dart`
[player_provider.dart](file:///e:/PROJECT SONDRA/sondra/app/lib/providers/player_provider.dart)
```dart
import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import '../services/api_service.dart';
import '../services/audio_handler.dart';
import '../services/offline_storage.dart';

// Global audio handler instance injected in main
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
  final String activePlaylistName;

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
    this.activePlaylistName = "Song Pool",
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
    String? activePlaylistName,
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
      activePlaylistName: activePlaylistName ?? this.activePlaylistName,
    );
  }
}

class PlayerNotifier extends StateNotifier<PlayerState> {
  final ApiService _api = ApiService();
  Timer? _positionLogTimer;
  StreamSubscription? _posSub;
  StreamSubscription? _durSub;
  StreamSubscription? _stateSub;
  bool _isBusy = false;
  DateTime? _lastActionTime;

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
      if (_isBusy) return;
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

    // Save playback progress every 10 seconds
    _positionLogTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (state.isPlaying && state.currentSong != null) {
        _api.logHistory(state.currentSong!["id"], state.position.inSeconds);
      }
    });

    // Register Media / Earbud skip controls callback from background handler
    // CHANGE 5: 600ms debounce prevents double-tap earbud from firing twice
    globalAudioHandler.onSkipToNext = () async {
      final now = DateTime.now();
      if (_lastActionTime != null &&
          now.difference(_lastActionTime!) < const Duration(milliseconds: 600)) {
        return;
      }
      _lastActionTime = now;
      handleNext();
    };
    globalAudioHandler.onSkipToPrevious = () async {
      final now = DateTime.now();
      if (_lastActionTime != null &&
          now.difference(_lastActionTime!) < const Duration(milliseconds: 600)) {
        return;
      }
      _lastActionTime = now;
      handlePrev();
    };
  }

  Future<void> playSong(Map<String, dynamic> song, List<Map<String, dynamic>> playlist, {int? startSeconds, String? playlistName, bool internalCall = false}) async {
    if (_isBusy && !internalCall) return;
    _isBusy = true;
    try {
      // 1. Immediately stop current playback to release native resources instantly
      await globalAudioHandler.player.stop();
      await globalAudioHandler.player.seek(Duration.zero);

      // 2. Identify if it is a new queue or transition within the same queue
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

      // Apply active shuffle to new queue immediately if turned on
      if (isNewQueue && state.shuffle) {
        _secureShuffle(newActive);
        newActive.removeWhere((s) => s["id"] == song["id"]);
        newActive.insert(0, song);
      }

      // CHANGE 6: Set playlist/buffering state BEFORE load but do NOT set currentSong yet.
      // currentSong is updated AFTER playUri() succeeds so the banner always matches
      // the song that is actually playing, not a song that is still loading.
      final resolvedPlaylistName = playlistName ?? (isNewQueue ? "Song Pool" : state.activePlaylistName);
      state = state.copyWith(
        originalPlaylist: newOriginal,
        activePlaylist: newActive,
        activePlaylistName: resolvedPlaylistName,
        position: startSeconds != null ? Duration(seconds: startSeconds) : Duration.zero,
        isBuffering: true,
      );

      try {
        // 3. INSTANT PLAYBACK: Use local file if downloaded, otherwise stream
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

        // CHANGE 6: Only now that playUri() has succeeded do we update the banner song.
        state = state.copyWith(
          currentSong: song,
          isBuffering: false,
          isPlaying: true,
        );

        if (startSeconds != null) {
          await globalAudioHandler.seek(Duration(seconds: startSeconds));
        }
      } catch (e) {
        print("Error loading song in provider: $e");
        // Skip to next song automatically on loading error (Rule 5)
        handleNext();
      }
    } finally {
      _isBusy = false;
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

  void _secureShuffle<T>(List<T> list) {
    if (list.length < 2) return;
    final rand = Random.secure();
    int entropy = DateTime.now().millisecondsSinceEpoch;
    for (int i = list.length - 1; i > 0; i--) {
      int secureVal = rand.nextInt(i + 1);
      int mix = (secureVal + entropy) % (i + 1);
      final temp = list[i];
      list[i] = list[mix];
      list[mix] = temp;
      entropy = (entropy ^ (mix + 1)) * 31;
    }
  }

  Future<Map<String, dynamic>> _findPlaylistContextFor(Map<String, dynamic> song) async {
    // 1. Look up in local personal/offline playlists first
    final allLocalPlaylists = OfflineStorage().getPlaylists();
    for (final pl in allLocalPlaylists) {
      final songs = List<Map<String, dynamic>>.from(pl["songs"] ?? []);
      final exists = songs.any((s) => s["song_id"] == song["id"] || s["id"] == song["id"]);
      if (exists) {
        final name = pl["name"] ?? "Offline Playlist";
        final list = songs.map((s) => {
          'id': s['song_id'] ?? s['id'],
          'title': s['title'],
          'artist': s['artist'],
          'album': s['album'],
          'duration_seconds': s['duration_seconds'],
          'cover_url': s['cover_url'],
          'local_file_path': s['local_file_path'],
        }).toList();
        return {'name': name, 'songs': list};
      }
    }

    // 2. Fetch remote playlists from ApiService
    try {
      final remotePlaylists = await _api.getPlaylists();
      for (final pl in remotePlaylists) {
        final songs = List<dynamic>.from(pl["songs"] ?? []);
        final exists = songs.any((s) => s["id"] == song["id"]);
        if (exists) {
          final name = pl["name"] ?? "Remote Playlist";
          final list = songs.map<Map<String, dynamic>>((s) => Map<String, dynamic>.from(s)).toList();
          return {'name': name, 'songs': list};
        }
      }
    } catch (e) {
      print("Error fetching remote playlists in _findPlaylistContextFor: $e");
    }

    // 3. Fallback to all library songs
    try {
      final allLibrary = await _api.getSongs();
      final list = allLibrary.map<Map<String, dynamic>>((s) => Map<String, dynamic>.from(s)).toList();
      return {'name': "Music Library", 'songs': list};
    } catch (e) {
      print("Error fetching all library songs in _findPlaylistContextFor: $e");
    }

    return {'name': "Music Library", 'songs': [song]};
  }

  void toggleShuffle() {
    final nextShuffle = !state.shuffle;
    List<Map<String, dynamic>> newActive = List.from(state.originalPlaylist);
    
    if (nextShuffle) {
      _secureShuffle(newActive);
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

  Future<void> handleNext() async {
    final now = DateTime.now();
    if (_lastActionTime != null && 
        now.difference(_lastActionTime!) < const Duration(milliseconds: 600)) {
      return;
    }
    _lastActionTime = now;

    if (_isBusy) return;
    _isBusy = true;

    try {
      if (state.currentSong == null) return;

      // RULE 1 - QUEUE PLAYS ACROSS PLAYLISTS
      if (state.queue.isNotEmpty) {
        final nextSong = state.queue.first;
        final remainingQueue = List<Map<String, dynamic>>.from(state.queue)..removeAt(0);
        state = state.copyWith(queue: remainingQueue);
        
        final contextResult = await _findPlaylistContextFor(nextSong);
        final plName = contextResult['name'] as String;
        final plSongs = contextResult['songs'] as List<Map<String, dynamic>>;
        
        await playSong(nextSong, plSongs, playlistName: plName, internalCall: true);
        return;
      }

      // RULE 2 - CURRENT PLAYLIST PLAYS THROUGH COMPLETELY
      if (state.activePlaylist.isEmpty) return;
      int idx = state.activePlaylist.indexWhere((s) => s["id"] == state.currentSong!["id"]);
      
      if (idx != -1) {
        int nextIdx = idx + 1;
        if (nextIdx >= state.activePlaylist.length) {
          // RULE 5 - Loop/Repeat checks
          if (state.repeat == "all") {
            nextIdx = 0;
            await playSong(state.activePlaylist[nextIdx], state.originalPlaylist, internalCall: true);
          } else {
            // End of playlist: stop playback and reset position
            await globalAudioHandler.pause();
            await seek(Duration.zero);
          }
        } else {
          await playSong(state.activePlaylist[nextIdx], state.originalPlaylist, internalCall: true);
        }
      }
    } finally {
      _isBusy = false;
    }
  }

  Future<void> handlePrev() async {
    final now = DateTime.now();
    if (_lastActionTime != null && 
        now.difference(_lastActionTime!) < const Duration(milliseconds: 600)) {
      return;
    }
    _lastActionTime = now;

    if (_isBusy) return;
    _isBusy = true;

    try {
      if (state.activePlaylist.isEmpty || state.currentSong == null) return;
      
      // Restart song if it has played past 3 seconds
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
        await playSong(state.activePlaylist[prevIdx], state.originalPlaylist, internalCall: true);
      }
    } finally {
      _isBusy = false;
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

  Future<void> playPlaylistShuffled(List<Map<String, dynamic>> playlist, String playlistName) async {
    if (playlist.isEmpty) return;
    if (!state.shuffle) {
      toggleShuffle();
    }
    final rand = Random.secure();
    final startSong = playlist[rand.nextInt(playlist.length)];
    await playSong(startSong, playlist, playlistName: playlistName);
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
final showBottomNavBarProvider = StateProvider<bool>((ref) => false);
```

### 3. `app/lib/screens/setup_screen.dart`
[setup_screen.dart](file:///e:/PROJECT SONDRA/sondra/app/lib/screens/setup_screen.dart)
```dart
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'home_screen.dart';

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _checkExistingSession();
  }

  Future<void> _checkExistingSession() async {
    final api = ApiService();
    await api.init();
    if (api.baseUrl != null && api.token != null) {
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      }
    }
  }

  Future<void> _handleLogin() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();

    if (username.isEmpty || password.isEmpty) {
      setState(() {
        _isLoading = false;
        _errorMessage = "All fields are required.";
      });
      return;
    }

    final success = await ApiService().login(username, password);
    
    if (mounted) {
      setState(() {
        _isLoading = false;
      });

      if (success) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      } else {
        setState(() {
          _errorMessage = "Authentication failed. Check your credentials.";
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0E17),
      body: Center(
        child: SingleChildScrollView(
          padding: const Duration(milliseconds: 24) == Duration.zero 
              ? EdgeInsets.zero 
              : const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(
                Icons.music_note_rounded,
                color: Color(0xFF8B5CF6),
                size: 72,
              ),
              const SizedBox(height: 12),
              const Text(
                "Sondra Music",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                "Private Server Streaming App",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white60,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 40),
              
              if (_errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.redAccent.withOpacity(0.3)),
                  ),
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Username Field
              TextField(
                controller: _usernameController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: "Admin Username",
                  labelStyle: const TextStyle(color: Colors.white60),
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
              const SizedBox(height: 16),

              // Password Field
              TextField(
                controller: _passwordController,
                obscureText: true,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: "Password",
                  labelStyle: const TextStyle(color: Colors.white60),
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
              const SizedBox(height: 24),

              ElevatedButton(
                onPressed: _isLoading ? null : _handleLogin,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF8B5CF6),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        "Log In",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}
```

### 4. `app/lib/screens/home_screen.dart`
[home_screen.dart](file:///e:/PROJECT SONDRA/sondra/app/lib/screens/home_screen.dart)
```dart
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
import '../widgets/playlist_search_bar.dart';
import '../widgets/playlist_header.dart';

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
  bool _isLibraryExpanded = false;
  bool _isPersonalExpanded = false;
  bool _isOfflineExpanded = false;

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
                BottomNavigationBarItem(icon: Icon(Icons.music_note_rounded), label: "Song Pool"),
                BottomNavigationBarItem(icon: Icon(Icons.list_rounded), label: "Playlists"),
                BottomNavigationBarItem(icon: Icon(Icons.settings_rounded), label: "Settings"),
              ],
            )
          : null,
    );
  }

  // ── Desktop Layout: sidebar + content + optional right now-playing panel
  Widget _buildDesktopLayout(bool showNowPlayingWindows) {
    Widget content;
    if (_selectedPlaylistWindows != null) {
      final pl = _selectedPlaylistWindows!;
      final pSongs = List<Map<String, dynamic>>.from(pl["songs"] ?? []);
      content = _PlaylistDetailScreenInline(
        name: pl["name"] ?? "Playlist",
        songs: pSongs,
        onBack: () => setState(() => _selectedPlaylistWindows = null),
      );
    } else if (_selectedOfflinePlaylistWindows != null) {
      final plId = _selectedOfflinePlaylistWindows!['id'] as int;
      final pl = OfflineStorage().getPlaylist(plId) ?? _selectedOfflinePlaylistWindows!;
      content = OfflinePlaylistScreen(
        playlist: pl,
        onBack: () => setState(() => _selectedOfflinePlaylistWindows = null),
        onPlaylistChanged: () => setState(() {}),
        key: ValueKey(plId),
      );
    } else {
      content = IndexedStack(
        index: _currentIndex,
        children: [
          _buildHomeTab(),
          _buildLibraryTab(),
          const SizedBox.shrink(), // Index 2 placeholder since tab is removed on Windows
          _buildSettingsTab(),
        ],
      );
    }

    return Row(
      children: [
        _buildSidebar(),
        Expanded(child: content),
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
    final playlistsAsync = ref.watch(playlistsProvider);
    final allLocalPlaylists = OfflineStorage().getPlaylists();
    final personalPlaylists = allLocalPlaylists.where((p) => p['type'] == 'personal').toList();
    final offlinePlaylists = allLocalPlaylists.where((p) => p['type'] == 'offline').toList();

    return Container(
      width: 220,
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
          const SizedBox(height: 20),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sidebarItem(Icons.home_rounded, "Home", 0),
                  _sidebarItem(Icons.music_note_rounded, "Song Pool", 1),
                  const SizedBox(height: 12),
                  const Divider(color: Colors.white10, height: 1),
                  const SizedBox(height: 12),
                  
                  // My Library Playlists Dropdown
                  _buildDropdownHeader(
                    label: "My Library Playlists",
                    isExpanded: _isLibraryExpanded,
                    onToggle: () => setState(() => _isLibraryExpanded = !_isLibraryExpanded),
                  ),
                  if (_isLibraryExpanded)
                    playlistsAsync.when(
                      data: (lists) {
                        if (lists.isEmpty) {
                          return const Padding(
                            padding: EdgeInsets.only(left: 16, top: 4, bottom: 4),
                            child: Text("No playlists", style: TextStyle(color: Colors.white30, fontSize: 12)),
                          );
                        }
                        return Column(
                          children: lists.map<Widget>((pl) {
                            final isSelected = _selectedPlaylistWindows != null && _selectedPlaylistWindows!["name"] == pl["name"];
                            return _sidebarPlaylistItem(pl["name"] ?? "Unnamed", isSelected, () {
                              setState(() {
                                _selectedPlaylistWindows = pl;
                                _selectedOfflinePlaylistWindows = null;
                              });
                            });
                          }).toList(),
                        );
                      },
                      loading: () => const Padding(
                        padding: EdgeInsets.all(8.0),
                        child: Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF8B5CF6)))),
                      ),
                      error: (e, s) => Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Text("Error: $e", style: const TextStyle(color: Colors.redAccent, fontSize: 11)),
                      ),
                    ),
                  const SizedBox(height: 8),

                  // Personal Playlists Dropdown
                  _buildDropdownHeader(
                    label: "Personal Playlists",
                    isExpanded: _isPersonalExpanded,
                    onToggle: () => setState(() => _isPersonalExpanded = !_isPersonalExpanded),
                  ),
                  if (_isPersonalExpanded) ...[
                    ...personalPlaylists.map<Widget>((pl) {
                      final isSelected = _selectedOfflinePlaylistWindows != null && _selectedOfflinePlaylistWindows!["id"] == pl["id"];
                      return _sidebarPlaylistItem(pl["name"] ?? "Unnamed", isSelected, () {
                        setState(() {
                          _selectedOfflinePlaylistWindows = pl;
                          _selectedPlaylistWindows = null;
                        });
                      });
                    }),
                    _sidebarCreateNewButton("Create New", () => _createPersonalPlaylist()),
                  ],
                  const SizedBox(height: 8),

                  // Offline Playlists Dropdown
                  _buildDropdownHeader(
                    label: "Offline Playlists",
                    isExpanded: _isOfflineExpanded,
                    onToggle: () => setState(() => _isOfflineExpanded = !_isOfflineExpanded),
                  ),
                  if (_isOfflineExpanded) ...[
                    ...offlinePlaylists.map<Widget>((pl) {
                      final isSelected = _selectedOfflinePlaylistWindows != null && _selectedOfflinePlaylistWindows!["id"] == pl["id"];
                      return _sidebarPlaylistItem(pl["name"] ?? "Unnamed", isSelected, () {
                        setState(() {
                          _selectedOfflinePlaylistWindows = pl;
                          _selectedPlaylistWindows = null;
                        });
                      });
                    }),
                    _sidebarCreateNewButton("Create New", () => _createOfflinePlaylist()),
                  ],
                ],
              ),
            ),
          ),
          const Divider(color: Colors.white10, height: 1),
          _sidebarItem(Icons.settings_rounded, "Settings", 3),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _sidebarItem(IconData icon, String label, int index) {
    final selected = _selectedPlaylistWindows == null && _selectedOfflinePlaylistWindows == null && _currentIndex == index;
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
        onTap: () => setState(() {
          _currentIndex = index;
          _selectedPlaylistWindows = null;
          _selectedOfflinePlaylistWindows = null;
        }),
      ),
    );
  }

  Widget _buildDropdownHeader({required String label, required bool isExpanded, required VoidCallback onToggle}) {
    return InkWell(
      onTap: onToggle,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            AnimatedRotation(
              turns: isExpanded ? 0.25 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: const Icon(Icons.keyboard_arrow_right_rounded, color: Colors.white54, size: 18),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sidebarPlaylistItem(String name, bool isSelected, VoidCallback onTap) {
    return Container(
      margin: const EdgeInsets.only(left: 12, right: 6, top: 1, bottom: 1),
      decoration: BoxDecoration(
        color: isSelected ? const Color(0xFF8B5CF6).withOpacity(0.15) : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            children: [
              Icon(Icons.playlist_play_rounded, color: isSelected ? const Color(0xFF8B5CF6) : Colors.white30, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  name,
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.white60,
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sidebarCreateNewButton(String label, VoidCallback onTap) {
    return Container(
      margin: const EdgeInsets.only(left: 12, right: 6, top: 2, bottom: 2),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            children: [
              const Icon(Icons.add_rounded, color: Color(0xFF8B5CF6), size: 16),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: Color(0xFF8B5CF6),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _createOfflinePlaylist() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const CreateOfflinePlaylistScreen()),
    );
    if (created == true && mounted) setState(() {});
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
          const Text("Song Pool", style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          PlaylistSearchBar(
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
          const SizedBox(height: 16),
          Expanded(
            child: songsAsync.when(
              data: (songs) {
                final allSongs = List<Map<String, dynamic>>.from(songs);
                final query = _searchQuery.toLowerCase().trim();
                final filtered = query.isEmpty
                    ? allSongs
                    : allSongs.where((s) => PlaylistSearchBar.matchSong(s, query)).toList();

                if (filtered.isEmpty) {
                  if (query.isEmpty) {
                    return const Center(
                      child: Text("No songs in your library", style: TextStyle(color: Colors.white38)),
                    );
                  } else {
                    return const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text("🔍 No songs found", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                          SizedBox(height: 8),
                          Text("Try another title or artist.", style: TextStyle(color: Colors.white38, fontSize: 14)),
                        ],
                      ),
                    );
                  }
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
                        onTap: () => ref.read(playerProvider.notifier).playSong(song, filtered, playlistName: "Song Pool"),
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

class _PlaylistDetailScreen extends ConsumerStatefulWidget {
  final String name;
  final List<Map<String, dynamic>> songs;

  const _PlaylistDetailScreen({required this.name, required this.songs});

  @override
  ConsumerState<_PlaylistDetailScreen> createState() => _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends ConsumerState<_PlaylistDetailScreen> {
  String _searchQuery = "";
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchQuery.toLowerCase().trim();
    final filteredSongs = query.isEmpty
        ? widget.songs
        : widget.songs.where((s) => PlaylistSearchBar.matchSong(s, query)).toList();

    final playerState = ref.watch(playerProvider);
    final bottomPad = playerState.currentSong != null ? (Platform.isWindows ? 90.0 : 76.0) : 0.0;
    final hasSong = playerState.currentSong != null;

    return Scaffold(
      backgroundColor: const Color(0xFF08070D),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.only(left: 8, right: 8, top: 8, bottom: bottomPad + 8),
                itemCount: filteredSongs.length + 1,
                itemBuilder: (ctx, idx) {
                  if (idx == 0) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CommonPlaylistHeader(
                          name: widget.name,
                          songCount: widget.songs.length,
                          isShuffled: playerState.shuffle,
                          onPlayAll: widget.songs.isEmpty
                              ? null
                              : () {
                                  ref.read(playerProvider.notifier).playSong(widget.songs.first, widget.songs, playlistName: widget.name);
                                },
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
                          trailingActions: Platform.isWindows
                              ? PopupMenuButton<String>(
                                  icon: const Icon(Icons.more_horiz_rounded, color: Colors.white70),
                                  color: const Color(0xFF1C1A25),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  onSelected: (_) {},
                                  itemBuilder: (_) => [
                                    const PopupMenuItem(
                                      enabled: false,
                                      child: Text(
                                        "Synced from Google Drive",
                                        style: TextStyle(color: Colors.white54, fontSize: 13),
                                      ),
                                    ),
                                  ],
                                )
                              : null,
                        ),
                        if (widget.songs.isNotEmpty && filteredSongs.isEmpty)
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
                  final s = filteredSongs[idx - 1];
                  final isCurrent = playerState.currentSong?["id"] == s["id"];
                  return GestureDetector(
                    onSecondaryTapDown: (details) {
                      if (Platform.isWindows) {
                        SongOptionsButton.showRightClickMenu(context, details.globalPosition, ref, s);
                      }
                    },
                    child: ListTile(
                      onTap: () => ref.read(playerProvider.notifier).playSong(s, widget.songs, playlistName: widget.name),
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
            ),
            if (!Platform.isWindows && hasSong)
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
}

class _PlaylistDetailScreenInline extends ConsumerStatefulWidget {
  final String name;
  final List<Map<String, dynamic>> songs;
  final VoidCallback onBack;

  const _PlaylistDetailScreenInline({
    required this.name,
    required this.songs,
    required this.onBack,
  });

  @override
  ConsumerState<_PlaylistDetailScreenInline> createState() => _PlaylistDetailScreenInlineState();
}

class _PlaylistDetailScreenInlineState extends ConsumerState<_PlaylistDetailScreenInline> {
  String _searchQuery = "";
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchQuery.toLowerCase().trim();
    final filteredSongs = query.isEmpty
        ? widget.songs
        : widget.songs.where((s) => PlaylistSearchBar.matchSong(s, query)).toList();

    final playerState = ref.watch(playerProvider);
    final bottomPad = playerState.currentSong != null ? 90.0 : 0.0;

    return Scaffold(
      backgroundColor: const Color(0xFF08070D),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: widget.onBack,
        ),
        elevation: 0,
      ),
      body: ListView.builder(
        padding: EdgeInsets.only(left: 8, right: 8, top: 8, bottom: bottomPad + 8),
        itemCount: filteredSongs.length + 1,
        itemBuilder: (ctx, idx) {
          if (idx == 0) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CommonPlaylistHeader(
                  name: widget.name,
                  songCount: widget.songs.length,
                  isShuffled: playerState.shuffle,
                  onPlayAll: widget.songs.isEmpty
                      ? null
                      : () {
                          ref.read(playerProvider.notifier).playSong(widget.songs.first, widget.songs, playlistName: widget.name);
                        },
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
                  trailingActions: Platform.isWindows
                      ? PopupMenuButton<String>(
                          icon: const Icon(Icons.more_horiz_rounded, color: Colors.white70),
                          color: const Color(0xFF1C1A25),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          onSelected: (_) {},
                          itemBuilder: (_) => [
                            const PopupMenuItem(
                              enabled: false,
                              child: Text(
                                "Synced from Google Drive",
                                style: TextStyle(color: Colors.white54, fontSize: 13),
                              ),
                            ),
                          ],
                        )
                      : null,
                ),
                if (widget.songs.isNotEmpty && filteredSongs.isEmpty)
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
          final s = filteredSongs[idx - 1];
          final isCurrent = playerState.currentSong?["id"] == s["id"];
          return GestureDetector(
            onSecondaryTapDown: (details) {
              if (Platform.isWindows) {
                SongOptionsButton.showRightClickMenu(context, details.globalPosition, ref, s);
              }
            },
            child: ListTile(
              onTap: () => ref.read(playerProvider.notifier).playSong(s, widget.songs, playlistName: widget.name),
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
```

### 5. `app/lib/screens/now_playing_screen.dart`
[now_playing_screen.dart](file:///e:/PROJECT SONDRA/sondra/app/lib/screens/now_playing_screen.dart)
```dart
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/player_provider.dart';
import '../widgets/song_cover.dart';
import 'queue_screen.dart';

class NowPlayingScreen extends ConsumerWidget {
  const NowPlayingScreen({super.key});

  String _formatDuration(Duration d) {
    final mins = d.inMinutes;
    final secs = d.inSeconds % 60;
    return "${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}";
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playerState = ref.watch(playerProvider);
    final notifier = ref.read(playerProvider.notifier);
    
    if (playerState.currentSong == null) {
      return const SizedBox.shrink();
    }

    final song = playerState.currentSong!;

    if (Platform.isWindows) {
      return _buildWindowsLayout(context, ref, playerState, notifier, song);
    } else {
      return _buildAndroidLayout(context, ref, playerState, notifier, song);
    }
  }

  // ──────────────────────────────────────────────────────────────────
  // ANDROID MOBILE LAYOUT (Full-screen slide-up like Spotify)
  // ──────────────────────────────────────────────────────────────────
  Widget _buildAndroidLayout(BuildContext context, WidgetRef ref, PlayerState playerState, PlayerNotifier notifier, Map<String, dynamic> song) {
    return Scaffold(
      backgroundColor: const Color(0xFF08070D),
      body: SafeArea(
        child: Column(
          children: [
            // Top bar with down-arrow dismiss and playlist title
            SizedBox(
              height: 48,
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white, size: 28),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const Spacer(),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        "PLAYING FROM PLAYLIST",
                        style: TextStyle(color: Colors.white38, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1.0),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        playerState.activePlaylistName,
                        style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.queue_music_rounded, color: Colors.white70, size: 22),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const QueueScreen()),
                      );
                    },
                  ),
                ],
              ),
            ),
            // Album art takes ~50% of remaining space (flex:5)
            Expanded(
              flex: 5,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: SongCoverWidget(
                      song: song,
                      width: 400,
                      height: 400,
                      borderRadius: 16.0,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Song title & artist
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                children: [
                  Text(
                    song["title"] ?? "Unknown Title",
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    song["artist"] ?? "Unknown Artist",
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white60, fontSize: 16),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Seek bar with time labels
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                children: [
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 4,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                      activeTrackColor: const Color(0xFF8B5CF6),
                      inactiveTrackColor: Colors.white12,
                      thumbColor: const Color(0xFF8B5CF6),
                    ),
                    child: Slider(
                      min: 0.0,
                      max: playerState.duration.inMilliseconds.toDouble(),
                      value: playerState.position.inMilliseconds.toDouble().clamp(
                        0.0, 
                        playerState.duration.inMilliseconds.toDouble()
                      ),
                      onChanged: (value) {
                        notifier.seek(Duration(milliseconds: value.toInt()));
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(_formatDuration(playerState.position), style: const TextStyle(color: Colors.white38, fontSize: 11)),
                        Text(_formatDuration(playerState.duration), style: const TextStyle(color: Colors.white38, fontSize: 11)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // Controls
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  icon: Icon(Icons.shuffle_rounded, color: playerState.shuffle ? const Color(0xFF8B5CF6) : Colors.white70, size: 28),
                  onPressed: () => notifier.toggleShuffle(),
                  tooltip: playerState.shuffle ? "Disable Shuffle" : "Enable Shuffle",
                ),
                IconButton(
                  icon: const Icon(Icons.skip_previous_rounded, color: Colors.white, size: 36),
                  onPressed: () => notifier.handlePrev(),
                ),
                GestureDetector(
                  onTap: () => notifier.togglePlay(),
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: const BoxDecoration(
                      color: Color(0xFF8B5CF6),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: playerState.isBuffering
                          ? const SizedBox(
                              width: 28,
                              height: 28,
                              child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white),
                            )
                          : Icon(
                              playerState.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                              color: Colors.white,
                              size: 32,
                            ),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.skip_next_rounded, color: Colors.white, size: 36),
                  onPressed: () => notifier.handleNext(),
                ),
                IconButton(
                  icon: Icon(
                    playerState.repeat == "one" ? Icons.repeat_one_rounded : Icons.repeat_rounded,
                    color: playerState.repeat != "none" ? const Color(0xFF8B5CF6) : Colors.white38,
                    size: 24,
                  ),
                  onPressed: () => notifier.cycleRepeat(),
                ),
              ],
            ),
            SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
          ],
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────
  // WINDOWS DESKTOP LAYOUT (Embedded page view)
  // ──────────────────────────────────────────────────────────────────
  Widget _buildWindowsLayout(BuildContext context, WidgetRef ref, PlayerState playerState, PlayerNotifier notifier, Map<String, dynamic> song) {
    // Get list of upcoming tracks (excluding currently playing)
    final upcomingList = <Map<String, dynamic>>[];
    if (playerState.activePlaylist.isNotEmpty) {
      final currentIdx = playerState.activePlaylist.indexWhere((s) => s["id"] == song["id"]);
      if (currentIdx != -1) {
        for (int i = currentIdx + 1; i < playerState.activePlaylist.length; i++) {
          if (upcomingList.length < 3) {
            upcomingList.add(playerState.activePlaylist[i]);
          } else {
            break;
          }
        }
      }
    }

    return Scaffold(
      backgroundColor: const Color(0xFF08070D),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 24),
          onPressed: () {
            ref.read(showNowPlayingProvider.notifier).state = false;
          },
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Now Playing", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text("from: ${playerState.activePlaylistName}", style: const TextStyle(color: Colors.white38, fontSize: 11)),
          ],
        ),
      ),
      body: Row(
        children: [
          // Left side: Large Album Art / seeded gradient
          Expanded(
            flex: 5,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: SongCoverWidget(
                    song: song,
                    width: 320,
                    height: 320,
                    borderRadius: 16.0,
                  ),
                ),
              ),
            ),
          ),

          // Vertical divider line
          Container(width: 1, color: Colors.white.withOpacity(0.06), margin: const EdgeInsets.symmetric(vertical: 24)),

          // Right side: Player details, seek, queue
          Expanded(
            flex: 7,
            child: Padding(
              padding: const EdgeInsets.all(40.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Title & Artist
                  Text(
                    song["title"] ?? "Unknown Track",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    song["artist"] ?? "Unknown Artist",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white60, fontSize: 18),
                  ),
                  const SizedBox(height: 32),

                  // Controls Row (Shuffle, Prev, Play, Next, Repeat)
                  Row(
                    children: [
                      IconButton(
                        icon: Icon(
                          Icons.shuffle_rounded,
                          color: playerState.shuffle ? const Color(0xFF8B5CF6) : Colors.white70,
                          size: 26,
                        ),
                        onPressed: () => notifier.toggleShuffle(),
                        tooltip: playerState.shuffle ? "Disable Shuffle" : "Enable Shuffle",
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.skip_previous_rounded, color: Colors.white, size: 28),
                        onPressed: () => notifier.handlePrev(),
                      ),
                      const SizedBox(width: 12),
                      GestureDetector(
                        onTap: () => notifier.togglePlay(),
                        child: Container(
                          width: 48,
                          height: 48,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: playerState.isBuffering
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Color(0xFF111019),
                                    ),
                                  )
                                : Icon(
                                    playerState.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                    color: const Color(0xFF111019),
                                    size: 26,
                                  ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      IconButton(
                        icon: const Icon(Icons.skip_next_rounded, color: Colors.white, size: 28),
                        onPressed: () => notifier.handleNext(),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: Icon(
                          playerState.repeat == "one" ? Icons.repeat_one_rounded : Icons.repeat_rounded,
                          color: playerState.repeat != "none" ? const Color(0xFF8B5CF6) : Colors.white38,
                          size: 22,
                        ),
                        onPressed: () => notifier.cycleRepeat(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Seek Bar
                  Row(
                    children: [
                      Text(_formatDuration(playerState.position), style: const TextStyle(color: Colors.white38, fontSize: 12)),
                      Expanded(
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 3,
                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                            activeTrackColor: const Color(0xFF8B5CF6),
                            inactiveTrackColor: Colors.white12,
                            thumbColor: const Color(0xFF8B5CF6),
                          ),
                          child: Slider(
                            min: 0.0,
                            max: playerState.duration.inMilliseconds.toDouble(),
                            value: playerState.position.inMilliseconds.toDouble().clamp(
                              0.0, 
                              playerState.duration.inMilliseconds.toDouble()
                            ),
                            onChanged: (value) {
                              notifier.seek(Duration(milliseconds: value.toInt()));
                            },
                          ),
                        ),
                      ),
                      Text(_formatDuration(playerState.duration), style: const TextStyle(color: Colors.white38, fontSize: 12)),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Accessories (Volume Control & Queue icon)
                  Row(
                    children: [
                      const Icon(Icons.volume_up_rounded, color: Colors.white60, size: 20),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 120,
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 3,
                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
                            activeTrackColor: Colors.white,
                            inactiveTrackColor: Colors.white12,
                            thumbColor: Colors.white,
                          ),
                          child: Slider(
                            min: 0.0,
                            max: 1.0,
                            value: playerState.volume,
                            onChanged: (vol) => notifier.setVolume(vol),
                          ),
                        ),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const QueueScreen()),
                          );
                        },
                        behavior: HitTestBehavior.opaque,
                        child: Row(
                          children: [
                            const Icon(Icons.queue_music_rounded, color: Color(0xFF8B5CF6), size: 22),
                            const SizedBox(width: 8),
                            const Text("Open Full Queue", style: TextStyle(color: Color(0xFF8B5CF6), fontSize: 13, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),

                  // Next Up / Queue list section
                  if (upcomingList.isNotEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.04),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withOpacity(0.04)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Next Up",
                            style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                          ),
                          const SizedBox(height: 12),
                          ...upcomingList.map((nextSong) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8.0),
                              child: Row(
                                children: [
                                  SongCoverWidget(
                                    song: nextSong,
                                    width: 32,
                                    height: 32,
                                    borderRadius: 4.0,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          nextSong["title"] ?? "Unknown Track",
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                                        ),
                                        Text(
                                          nextSong["artist"] ?? "Unknown Artist",
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(color: Colors.white38, fontSize: 11),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────
// WINDOWS RIGHT PANEL — Compact now-playing overlay for right sidebar
// ──────────────────────────────────────────────────────────────────────
class NowPlayingRightPanel extends ConsumerWidget {
  final VoidCallback onClose;
  const NowPlayingRightPanel({super.key, required this.onClose});

  String _formatDuration(Duration d) {
    final mins = d.inMinutes;
    final secs = d.inSeconds % 60;
    return "${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}";
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playerState = ref.watch(playerProvider);
    final notifier = ref.read(playerProvider.notifier);

    if (playerState.currentSong == null) return const SizedBox.shrink();

    final song = playerState.currentSong!;

    // Next 3 upcoming tracks
    final upcomingList = <Map<String, dynamic>>[];
    if (playerState.activePlaylist.isNotEmpty) {
      final currentIdx = playerState.activePlaylist.indexWhere((s) => s["id"] == song["id"]);
      if (currentIdx != -1) {
        for (int i = currentIdx + 1; i < playerState.activePlaylist.length && upcomingList.length < 3; i++) {
          upcomingList.add(playerState.activePlaylist[i]);
        }
      }
    }

    return Container(
      width: 340,
      decoration: BoxDecoration(
        color: const Color(0xFF0E0C17),
        border: Border(left: BorderSide(color: Colors.white.withOpacity(0.06))),
      ),
      child: Column(
        children: [
          // Top bar: "Now Playing" label + close button
          SizedBox(
            height: 56,
            child: Row(
              children: [
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Now Playing", style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 2),
                      Text("from: ${playerState.activePlaylistName}", style: const TextStyle(color: Colors.white38, fontSize: 10), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white54, size: 22),
                  onPressed: onClose,
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Colors.white10),

          // Album art
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 32, 32, 16),
            child: AspectRatio(
              aspectRatio: 1,
              child: SongCoverWidget(song: song, width: 280, height: 280, borderRadius: 12),
            ),
          ),

          // Title + Artist
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(song["title"] ?? "Unknown Track",
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(song["artist"] ?? "Unknown Artist",
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white60, fontSize: 14)),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Seek bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                    activeTrackColor: const Color(0xFF8B5CF6),
                    inactiveTrackColor: Colors.white12,
                    thumbColor: const Color(0xFF8B5CF6),
                  ),
                  child: Slider(
                    min: 0.0,
                    max: playerState.duration.inMilliseconds.toDouble(),
                    value: playerState.position.inMilliseconds.toDouble().clamp(
                        0.0, playerState.duration.inMilliseconds.toDouble()),
                    onChanged: (value) => notifier.seek(Duration(milliseconds: value.toInt())),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_formatDuration(playerState.position), style: const TextStyle(color: Colors.white38, fontSize: 11)),
                      Text(_formatDuration(playerState.duration), style: const TextStyle(color: Colors.white38, fontSize: 11)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Controls (compact row)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: Icon(Icons.shuffle_rounded,
                    color: playerState.shuffle ? const Color(0xFF8B5CF6) : Colors.white70, size: 24),
                onPressed: () => notifier.toggleShuffle(),
                tooltip: playerState.shuffle ? "Disable Shuffle" : "Enable Shuffle",
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.skip_previous_rounded, color: Colors.white, size: 26),
                onPressed: () => notifier.handlePrev(),
              ),
              GestureDetector(
                onTap: () => notifier.togglePlay(),
                child: Container(
                  width: 44, height: 44,
                  decoration: const BoxDecoration(color: Color(0xFF8B5CF6), shape: BoxShape.circle),
                  child: Center(
                    child: playerState.isBuffering
                        ? const SizedBox(width: 18, height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Icon(playerState.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                            color: Colors.white, size: 24),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.skip_next_rounded, color: Colors.white, size: 26),
                onPressed: () => notifier.handleNext(),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: Icon(
                  playerState.repeat == "one" ? Icons.repeat_one_rounded : Icons.repeat_rounded,
                  color: playerState.repeat != "none" ? const Color(0xFF8B5CF6) : Colors.white38,
                  size: 20,
                ),
                onPressed: () => notifier.cycleRepeat(),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Volume
          Row(
            children: [
              const SizedBox(width: 24),
              const Icon(Icons.volume_up_rounded, color: Colors.white60, size: 18),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
                    activeTrackColor: Colors.white,
                    inactiveTrackColor: Colors.white12,
                    thumbColor: Colors.white,
                  ),
                  child: Slider(
                    min: 0.0, max: 1.0,
                    value: playerState.volume,
                    onChanged: (vol) => notifier.setVolume(vol),
                  ),
                ),
              ),
              const SizedBox(width: 24),
            ],
          ),

          const Spacer(),

          // Queue / Next Up
          if (upcomingList.isNotEmpty)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.04),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text("Next Up",
                          style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                      const Spacer(),
                      GestureDetector(
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const QueueScreen()),
                        ),
                        child: const Icon(Icons.queue_music_rounded, color: Color(0xFF8B5CF6), size: 18),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ...upcomingList.map((nextSong) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        SongCoverWidget(song: nextSong, width: 28, height: 28, borderRadius: 4),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(nextSong["title"] ?? "Unknown Track",
                                  maxLines: 1, overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                              Text(nextSong["artist"] ?? "Unknown Artist",
                                  maxLines: 1, overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: Colors.white38, fontSize: 10)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  )).toList(),
                ],
              ),
            ),

          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
```

### 6. `app/lib/screens/queue_screen.dart`
[queue_screen.dart](file:///e:/PROJECT SONDRA/sondra/app/lib/screens/queue_screen.dart)
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/player_provider.dart';
import '../widgets/song_cover.dart';
import 'dart:io' show Platform;
import '../widgets/song_options_menu.dart';

class QueueScreen extends ConsumerWidget {
  const QueueScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playerState = ref.watch(playerProvider);
    final notifier = ref.read(playerProvider.notifier);

    final currentSong = playerState.currentSong;
    final manualQueue = playerState.queue;

    // Calculate the remaining songs in the playlist that will play next
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
          // Section 1: Now Playing
          if (currentSong != null) ...[
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.only(left: 16.0, right: 16.0, top: 16.0, bottom: 8.0),
                child: Text("Now playing", style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.bold)),
              ),
            ),
            SliverToBoxAdapter(
              child: GestureDetector(
                onSecondaryTapDown: (details) {
                  if (Platform.isWindows) {
                    SongOptionsButton.showRightClickMenu(context, details.globalPosition, ref, currentSong);
                  }
                },
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
                  trailing: SongOptionsButton(song: currentSong),
                ),
              ),
            ),
          ],

          // Section 2: Next In Queue (Manually added - Drag and Drop + Swipe to remove)
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
                    child: GestureDetector(
                      onSecondaryTapDown: (details) {
                        if (Platform.isWindows) {
                          SongOptionsButton.showRightClickMenu(context, details.globalPosition, ref, s, inQueue: true, queueIndex: index);
                        }
                      },
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
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SongOptionsButton(song: s, inQueue: true, queueIndex: index),
                            const SizedBox(width: 8),
                            const Icon(Icons.drag_handle_rounded, color: Colors.white24),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ],

          // Section 3: Next Up (Remaining songs from active playlist)
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
                  return GestureDetector(
                    onSecondaryTapDown: (details) {
                      if (Platform.isWindows) {
                        SongOptionsButton.showRightClickMenu(context, details.globalPosition, ref, s);
                      }
                    },
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
                        style: const TextStyle(color: Colors.white60, fontSize: 14),
                      ),
                      subtitle: Text(
                        s["artist"] ?? "Unknown Artist",
                        style: const TextStyle(color: Colors.white38, fontSize: 11),
                      ),
                      trailing: SongOptionsButton(song: s),
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

### 7. `app/lib/screens/offline_playlist_screen.dart`
[offline_playlist_screen.dart](file:///e:/PROJECT SONDRA/sondra/app/lib/screens/offline_playlist_screen.dart)
```dart
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
import '../widgets/playlist_search_bar.dart';
import '../widgets/playlist_header.dart';

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
                                songCount: songs.length,
                                extraInfo: sizeStr,
                                isShuffled: playerState.shuffle,
                                onPlayAll: songs.isEmpty ? null : _playAll,
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
                                trailingActions: Platform.isWindows
                                    ? PopupMenuButton<String>(
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
                                      )
                                    : null,
                              );
                            },
                          )
                        else
                          CommonPlaylistHeader(
                            name: _playlist['name'] ?? '',
                            songCount: songs.length,
                            isShuffled: playerState.shuffle,
                            onPlayAll: songs.isEmpty ? null : _playAll,
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
                            trailingActions: Platform.isWindows
                                ? PopupMenuButton<String>(
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
                                    itemBuilder: (_) => _buildWindowsHeaderMenuItems(),
                                  )
                                : null,
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
                      onTap: () => _playSong(entry),
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

  void _playAll() {
    final songs = List<Map<String, dynamic>>.from(_playlist['songs'] ?? []);
    if (songs.isEmpty) return;
    _playSong(songs.first);
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
```

### 8. `app/lib/screens/create_offline_playlist_screen.dart`
[create_offline_playlist_screen.dart](file:///e:/PROJECT SONDRA/sondra/app/lib/screens/create_offline_playlist_screen.dart)
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
    _nameController.addListener(() => setState(() {}));
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
    final playlist = await storage.createPlaylist(name, type: 'offline');
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

### 9. `app/lib/services/api_service.dart`
[api_service.dart](file:///e:/PROJECT SONDRA/sondra/app/lib/services/api_service.dart)
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
          // Token expired or invalid
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

    // Connect to backend SSE event stream
    // Because standard EventSource is not in Dart, we use Dio with responseType=stream
    final sseUrl = "$baseUrl/api/events?token=$token";
    
    StreamSubscription? sub;
    sub = dio.get<ResponseBody>(
      sseUrl,
      options: Options(responseType: ResponseType.stream),
    ).asStream().listen((response) {
      final stream = response.data?.stream;
      if (stream == null) return;
      
      sseSubscription = stream.map((event) => event as List<int>).transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
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

  // API wrappers
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

### 10. `app/lib/services/audio_handler.dart`
[audio_handler.dart](file:///e:/PROJECT SONDRA/sondra/app/lib/services/audio_handler.dart)
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
  bool _isLoading = false;
  DateTime? _lastSmtcAction;

  // Callbacks hooked by the Riverpod notifier
  Future<void> Function()? onSkipToNext;
  Future<void> Function()? onSkipToPrevious;

  SondraAudioHandler() {
    // Forward playback states from just_audio to audio_service
    _player.playbackEventStream.map(_transformEvent).pipe(playbackState);

    // Initialize Windows System Media Transport Controls (SMTC)
    if (kIsWeb ? false : Platform.isWindows) {
      _initWindowsSmtc();
    }

    // Trigger audio session initialization immediately
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
    
    // Listen to button press streams
    _smtc!.buttonPressStream.listen((event) async {
      final now = DateTime.now();
      if (_lastSmtcAction != null && 
          now.difference(_lastSmtcAction!) < const Duration(milliseconds: 600)) {
        return;
      }
      _lastSmtcAction = now;

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

    // Keep SMTC playback status in sync with player playing state
    _player.playingStream.listen((playing) {
      _smtc?.setPlaybackStatus(
        playing ? PlaybackStatus.Playing : PlaybackStatus.Paused
      );
    });

    // Keep SMTC timeline in sync with player position/duration
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
    if (_isLoading) {
      try {
        await _player.stop();
      } catch (_) {}
    }
    _isLoading = true;
    try {
      await ensureInitialized();
    mediaItem.add(item);

    // Update SMTC Metadata on Windows
    if (_smtc != null) {
      _smtc!.setTitle(item.title);
      _smtc!.setArtist(item.artist ?? "Unknown Artist");
      if (item.album != null) {
        _smtc!.setAlbum(item.album!);
      }
    }

    try {
      // Check if this is a local file path (starts with / on Android or a drive letter on Windows)
      final isLocalFilePath = uri.startsWith('/') || 
          (uri.length > 2 && uri[1] == ':'); // Windows drive path like C:\...
      
      if (!kIsWeb && Platform.isAndroid) {
        // Android-specific: prevent cache collision and metadata mismatch
        if (isLocalFilePath) {
          await _player.setAudioSource(
            AudioSource.file(
              uri,
              tag: item,
            ),
          );
        } else {
          final parsedUri = Uri.parse(uri);
          if (parsedUri.scheme == 'file') {
            await _player.setAudioSource(
              AudioSource.file(
                parsedUri.toFilePath(),
                tag: item,
              ),
            );
          } else {
            await _player.setAudioSource(
              AudioSource.uri(
                parsedUri,
                tag: item,
              ),
            );
          }
        }
      } else {
        // Other platforms (Windows, etc.): do not modify existing behavior
        if (isLocalFilePath) {
          await _player.setAudioSource(AudioSource.file(uri));
        } else {
          final parsedUri = Uri.parse(uri);
          if (parsedUri.scheme == 'file') {
            await _player.setAudioSource(AudioSource.file(parsedUri.toFilePath()));
          } else {
            await _player.setAudioSource(
              AudioSource.uri(
                parsedUri,
                tag: item,
              ),
            );
          }
        }
      }
      _player.play();
    } finally {
      _isLoading = false;
    }
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
        MediaAction.play,
        MediaAction.pause,
        MediaAction.playPause,
        MediaAction.skipToNext,
        MediaAction.skipToPrevious,
        MediaAction.stop,
      },
      androidCompactActionIndices: const [0, 1, 3],
      processingState: const {
        ProcessingState.idle: AudioProcessingState.idle,
        ProcessingState.loading: AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready: AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[_player.processingState] ?? AudioProcessingState.idle,
      playing: _player.playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: event.currentIndex,
    );
  }
}
```

### 11. `app/lib/services/download_manager.dart`
[download_manager.dart](file:///e:/PROJECT SONDRA/sondra/app/lib/services/download_manager.dart)
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
```

### 12. `app/lib/services/offline_storage.dart`
[offline_storage.dart](file:///e:/PROJECT SONDRA/sondra/app/lib/services/offline_storage.dart)
```dart
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OfflineStorage {
  static final OfflineStorage _instance = OfflineStorage._();
  factory OfflineStorage() => _instance;
  OfflineStorage._();

  List<Map<String, dynamic>> _playlists = [];

  Future<String> get _storageDir async {
    try {
      final dir = await getApplicationSupportDirectory();
      final storage = Directory(p.join(dir.path, 'sondra_data'));
      if (!await storage.exists()) {
        await storage.create(recursive: true);
      }
      return storage.path;
    } catch (e) {
      print("Failed to use application support directory for storage, using temporary directory: $e");
      final tempDir = await getTemporaryDirectory();
      final storage = Directory(p.join(tempDir.path, 'sondra_data'));
      if (!await storage.exists()) {
        await storage.create(recursive: true);
      }
      return storage.path;
    }
  }

  Future<File> get _playlistsFile async {
    final d = await _storageDir;
    return File(p.join(d, 'offline_playlists.json'));
  }

  Future<String> get downloadsDir async {
    try {
      final dir = await getApplicationSupportDirectory();
      final dl = Directory(p.join(dir.path, 'sondra_downloads'));
      if (!await dl.exists()) {
        await dl.create(recursive: true);
      }
      return dl.path;
    } catch (e) {
      print("Failed to use application support directory for downloads, using temporary directory: $e");
      final tempDir = await getTemporaryDirectory();
      final dl = Directory(p.join(tempDir.path, 'sondra_downloads'));
      if (!await dl.exists()) {
        await dl.create(recursive: true);
      }
      return dl.path;
    }
  }

  Future<void> init() async {
    await checkVersionAndCleanup();
    final file = await _playlistsFile;
    if (await file.exists()) {
      final content = await file.readAsString();
      if (content.isNotEmpty) {
        _playlists = List<Map<String, dynamic>>.from(jsonDecode(content));
        // Reset any downloads stuck in 'downloading' state from a previous session
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

  Future<Map<String, dynamic>> createPlaylist(String name, {String type = 'offline'}) async {
    final id = DateTime.now().millisecondsSinceEpoch;
    final entry = <String, dynamic>{
      'id': id,
      'name': name,
      'type': type,
      'created_at': DateTime.now().toIso8601String(),
      'songs': <Map<String, dynamic>>[],
    };
    _playlists.insert(0, entry);
    await _save();
    return entry;
  }

  List<Map<String, dynamic>> getPlaylists() {
    return List.from(_playlists.map((pl) => {
      ...pl,
      'type': pl['type'] ?? 'offline',
    }));
  }

  Map<String, dynamic>? getPlaylist(int id) {
    final matches = _playlists.where((p) => p['id'] == id);
    if (matches.isEmpty) return null;
    final pl = matches.first;
    return {
      ...pl,
      'type': pl['type'] ?? 'offline',
    };
  }

  Future<void> addSongsToPlaylist(int playlistId, List<Map<String, dynamic>> songs) async {
    final idx = _playlists.indexWhere((p) => p['id'] == playlistId);
    if (idx == -1) return;
    final existing = _playlists[idx];
    final existingSongs = List<Map<String, dynamic>>.from(existing['songs'] ?? []);
    final existingSongIds = existingSongs.map((s) => s['song_id'] as int).toSet();

    for (final song in songs) {
      final sid = song['id'] as int;
      if (!existingSongIds.contains(sid)) {
        existingSongs.add({
          'id': DateTime.now().millisecondsSinceEpoch + existingSongs.length,
          'playlist_id': playlistId,
          'song_id': sid,
          'title': song['title'] ?? 'Unknown Track',
          'artist': song['artist'],
          'album': song['album'],
          'duration_seconds': song['duration_seconds'],
          'cover_url': song['cover_url'],
          'local_file_path': null,
          'status': 'notDownloaded',
          'progress': 0.0,
        });
      }
    }

    _playlists[idx] = {
      ...existing,
      'songs': existingSongs,
    };
    await _save();
  }

  Future<void> updateSongStatus(int playlistId, int songEntryId, String status, {String? filePath, double? progress}) async {
    final plIdx = _playlists.indexWhere((p) => p['id'] == playlistId);
    if (plIdx == -1) return;
    final songs = List<Map<String, dynamic>>.from(_playlists[plIdx]['songs'] ?? []);
    final songIdx = songs.indexWhere((s) => s['id'] == songEntryId);
    if (songIdx == -1) return;

    songs[songIdx]['status'] = status;
    if (filePath != null) songs[songIdx]['local_file_path'] = filePath;
    if (progress != null) songs[songIdx]['progress'] = progress;

    _playlists[plIdx]['songs'] = songs;
    await _save();
  }

  Future<void> deleteSong(int playlistId, int songEntryId) async {
    final plIdx = _playlists.indexWhere((p) => p['id'] == playlistId);
    if (plIdx == -1) return;
    final songs = List<Map<String, dynamic>>.from(_playlists[plIdx]['songs'] ?? []);
    songs.removeWhere((s) => s['id'] == songEntryId);
    _playlists[plIdx]['songs'] = songs;
    await _save();
  }

  Future<void> reorderSong(int playlistId, int fromIndex, int toIndex) async {
    final plIdx = _playlists.indexWhere((p) => p['id'] == playlistId);
    if (plIdx == -1) return;

    final songs = List<Map<String, dynamic>>.from(_playlists[plIdx]['songs'] ?? []);
    if (fromIndex < 0 || fromIndex >= songs.length || toIndex < 0 || toIndex >= songs.length) {
      return;
    }

    final item = songs.removeAt(fromIndex);
    songs.insert(toIndex, item);

    _playlists[plIdx]['songs'] = songs;
    await _save();
  }

  Future<void> deletePlaylist(int playlistId) async {
    _playlists.removeWhere((p) => p['id'] == playlistId);
    await _save();
  }

  Future<void> renamePlaylist(int playlistId, String newName) async {
    final idx = _playlists.indexWhere((p) => p['id'] == playlistId);
    if (idx == -1) return;
    _playlists[idx]['name'] = newName;
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

  Future<void> clearAllDownloads() async {
    try {
      final dPath = await downloadsDir;
      final downloadDir = Directory(dPath);
      if (await downloadDir.exists()) {
        await for (final entity in downloadDir.list(recursive: true)) {
          if (entity is File) {
            await entity.delete();
          }
        }
      }
      // Reset statuses in all playlists
      for (int i = 0; i < _playlists.length; i++) {
        final songs = List<Map<String, dynamic>>.from(_playlists[i]['songs'] ?? []);
        for (int j = 0; j < songs.length; j++) {
          songs[j]['status'] = 'notDownloaded';
          songs[j]['local_file_path'] = null;
          songs[j]['progress'] = 0.0;
        }
        _playlists[i]['songs'] = songs;
      }
      await _save();
    } catch (e) {
      print("Error clearing all downloads: $e");
    }
  }

  static Future<int> getCacheSize() async {
    int total = 0;
    try {
      final tempDir = await getTemporaryDirectory();
      // 1. just_audio_cache directory
      final justAudioCacheDir = Directory(p.join(tempDir.path, 'just_audio_cache'));
      if (await justAudioCacheDir.exists()) {
        await for (final entity in justAudioCacheDir.list(recursive: true)) {
          if (entity is File) {
            total += await entity.length();
          }
        }
      }
      // 2. sondra_cache_* files in tempDir
      await for (final entity in tempDir.list()) {
        if (entity is File && p.basename(entity.path).startsWith('sondra_cache_')) {
          total += await entity.length();
        }
      }
    } catch (e) {
      print("Error getting cache size: $e");
    }
    return total;
  }

  static Future<void> clearCache() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final justAudioCacheDir = Directory(p.join(tempDir.path, 'just_audio_cache'));
      if (await justAudioCacheDir.exists()) {
        await justAudioCacheDir.delete(recursive: true);
      }
      await for (final entity in tempDir.list()) {
        if (entity is File && p.basename(entity.path).startsWith('sondra_cache_')) {
          await entity.delete();
        }
      }
    } catch (e) {
      print("Error clearing cache: $e");
    }
  }

  static Future<int> getTotalDownloadSize() async {
    try {
      final dPath = await OfflineStorage().downloadsDir;
      final downloadDir = Directory(dPath);
      if (!await downloadDir.exists()) return 0;
      int total = 0;
      await for (final entity in downloadDir.list(recursive: true)) {
        if (entity is File) {
          total += await entity.length();
        }
      }
      return total;
    } catch (e) {
      print("Error getting total download size: $e");
      return 0;
    }
  }

  static Future<int> getPlaylistDownloadSize(List<dynamic> songs) async {
    try {
      final dPath = await OfflineStorage().downloadsDir;
      final downloadDir = Directory(dPath);
      if (!await downloadDir.exists()) return 0;
      int total = 0;
      for (final s in songs) {
        if (s['status'] == 'completed') {
          final songId = s['song_id'] ?? s['id'];
          final file = File(p.join(dPath, '$songId.mp3'));
          if (await file.exists()) {
            total += await file.length();
          }
        }
      }
      return total;
    } catch (e) {
      print("Error getting playlist download size: $e");
      return 0;
    }
  }

  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  Future<void> checkVersionAndCleanup() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      const String currentVersion = "1.0.0+1"; // Matches version in pubspec.yaml
      final storedVersion = prefs.getString("sondra_app_version");
      if (storedVersion != currentVersion) {
        print("Version mismatch: stored '$storedVersion', current '$currentVersion'. Performing full cleanup.");
        await clearAllData();
        await prefs.setString("sondra_app_version", currentVersion);
      }
    } catch (e) {
      print("Error in checkVersionAndCleanup: $e");
    }
  }

  Future<void> clearAllData() async {
    try {
      // 1. Delete all files in downloads directory
      final dPath = await downloadsDir;
      final downloadDir = Directory(dPath);
      if (await downloadDir.exists()) {
        await for (final entity in downloadDir.list(recursive: true)) {
          if (entity is File) {
            await entity.delete();
          }
        }
      }

      // 2. Delete offline_playlists.json
      final file = await _playlistsFile;
      if (await file.exists()) {
        await file.delete();
      }
      _playlists = []; // Clear in-memory cache

      // 3. Clear just_audio cache
      await clearCache();

      print("Full data cleanup completed.");
    } catch (e) {
      print("Error clearing all data: $e");
    }
  }
}
```

### 13. `app/lib/widgets/mini_player.dart`
[mini_player.dart](file:///e:/PROJECT SONDRA/sondra/app/lib/widgets/mini_player.dart)
```dart
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/player_provider.dart';
import 'song_cover.dart';

class MiniPlayer extends ConsumerStatefulWidget {
  final VoidCallback onTap;
  const MiniPlayer({super.key, required this.onTap});

  @override
  ConsumerState<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends ConsumerState<MiniPlayer> {
  bool _isFavorited = false;

  String _formatDuration(Duration d) {
    final mins = d.inMinutes;
    final secs = d.inSeconds % 60;
    return "${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}";
  }

  @override
  Widget build(BuildContext context) {
    final playerState = ref.watch(playerProvider);
    final notifier = ref.read(playerProvider.notifier);

    if (playerState.currentSong == null) {
      return const SizedBox.shrink();
    }

    final song = playerState.currentSong!;

    if (Platform.isWindows) {
      return _buildWindowsBar(context, playerState, notifier, song);
    } else {
      return _buildMobileBar(context, playerState, notifier, song);
    }
  }

  // ──────────────────────────────────────────────────────────────
  // ANDROID MOBILE BAR (compact: cover, title, play/pause, next)
  // ──────────────────────────────────────────────────────────────
  Widget _buildMobileBar(BuildContext context, PlayerState playerState, PlayerNotifier notifier, Map<String, dynamic> song) {
    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        height: 60,
        decoration: BoxDecoration(
          color: const Color(0xFF111019),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.06)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 12,
              offset: const Offset(0, 4),
            )
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            SongCoverWidget(
              song: song,
              width: 40,
              height: 40,
              borderRadius: 6.0,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    song["title"] ?? "Unknown Track",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    "${song["artist"] ?? "Unknown Artist"} · ${playerState.activePlaylistName}",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white54, fontSize: 10),
                  ),
                ],
              ),
            ),
            if (playerState.isBuffering)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: SizedBox(
                  width: 20, height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF8B5CF6)),
                ),
              ),
            IconButton(
              icon: Icon(
                Icons.shuffle_rounded,
                color: playerState.shuffle ? const Color(0xFF8B5CF6) : Colors.white70,
                size: 24,
              ),
              onPressed: () => notifier.toggleShuffle(),
              tooltip: playerState.shuffle ? "Disable Shuffle" : "Enable Shuffle",
            ),
            IconButton(
              icon: Icon(
                playerState.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: Colors.white, size: 26,
              ),
              onPressed: () => notifier.togglePlay(),
            ),
            IconButton(
              icon: const Icon(Icons.skip_next_rounded, color: Colors.white, size: 26),
              onPressed: () => notifier.handleNext(),
            ),
          ],
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────
  // WINDOWS DESKTOP BAR (three sections, Spotify-like)
  // ──────────────────────────────────────────────────────────────
  Widget _buildWindowsBar(BuildContext context, PlayerState playerState, PlayerNotifier notifier, Map<String, dynamic> song) {
    return Container(
      height: 72,
      decoration: const BoxDecoration(
        color: Color(0xFF111019),
        border: Border(top: BorderSide(color: Colors.white10, width: 0.5)),
      ),
      child: Row(
        children: [
          // ═══ LEFT SECTION: Cover, title, artist, heart ═══
          Expanded(
            flex: 3,
            child: Row(
              children: [
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: widget.onTap,
                  behavior: HitTestBehavior.opaque,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SongCoverWidget(song: song, width: 52, height: 52, borderRadius: 4.0),
                      const SizedBox(width: 10),
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 110,
                            child: Text(
                              song["title"] ?? "Unknown Track",
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                            ),
                          ),
                          const SizedBox(height: 2),
                          SizedBox(
                            width: 110,
                            child: Text(
                              song["artist"] ?? "Unknown Artist",
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 12),
                            ),
                          ),
                          const SizedBox(height: 2),
                          SizedBox(
                            width: 110,
                            child: Row(
                              children: [
                                const Icon(Icons.playlist_play_rounded, size: 10, color: Colors.white30),
                                const SizedBox(width: 2),
                                Expanded(
                                  child: Text(
                                    playerState.activePlaylistName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: Colors.white30, fontSize: 9),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: Icon(
                    _isFavorited ? Icons.favorite_rounded : Icons.favorite_outline_rounded,
                    color: _isFavorited ? const Color(0xFF8B5CF6) : Colors.white38,
                    size: 18,
                  ),
                  onPressed: () => setState(() => _isFavorited = !_isFavorited),
                  tooltip: _isFavorited ? "Remove from Favorites" : "Add to Favorites",
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  splashRadius: 16,
                ),
              ],
            ),
          ),

          // ═══ CENTRE SECTION: Controls + seek bar ═══
          Expanded(
            flex: 5,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Control buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _compactBtn(
                      icon: Icons.shuffle_rounded,
                      color: playerState.shuffle ? const Color(0xFF8B5CF6) : Colors.white70,
                      size: 20,
                      onPressed: () => notifier.toggleShuffle(),
                      tooltip: playerState.shuffle ? "Disable Shuffle" : "Enable Shuffle",
                    ),
                    const SizedBox(width: 4),
                    _compactBtn(
                      icon: Icons.skip_previous_rounded,
                      color: Colors.white,
                      size: 20,
                      onPressed: () => notifier.handlePrev(),
                    ),
                    const SizedBox(width: 10),
                    // Play/Pause — larger circular button
                    GestureDetector(
                      onTap: () => notifier.togglePlay(),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: playerState.isBuffering
                              ? const SizedBox(
                                  width: 16, height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF111019)),
                                )
                              : Icon(
                                  playerState.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                  color: const Color(0xFF111019),
                                  size: 22,
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    _compactBtn(
                      icon: Icons.skip_next_rounded,
                      color: Colors.white,
                      size: 20,
                      onPressed: () => notifier.handleNext(),
                    ),
                    const SizedBox(width: 4),
                    _compactBtn(
                      icon: playerState.repeat == "one" ? Icons.repeat_one_rounded : Icons.repeat_rounded,
                      color: playerState.repeat != "none" ? const Color(0xFF8B5CF6) : Colors.white38,
                      size: 18,
                      onPressed: () => notifier.cycleRepeat(),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                // Seek bar
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      Text(
                        _formatDuration(playerState.position),
                        style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 10, fontFeatures: [FontFeature.tabularFigures()]),
                      ),
                      Expanded(
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 4,
                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                            activeTrackColor: const Color(0xFF8B5CF6),
                            inactiveTrackColor: Colors.white12,
                            thumbColor: const Color(0xFF8B5CF6),
                          ),
                          child: Slider(
                            min: 0.0,
                            max: playerState.duration.inMilliseconds.toDouble(),
                            value: playerState.position.inMilliseconds.toDouble().clamp(0.0, playerState.duration.inMilliseconds.toDouble()),
                            onChanged: (value) => notifier.seek(Duration(milliseconds: value.toInt())),
                          ),
                        ),
                      ),
                      Text(
                        _formatDuration(playerState.duration),
                        style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 10, fontFeatures: [FontFeature.tabularFigures()]),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ═══ RIGHT SECTION: Queue, volume icon, volume slider ═══
          Expanded(
            flex: 3,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _compactBtn(
                  icon: Icons.queue_music_rounded,
                  color: Colors.white60,
                  size: 18,
                  onPressed: widget.onTap,
                ),
                const SizedBox(width: 4),
                Icon(
                  playerState.volume == 0 ? Icons.volume_mute_rounded : Icons.volume_up_rounded,
                  color: Colors.white60,
                  size: 16,
                ),
                const SizedBox(width: 4),
                SizedBox(
                  width: 90,
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 4,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                      activeTrackColor: Colors.white70,
                      inactiveTrackColor: Colors.white12,
                      thumbColor: Colors.white,
                    ),
                    child: Slider(
                      min: 0.0,
                      max: 1.0,
                      value: playerState.volume,
                      onChanged: (vol) => notifier.setVolume(vol),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _compactBtn({
    required IconData icon,
    required Color color,
    required double size,
    required VoidCallback onPressed,
    String? tooltip,
  }) {
    return SizedBox(
      width: 36,
      height: 36,
      child: IconButton(
        icon: Icon(icon, color: color, size: size),
        onPressed: onPressed,
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        splashRadius: 18,
      ),
    );
  }
}
```

### 14. `app/lib/widgets/song_cover.dart`
[song_cover.dart](file:///e:/PROJECT SONDRA/sondra/app/lib/widgets/song_cover.dart)
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

    // No cover_url → show gradient immediately without a network request.
    // This also covers offline songs that have no cover art.
    if (song["cover_url"] == null || (song["cover_url"] is String && (song["cover_url"] as String).isEmpty)) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: _buildPlaceholder(initial),
      );
    }

    final coverUrl = "${ApiService().baseUrl}/api/songs/${song["id"]}/cover?v=${song["id"]}";

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: CachedNetworkImage(
        imageUrl: coverUrl,
        cacheKey: "song_cover_${song["id"]}",
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
    
    // Consistent hash function
    int hash = 0;
    for (int i = 0; i < songTitle.length; i++) {
      hash = songTitle.codeUnitAt(i) + ((hash << 5) - hash);
    }
    
    // Vibrantly curated gradient palettes (analogous to Web Admin interface)
    final List<List<Color>> palettes = [
      [const Color(0xFFF43F5E), const Color(0xFFFB7185)], // Rose
      [const Color(0xFFEC4899), const Color(0xFFF472B6)], // Pink
      [const Color(0xFFD946EF), const Color(0xFFE879F9)], // Fuchsia
      [const Color(0xFFA855F7), const Color(0xFFC084FC)], // Purple
      [const Color(0xFF8B5CF6), const Color(0xFFA78BFA)], // Violet
      [const Color(0xFF6366F1), const Color(0xFF818CF8)], // Indigo
      [const Color(0xFF3B82F6), const Color(0xFF60A5FA)], // Blue
      [const Color(0xFF0EA5E9), const Color(0xFF38BDF8)], // Light Blue
      [const Color(0xFF06B6D4), const Color(0xFF22D3EE)], // Cyan
      [const Color(0xFF14B8A6), const Color(0xFF2DD4BF)], // Teal
      [const Color(0xFF10B981), const Color(0xFF34D399)], // Emerald
      [const Color(0xFF22C55E), const Color(0xFF4ADE80)], // Green
      [const Color(0xFFEAB308), const Color(0xFFFACC15)], // Yellow
      [const Color(0xFFF97316), const Color(0xFFFB923C)], // Orange
      [const Color(0xFFEF4444), const Color(0xFFF87171)], // Red
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

### 15. `app/lib/widgets/song_options_menu.dart`
[song_options_menu.dart](file:///e:/PROJECT SONDRA/sondra/app/lib/widgets/song_options_menu.dart)
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
  final VoidCallback? onPlaylistChanged;
  final int? playlistId;
  final int? songEntryId;

  const SongOptionsButton({
    super.key,
    required this.song,
    this.inQueue = false,
    this.queueIndex,
    this.onPlaylistChanged,
    this.playlistId,
    this.songEntryId,
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

  // Right-click helper called by the enclosing song row Gesture Detector
  static void showRightClickMenu(
    BuildContext context,
    Offset globalPos,
    WidgetRef ref,
    Map<String, dynamic> song, {
    bool inQueue = false,
    int? queueIndex,
    VoidCallback? onPlaylistChanged,
    int? playlistId,
    int? songEntryId,
  }) {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(globalPos, globalPos),
      Offset.zero & overlay.size,
    );

    final button = SongOptionsButton(
      song: song,
      inQueue: inQueue,
      queueIndex: queueIndex,
      onPlaylistChanged: onPlaylistChanged,
      playlistId: playlistId,
      songEntryId: songEntryId,
    );
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
      if (song['local_file_path'] != null && (song['local_file_path'] as String).isNotEmpty)
        _popupItem(
          icon: Icons.delete_outline_rounded,
          title: "Remove Local Download",
          color: Colors.redAccent,
          onTap: () async {
            final songId = song['id'] as int;
            await DownloadManager().deleteDownloadedFile(songId);
            await OfflineStorage().removeSongDownload(songId);
            if (onPlaylistChanged != null) {
              onPlaylistChanged!();
            }
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
      if (playlistId != null && songEntryId != null)
        _popupItem(
          icon: Icons.playlist_remove_rounded,
          title: "Remove from Playlist",
          color: Colors.redAccent,
          onTap: () async {
            await OfflineStorage().deleteSong(playlistId!, songEntryId!);
            if (onPlaylistChanged != null) {
              onPlaylistChanged!();
            }
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
              // Song Info Header
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
              if (song['local_file_path'] != null && (song['local_file_path'] as String).isNotEmpty)
                _bottomSheetItem(
                  context: ctx,
                  icon: Icons.delete_outline_rounded,
                  title: "Remove Local Download",
                  color: Colors.redAccent,
                  onTap: () async {
                    final songId = song['id'] as int;
                    await DownloadManager().deleteDownloadedFile(songId);
                    await OfflineStorage().removeSongDownload(songId);
                    if (onPlaylistChanged != null) {
                      onPlaylistChanged!();
                    }
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
              if (playlistId != null && songEntryId != null)
                _bottomSheetItem(
                  context: ctx,
                  icon: Icons.playlist_remove_rounded,
                  title: "Remove from Playlist",
                  color: Colors.redAccent,
                  onTap: () async {
                    await OfflineStorage().deleteSong(playlistId!, songEntryId!);
                    if (onPlaylistChanged != null) {
                      onPlaylistChanged!();
                    }
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
                // Create New Option
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
      // Find the song entry inside the updated playlist to get the correct entry ID for DownloadManager
      final pl = storage.getPlaylist(playlistId);
      if (pl != null) {
        final songs = List<Map<String, dynamic>>.from(pl['songs'] ?? []);
        final entry = songs.firstWhere((s) => s['song_id'] == song['id']);
        // Trigger download
        DownloadManager().downloadSong(playlistId, entry);
      }
    }

    if (onPlaylistChanged != null) {
      onPlaylistChanged!();
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

### 16. `app/lib/widgets/playlist_header.dart`
[playlist_header.dart](file:///e:/PROJECT SONDRA/sondra/app/lib/widgets/playlist_header.dart)
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class CommonPlaylistHeader extends ConsumerWidget {
  final String name;
  final int songCount;
  final String? extraInfo;
  final VoidCallback? onPlayAll;
  final bool isShuffled;
  final VoidCallback? onToggleShuffle;
  final Widget? trailingActions;
  final Widget? searchBar;

  const CommonPlaylistHeader({
    super.key,
    required this.name,
    required this.songCount,
    this.extraInfo,
    this.onPlayAll,
    required this.isShuffled,
    this.onToggleShuffle,
    this.trailingActions,
    this.searchBar,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                "$songCount song${songCount == 1 ? '' : 's'}",
                style: const TextStyle(color: Colors.white54, fontSize: 14),
              ),
              if (extraInfo != null && extraInfo!.isNotEmpty) ...[
                const SizedBox(width: 8),
                const Text("•", style: TextStyle(color: Colors.white30)),
                const SizedBox(width: 8),
                Text(
                  extraInfo!,
                  style: const TextStyle(
                    color: Color(0xFF10B981),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
          if (searchBar != null) ...[
            const SizedBox(height: 12),
            searchBar!,
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: onPlayAll,
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
                onPressed: onToggleShuffle,
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
              if (trailingActions != null) ...[
                const SizedBox(width: 12),
                trailingActions!,
              ],
            ],
          ),
        ],
      ),
    );
  }
}
```

### 17. `app/lib/widgets/playlist_search_bar.dart`
[playlist_search_bar.dart](file:///e:/PROJECT SONDRA/sondra/app/lib/widgets/playlist_search_bar.dart)
```dart
import 'package:flutter/material.dart';

class PlaylistSearchBar extends StatelessWidget {
  final TextEditingController controller;
  final String query;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  const PlaylistSearchBar({
    super.key,
    required this.controller,
    required this.query,
    required this.onChanged,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: "Search by title, artist...",
        hintStyle: const TextStyle(color: Colors.white24, fontSize: 14),
        prefixIcon: const Icon(Icons.search_rounded, color: Colors.white38),
        suffixIcon: query.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear_rounded, color: Colors.white38, size: 20),
                onPressed: onClear,
              )
            : null,
        filled: true,
        fillColor: Colors.white.withOpacity(0.05),
        contentPadding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 16.0),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF8B5CF6)),
        ),
      ),
      onChanged: onChanged,
    );
  }

  static bool matchSong(Map<String, dynamic> s, String query) {
    if (query.isEmpty) return true;
    final q = query.toLowerCase().trim();

    final title = (s['title'] ?? '').toString().toLowerCase();
    final artist = (s['artist'] ?? '').toString().toLowerCase();
    final album = (s['album'] ?? '').toString().toLowerCase();
    final genre = (s['genre'] ?? '').toString().toLowerCase();

    // Check filename from any path/URL/file ID field
    final filePath = (s['local_file_path'] ?? s['file_path'] ?? s['url'] ?? s['gdrive_file_id'] ?? '').toString();
    final filename = filePath.split(RegExp(r'[/\\]')).last.toLowerCase();

    // Tags check if custom tags field exists in the map
    final tagsStr = s.containsKey('tags') ? s['tags'].toString().toLowerCase() : '';

    return title.contains(q) ||
           artist.contains(q) ||
           album.contains(q) ||
           filename.contains(q) ||
           genre.contains(q) ||
           tagsStr.contains(q);
  }
}
```

### 18. `backend/main.py`
[main.py](file:///e:/PROJECT SONDRA/sondra/backend/main.py)
```python
import os
import asyncio
from contextlib import asynccontextmanager
from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.responses import RedirectResponse, JSONResponse, FileResponse
from fastapi.exceptions import HTTPException, RequestValidationError
from database import engine
import models
from routers import auth, songs, playlists, stream, sync, history

from dotenv import load_dotenv
load_dotenv(override=True)

# Create database tables if they do not exist
models.Base.metadata.create_all(bind=engine)

# Periodic Sync Daemon task definition
async def run_periodic_sync_daemon():
    # Allow uvicorn to fully bind ports before the first immediate sync trigger
    await asyncio.sleep(1)
    print("Sync Daemon: Triggering immediate startup library sync...")
    
    root_id = os.getenv("GDRIVE_ROOT_FOLDER_ID")
    from routers.sync import sync_manager, execute_sync_and_broadcast
    
    if root_id:
        try:
            await execute_sync_and_broadcast()
        except Exception as e:
            print(f"Sync Daemon Startup Sync Error: {e}")
    else:
        print("Sync Daemon: GDRIVE_ROOT_FOLDER_ID is not configured. Skipping startup sync.")
        
    while True:
        try:
            from dotenv import load_dotenv
            load_dotenv(override=True)
            
            interval_str = os.getenv("SYNC_INTERVAL_SECONDS", "900")
            interval = int(interval_str)
        except Exception:
            interval = 900

        await asyncio.sleep(interval)
        
        if not sync_manager.is_syncing and os.getenv("GDRIVE_ROOT_FOLDER_ID"):
            print("Sync Daemon: Triggering periodic background sync...")
            try:
                await execute_sync_and_broadcast()
            except Exception as e:
                print(f"Sync Daemon Error during sync: {e}")
        else:
            if not os.getenv("GDRIVE_ROOT_FOLDER_ID"):
                print("Sync Daemon: GDRIVE_ROOT_FOLDER_ID is not configured. Skipping sync.")

# FastAPI Lifespan manager
@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup actions
    sync_task = asyncio.create_task(run_periodic_sync_daemon())
    yield
    # Shutdown actions
    print("Sondra shutting down. Cancelling background tasks...")
    sync_task.cancel()
    try:
        await sync_task
    except asyncio.CancelledError:
        pass

# Initialize FastAPI app with lifespan context
app = FastAPI(
    title="Sondra Music Platform",
    description="Personal music streaming platform using Google Drive backend.",
    version="1.0.0",
    lifespan=lifespan
)

# Custom Global Error Handler Overrides
@app.exception_handler(HTTPException)
async def http_exception_handler(request: Request, exc: HTTPException):
    """Format HTTP exceptions into consistent JSON error format."""
    return JSONResponse(
        status_code=exc.status_code,
        content={"error": exc.detail},
        headers=exc.headers
    )

@app.exception_handler(RequestValidationError)
async def validation_exception_handler(request: Request, exc: RequestValidationError):
    """Format request validation exceptions into consistent JSON error format."""
    errors = exc.errors()
    if errors:
        first_err = errors[0]
        field_loc = ".".join(str(x) for x in first_err.get("loc", []))
        message = f"{first_err.get('msg', 'Validation error')} for field: {field_loc}"
    else:
        message = "Request validation failed"
        
    return JSONResponse(
        status_code=422,
        content={"error": message}
    )

# Configure CORS
cors_origins_str = os.getenv("CORS_ORIGINS", "")
if cors_origins_str:
    origins = [o.strip() for o in cors_origins_str.split(",") if o.strip()]
else:
    origins = [
        "http://localhost:5173",
        "http://127.0.0.1:5173",
        "http://localhost:8000",
        "http://127.0.0.1:8000",
    ]

app.add_middleware(
    CORSMiddleware,
    allow_origins=origins if origins else ["*"],
    allow_credentials=True if origins else False,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Register routers under standard routes and /api prefix
app.include_router(auth.router)
app.include_router(auth.router, prefix="/api")
app.include_router(songs.router, prefix="/api")
app.include_router(playlists.router, prefix="/api")
app.include_router(stream.router, prefix="/api")
app.include_router(sync.router, prefix="/api")
app.include_router(history.router)
app.include_router(history.router, prefix="/api")

@app.get("/events")
async def root_sse_events(request: Request):
    from routers.sync import sse_events_endpoint
    return await sse_events_endpoint(request)

@app.get("/api/events")
async def api_sse_events(request: Request):
    from routers.sync import sse_events_endpoint
    return await sse_events_endpoint(request)

@app.api_route("/health", methods=["GET", "HEAD"])
async def health():
    """Health check endpoint supporting GET and HEAD requests."""
    return {"status": "ok"}

@app.get("/")
def read_root():
    """API Root status endpoint."""
    return {"message": "Sondra Music Platform API", "status": "active"}
```

### 19. `backend/database.py`
[database.py](file:///e:/PROJECT SONDRA/sondra/backend/database.py)
```python
import os
from sqlalchemy import create_engine
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker

# Default SQLite database path
DB_PATH = os.path.join(os.path.dirname(__file__), "sondra.db")
SQLALCHEMY_DATABASE_URL = f"sqlite:///{DB_PATH}"

# Connect args needed for SQLite to enable multithreading checks compatibility
engine = create_engine(
    SQLALCHEMY_DATABASE_URL, connect_args={"check_same_thread": False}
)

SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

Base = declarative_base()

def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
```

### 20. `backend/models.py`
[models.py](file:///e:/PROJECT SONDRA/sondra/backend/models.py)
```python
from datetime import datetime
from sqlalchemy import Column, Integer, String, DateTime, ForeignKey
from sqlalchemy.orm import relationship
from database import Base

class Playlist(Base):
    __tablename__ = "playlists"

    id = Column(Integer, primary_key=True, index=True)
    gdrive_folder_id = Column(String, unique=True, index=True, nullable=False)
    name = Column(String, nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow)

    # Relationships
    songs = relationship("Song", back_populates="playlist", cascade="all, delete-orphan")


class Song(Base):
    __tablename__ = "songs"

    id = Column(Integer, primary_key=True, index=True)
    gdrive_file_id = Column(String, unique=True, index=True, nullable=False)
    title = Column(String, nullable=True)
    artist = Column(String, nullable=True)
    album = Column(String, nullable=True)
    genre = Column(String, nullable=True)
    duration_seconds = Column(Integer, nullable=True)
    cover_url = Column(String, nullable=True)
    playlist_id = Column(Integer, ForeignKey("playlists.id", ondelete="SET NULL"), nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow)

    # Relationships
    playlist = relationship("Playlist", back_populates="songs")
    history_entries = relationship("ListenHistory", back_populates="song", cascade="all, delete-orphan")


class ListenHistory(Base):
    __tablename__ = "listen_history"

    id = Column(Integer, primary_key=True, index=True)
    song_id = Column(Integer, ForeignKey("songs.id", ondelete="CASCADE"), nullable=False)
    listened_at = Column(DateTime, default=datetime.utcnow)
    position_seconds = Column(Integer, nullable=False, default=0)

    # Relationships
    song = relationship("Song", back_populates="history_entries")
```

### 21. `backend/gdrive.py`
[gdrive.py](file:///e:/PROJECT SONDRA/sondra/backend/gdrive.py)
```python
import os
import io
import base64
from google.auth.transport.requests import Request
from google.oauth2.credentials import Credentials
from google_auth_oauthlib.flow import InstalledAppFlow
from googleapiclient.discovery import build
from googleapiclient.http import MediaIoBaseDownload
from dotenv import load_dotenv

# Mutagen parsing
from mutagen import File as MutagenFile
from mutagen.easyid3 import EasyID3
from mutagen.mp3 import MP3
from mutagen.mp4 import MP4
from mutagen.flac import FLAC

load_dotenv()

SCOPES = ["https://www.googleapis.com/auth/drive.readonly"]
BACKEND_DIR = os.path.dirname(os.path.abspath(__file__))

def get_drive_service():
    """
    Returns an authenticated Google Drive API service client.
    Uses token.json if it exists and is valid, otherwise performs OAuth2 local server flow.
    """
    creds = None
    token_path = os.path.join(BACKEND_DIR, "token.json")
    
    # Load credentials.json path from env or use default
    creds_env = os.getenv("GDRIVE_OAUTH_CREDS", "credentials.json")
    if os.path.isabs(creds_env):
        creds_path = creds_env
    else:
        creds_path = os.path.join(BACKEND_DIR, creds_env)
        # Handle file name mismatch fallback automatically
        if not os.path.exists(creds_path):
            for name in ["credentials.json", "creds.json"]:
                p = os.path.join(BACKEND_DIR, name)
                if os.path.exists(p):
                    creds_path = p
                    break

    # 1. Try loading from GDRIVE_TOKEN_JSON environment variable first (for cloud services like Render)
    token_env = os.getenv("GDRIVE_TOKEN_JSON")
    if token_env:
        try:
            import json
            creds_info = json.loads(token_env)
            
            # Inject client_id and client_secret if missing, to allow token refresh on headless servers
            if "client_id" not in creds_info or "client_secret" not in creds_info:
                client_config = None
                creds_env_str = os.getenv("GDRIVE_CREDS_JSON")
                if creds_env_str:
                    try:
                        client_config = json.loads(creds_env_str)
                    except Exception:
                        pass
                if not client_config and os.path.exists(creds_path):
                    try:
                        with open(creds_path, "r") as f:
                            client_config = json.load(f)
                    except Exception:
                        pass
                
                if client_config:
                    key = "installed" if "installed" in client_config else "web"
                    if key in client_config:
                        creds_info["client_id"] = client_config[key]["client_id"]
                        creds_info["client_secret"] = client_config[key]["client_secret"]
            
            creds = Credentials.from_authorized_user_info(creds_info, SCOPES)
            print("Loaded Google OAuth credentials from GDRIVE_TOKEN_JSON environment variable.")
        except Exception as e:
            print(f"Error parsing GDRIVE_TOKEN_JSON from env: {e}")

    # 2. Fallback to loading token.json file
    if not creds and os.path.exists(token_path):
        try:
            # We also inject client_id and client_secret to local token.json if loaded to ensure refresh works locally
            with open(token_path, "r") as f:
                import json
                creds_info = json.load(f)
            
            if "client_id" not in creds_info or "client_secret" not in creds_info:
                client_config = None
                if os.path.exists(creds_path):
                    try:
                        with open(creds_path, "r") as f2:
                            client_config = json.load(f2)
                    except Exception:
                        pass
                if client_config:
                    key = "installed" if "installed" in client_config else "web"
                    if key in client_config:
                        creds_info["client_id"] = client_config[key]["client_id"]
                        creds_info["client_secret"] = client_config[key]["client_secret"]
            
            creds = Credentials.from_authorized_user_info(creds_info, SCOPES)
        except Exception as e:
            print(f"Error loading token.json: {e}")

    # 3. If no valid credentials, run Desktop flow or load client configs from env
    if not creds or not creds.valid:
        if creds and creds.expired and creds.refresh_token:
            try:
                creds.refresh(Request())
            except Exception as e:
                print(f"Error refreshing credentials: {e}")
                creds = None
                
        if not creds:
            # Check if we can load credentials configuration from environment variable
            creds_env_str = os.getenv("GDRIVE_CREDS_JSON")
            if creds_env_str:
                raise RuntimeError(
                    "Google Drive OAuth token has expired or is invalid, and could not be refreshed. "
                    "Please regenerate a fresh token.json locally (run start.bat) and update GDRIVE_TOKEN_JSON on Render."
                )
            else:
                if not os.path.exists(creds_path):
                    # Try fallback names if 'credentials.json' is configured but might be 'creds.json'
                    alternate_path = os.path.join(BACKEND_DIR, "creds.json")
                    if os.path.exists(alternate_path):
                        creds_path = alternate_path
                    else:
                        raise FileNotFoundError(
                            f"Google Drive credentials file not found at '{creds_path}'. "
                            "Please download Desktop client credentials JSON from Google Cloud Console, "
                            "save it in the backend folder, and configure GDRIVE_OAUTH_CREDS in your .env."
                        )
                
                flow = InstalledAppFlow.from_client_secrets_file(creds_path, SCOPES)
                # Starts local server and opens browser for desktop client authentication
                creds = flow.run_local_server(port=0)
            
            # Save token
            try:
                with open(token_path, "w") as token_file:
                    token_file.write(creds.to_json())
            except Exception as e:
                print(f"Could not save token.json file (read-only environment like Render): {e}")

    return build("drive", "v3", credentials=creds)


def get_access_token():
    """Retrieves current valid access token for proxy request usage."""
    # We call get_drive_service which refreshes the token.json if needed
    service = get_drive_service()
    return service._http.credentials.token


def list_playlist_folders(root_folder_id: str):
    """
    Returns a list of dictionaries containing folder information:
    [{"id": folder_gdrive_id, "name": folder_name}]
    Lists all folders directly inside the given root folder ID.
    """
    if not root_folder_id:
        return []
        
    # Programmatically extract the clean folder ID if a full URL was provided
    root_folder_id = root_folder_id.strip()
    if "drive.google.com" in root_folder_id:
        if "/folders/" in root_folder_id:
            root_folder_id = root_folder_id.split("/folders/")[-1]
        elif "/file/d/" in root_folder_id:
            root_folder_id = root_folder_id.split("/file/d/")[-1]
        root_folder_id = root_folder_id.split("?")[0].split("/")[0]
        
    service = get_drive_service()
    query = f"'{root_folder_id}' in parents and mimeType = 'application/vnd.google-apps.folder' and trashed = false"
    
    folders = []
    page_token = None
    while True:
        response = service.files().list(
            q=query,
            spaces="drive",
            fields="nextPageToken, files(id, name)",
            pageToken=page_token
        ).execute()
        
        folders.extend(response.get("files", []))
        page_token = response.get("nextPageToken", None)
        if not page_token:
            break
            
    return [{"id": f["id"], "name": f["name"]} for f in folders]


def list_songs_in_folder(folder_id: str):
    """
    Returns a list of songs directly inside the folder:
    [{"id": file_gdrive_id, "name": filename, "mimeType": ..., "size": ...}]
    Filters for mp3, flac, and m4a files.
    """
    service = get_drive_service()
    query = f"'{folder_id}' in parents and trashed = false"
    
    files = []
    page_token = None
    while True:
        response = service.files().list(
            q=query,
            spaces="drive",
            fields="nextPageToken, files(id, name, mimeType, size)",
            pageToken=page_token
        ).execute()
        
        files.extend(response.get("files", []))
        page_token = response.get("nextPageToken", None)
        if not page_token:
            break
            
    audio_extensions = (".mp3", ".flac", ".m4a")
    songs = []
    for f in files:
        name = f.get("name", "")
        name_lower = name.lower()
        mime = f.get("mimeType", "")
        
        is_audio = (
            name_lower.endswith(audio_extensions) or
            mime.startswith("audio/") or
            (mime == "application/octet-stream" and name_lower.endswith(audio_extensions))
        )
        if is_audio:
            songs.append({
                "id": f["id"],
                "name": name,
                "mimeType": mime,
                "size": int(f.get("size", 0))
            })
            
    return songs


def get_stream_url(gdrive_file_id: str):
    """
    Returns a direct streamable URL for Google Drive media.
    Our proxy stream endpoint forwards requests to this API endpoint.
    """
    return f"https://www.googleapis.com/drive/v3/files/{gdrive_file_id}?alt=media"


def get_file_metadata(gdrive_file_id: str):
    """
    Downloads the file temporarily, reads tags with Mutagen:
    (title, artist, album, genre, duration_seconds, embedded cover art as base64 data URI),
    deletes the temp file, and returns the dict.
    Falls back to the filename as title if tag metadata is missing.
    """
    service = get_drive_service()
    
    # 1. Fetch file name first
    file_info = service.files().get(fileId=gdrive_file_id, fields="name").execute()
    filename = file_info.get("name", "Unknown Track")
    
    # Setup temp path
    temp_dir = os.path.join(BACKEND_DIR, "cache", "temp")
    os.makedirs(temp_dir, exist_ok=True)
    temp_path = os.path.join(temp_dir, f"metadata_{gdrive_file_id}.tmp")
    
    metadata = {
        "title": None,
        "artist": "Unknown Artist",
        "album": "Unknown Album",
        "genre": "Unknown",
        "duration_seconds": 0,
        "cover_url": None  # stores base64 image data URI
    }
    
    # 2. Download file
    try:
        request = service.files().get_media(fileId=gdrive_file_id)
        with io.FileIO(temp_path, "wb") as fh:
            downloader = MediaIoBaseDownload(fh, request)
            done = False
            while not done:
                _, done = downloader.next_chunk()
                
        # 3. Read tags with mutagen
        audio = MutagenFile(temp_path)
        if audio is not None:
            if audio.info:
                metadata["duration_seconds"] = int(audio.info.length)
                
            if hasattr(audio, "tags") and audio.tags:
                if isinstance(audio, MP3):
                    try:
                        easy_audio = EasyID3(temp_path)
                        metadata["title"] = easy_audio.get("title", [None])[0]
                        metadata["artist"] = easy_audio.get("artist", [None])[0]
                        metadata["album"] = easy_audio.get("album", [None])[0]
                        metadata["genre"] = easy_audio.get("genre", [None])[0]
                    except Exception:
                        pass
                    
                    # APIC cover frame extraction
                    for tag_name in audio.tags.keys():
                        if tag_name.startswith("APIC"):
                            apic = audio.tags[tag_name]
                            if apic.data:
                                b64 = base64.b64encode(apic.data).decode("utf-8")
                                metadata["cover_url"] = f"data:{apic.mime};base64,{b64}"
                            break
                            
                elif isinstance(audio, MP4):
                    tags = audio.tags
                    metadata["title"] = tags.get("\xa9nam", [None])[0]
                    metadata["artist"] = tags.get("\xa9ART", [None])[0]
                    metadata["album"] = tags.get("\xa9alb", [None])[0]
                    metadata["genre"] = tags.get("\xa9gen", [None])[0]
                    
                    if "covr" in tags:
                        covr = tags["covr"]
                        if isinstance(covr, list) and len(covr) > 0:
                            b64 = base64.b64encode(bytes(covr[0])).decode("utf-8")
                            # MP4 covers can be jpg/png. Default to jpeg if unknown.
                            metadata["cover_url"] = f"data:image/jpeg;base64,{b64}"
                            
                elif isinstance(audio, FLAC):
                    tags = audio.tags
                    metadata["title"] = tags.get("title", [None])[0]
                    metadata["artist"] = tags.get("artist", [None])[0]
                    metadata["album"] = tags.get("album", [None])[0]
                    metadata["genre"] = tags.get("genre", [None])[0]
                    
                    if audio.pictures:
                        pic = audio.pictures[0]
                        if pic.data:
                            b64 = base64.b64encode(pic.data).decode("utf-8")
                            metadata["cover_url"] = f"data:{pic.mime};base64,{b64}"
                            
                else:
                    tags = audio.tags
                    if hasattr(tags, "get"):
                        metadata["title"] = tags.get("title", [None])[0]
                        metadata["artist"] = tags.get("artist", [None])[0]
                        metadata["album"] = tags.get("album", [None])[0]
                        metadata["genre"] = tags.get("genre", [None])[0]

    except Exception as e:
        print(f"Error reading tags from GDrive file {gdrive_file_id}: {e}")
    finally:
        # Clean up temp file
        if os.path.exists(temp_path):
            try:
                os.remove(temp_path)
            except Exception:
                pass

    # Clean text values
    for fld in ["title", "artist", "album", "genre"]:
        val = metadata[fld]
        if isinstance(val, list):
            metadata[fld] = str(val[0]) if val else None
        elif val is not None:
            metadata[fld] = str(val).strip()

    # Title fallback to filename without extension
    if not metadata["title"]:
        name_without_ext, _ = os.path.splitext(filename)
        if " - " in name_without_ext:
            parts = name_without_ext.split(" - ", 1)
            metadata["artist"] = parts[0].strip()
            metadata["title"] = parts[1].strip()
        else:
            metadata["title"] = name_without_ext.strip()
            
    # Ensure default values exist
    if not metadata["artist"]:
        metadata["artist"] = "Unknown Artist"
    if not metadata["album"]:
        metadata["album"] = "Unknown Album"
    if not metadata["genre"]:
        metadata["genre"] = "Unknown"

    return metadata


def get_direct_stream_url(gdrive_file_id: str) -> str:
    """
    Ensures the Google Drive file is temporarily accessible by anyone with the link
    and returns a direct streamable download link.
    """
    service = get_drive_service()
    try:
        # Check or create reader permission for "anyone"
        permission = {
            'type': 'anyone',
            'role': 'reader'
        }
        service.permissions().create(fileId=gdrive_file_id, body=permission).execute()
    except Exception as e:
        print(f"Error creating file sharing permission for {gdrive_file_id}: {e}")
    
    # Return the direct usercontent download URL format to bypass cross-origin redirect headers
    return f"https://drive.usercontent.google.com/download?id={gdrive_file_id}&export=download"
```

### 22. `backend/routers/auth.py`
[auth.py](file:///e:/PROJECT SONDRA/sondra/backend/routers/auth.py)
```python
import os
from datetime import datetime, timedelta
from typing import Optional
from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer, OAuth2PasswordRequestForm
from jose import JWTError, jwt
from pydantic import BaseModel
import secrets
from dotenv import load_dotenv

# Load env variables
load_dotenv(override=True)

ADMIN_USERNAME = os.getenv("ADMIN_USERNAME", "admin")
ADMIN_PASSWORD = os.getenv("ADMIN_PASSWORD", "adminpassword")
JWT_SECRET = os.getenv("JWT_SECRET", "sondrasecretkey1234567890")
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_DAYS = 30

router = APIRouter(prefix="/auth", tags=["Authentication"])

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/auth/login")

class LoginRequest(BaseModel):
    username: str
    password: str

class Token(BaseModel):
    access_token: str
    token_type: str

def create_access_token(data: dict, expires_delta: Optional[timedelta] = None):
    to_encode = data.copy()
    if expires_delta:
        expire = datetime.utcnow() + expires_delta
    else:
        expire = datetime.utcnow() + timedelta(days=ACCESS_TOKEN_EXPIRE_DAYS)
    to_encode.update({"exp": expire})
    encoded_jwt = jwt.encode(to_encode, JWT_SECRET, algorithm=ALGORITHM)
    return encoded_jwt

@router.post("/login", response_model=Token)
def login(login_data: LoginRequest):
    # Use secrets.compare_digest to protect against timing attacks
    if not (
        secrets.compare_digest(login_data.username, ADMIN_USERNAME)
        and secrets.compare_digest(login_data.password, ADMIN_PASSWORD)
    ):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect username or password",
            headers={"WWW-Authenticate": "Bearer"},
        )
    
    access_token = create_access_token(data={"sub": login_data.username})
    return {"access_token": access_token, "token_type": "bearer"}

# Form data login endpoint (needed for OAuth2PasswordBearer standard docs/testing)
@router.post("/login/form", response_model=Token, include_in_schema=False)
def login_form(form_data: OAuth2PasswordRequestForm = Depends()):
    if not (
        secrets.compare_digest(form_data.username, ADMIN_USERNAME)
        and secrets.compare_digest(form_data.password, ADMIN_PASSWORD)
    ):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect username or password",
            headers={"WWW-Authenticate": "Bearer"},
        )
    
    access_token = create_access_token(data={"sub": form_data.username})
    return {"access_token": access_token, "token_type": "bearer"}

def get_current_admin(token: str = Depends(oauth2_scheme)):
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Could not validate credentials",
        headers={"WWW-Authenticate": "Bearer"},
    )
    try:
        payload = jwt.decode(token, JWT_SECRET, algorithms=[ALGORITHM])
        username: str = payload.get("sub")
        if username is None or username != ADMIN_USERNAME:
            raise credentials_exception
        return username
    except JWTError:
        raise credentials_exception

@router.get("/me")
def get_me(username: str = Depends(get_current_admin)):
    return {"username": username, "role": "admin"}

class PasswordChangeRequest(BaseModel):
    current_password: str
    new_password: str

@router.patch("/password")
def change_password(
    payload: PasswordChangeRequest,
    username: str = Depends(get_current_admin)
):
    global ADMIN_PASSWORD
    # Perform safe digest comparison
    if not secrets.compare_digest(payload.current_password, ADMIN_PASSWORD):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Incorrect current password"
        )
    
    ADMIN_PASSWORD = payload.new_password
    
    # Save the updated password to .env file for persistence
    try:
        possible_paths = [
            os.path.join(os.path.dirname(os.path.dirname(__file__)), ".env"),
            os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(__file__))), ".env"),
        ]
        env_path = None
        for p in possible_paths:
            if os.path.exists(p):
                env_path = p
                break
        if not env_path:
            env_path = possible_paths[0]
            
        if os.path.exists(env_path):
            with open(env_path, "r", encoding="utf-8") as f:
                lines = f.readlines()
                
            updated = False
            for idx, line in enumerate(lines):
                if line.strip().startswith("ADMIN_PASSWORD="):
                    lines[idx] = f"ADMIN_PASSWORD={payload.new_password}\n"
                    updated = True
                    break
            
            if not updated:
                lines.append(f"\nADMIN_PASSWORD={payload.new_password}\n")
                
            with open(env_path, "w", encoding="utf-8") as f:
                f.writelines(lines)
            print("Successfully updated password in .env file.")
    except Exception as e:
        print(f"Error persisting new password to .env file: {e}")
        
    return {"message": "Password changed successfully"}
```

### 23. `backend/routers/songs.py`
[songs.py](file:///e:/PROJECT SONDRA/sondra/backend/routers/songs.py)
```python
import os
import base64
from fastapi import APIRouter, Depends, HTTPException, Response
from sqlalchemy.orm import Session, joinedload
from sqlalchemy import or_
from typing import List, Optional
from database import get_db
from routers.auth import get_current_admin
import models
from pydantic import BaseModel
from datetime import datetime

router = APIRouter(prefix="/songs", tags=["Songs"])

DEFAULT_COVER_SVG = """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 500 500" width="100%" height="100%">
  <defs>
    <linearGradient id="grad" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" style="stop-color:#1e3c72;stop-opacity:1" />
      <stop offset="100%" style="stop-color:#2a5298;stop-opacity:1" />
    </linearGradient>
  </defs>
  <rect width="100%" height="100%" fill="url(#grad)" />
  <circle cx="250" cy="250" r="120" fill="none" stroke="#ffffff" stroke-width="4" opacity="0.1" />
  <circle cx="250" cy="250" r="80" fill="none" stroke="#ffffff" stroke-width="4" opacity="0.2" />
  <path d="M220 180v140l100-70-100-70z" fill="#ffffff" opacity="0.8" />
  <text x="250" y="380" font-family="'Outfit', sans-serif" font-size="28" fill="#ffffff" text-anchor="middle" font-weight="bold" opacity="0.7">Sondra Music</text>
</svg>"""

# Nested playlist model
class PlaylistBriefResponse(BaseModel):
    id: int
    gdrive_folder_id: str
    name: str

    class Config:
        orm_mode = True

# Main song response model
class SongResponse(BaseModel):
    id: int
    gdrive_file_id: str
    title: Optional[str] = None
    artist: Optional[str] = None
    album: Optional[str] = None
    genre: Optional[str] = None
    duration_seconds: int = 0
    cover_url: Optional[str] = None
    playlist_id: Optional[int] = None
    created_at: datetime
    playlist: Optional[PlaylistBriefResponse] = None

    class Config:
        orm_mode = True

# Song metadata PATCH schema
class SongUpdate(BaseModel):
    title: Optional[str] = None
    artist: Optional[str] = None
    album: Optional[str] = None
    genre: Optional[str] = None

@router.get("", response_model=List[SongResponse])
def get_songs(
    db: Session = Depends(get_db),
    admin: str = Depends(get_current_admin)
):
    """Retrieves all songs, including joined playlist details."""
    return db.query(models.Song).options(joinedload(models.Song.playlist)).all()

@router.get("/search", response_model=List[SongResponse])
def search_songs(
    q: str,
    db: Session = Depends(get_db),
    admin: str = Depends(get_current_admin)
):
    """Performs case-insensitive searches in titles, artists, and albums."""
    search_filter = f"%{q}%"
    return db.query(models.Song)\
        .options(joinedload(models.Song.playlist))\
        .filter(
            or_(
                models.Song.title.ilike(search_filter),
                models.Song.artist.ilike(search_filter),
                models.Song.album.ilike(search_filter)
            )
        )\
        .all()

@router.get("/{song_id}", response_model=SongResponse)
def get_song(
    song_id: int,
    db: Session = Depends(get_db),
    admin: str = Depends(get_current_admin)
):
    """Retrieves a single song metadata by ID."""
    song = db.query(models.Song).options(joinedload(models.Song.playlist)).filter(models.Song.id == song_id).first()
    if not song:
        raise HTTPException(status_code=404, detail="Song not found")
    return song

@router.patch("/{song_id}", response_model=SongResponse)
def update_song_metadata(
    song_id: int,
    payload: SongUpdate,
    db: Session = Depends(get_db),
    admin: str = Depends(get_current_admin)
):
    """Updates metadata (title, artist, album, genre) locally in the SQLite DB."""
    song = db.query(models.Song).filter(models.Song.id == song_id).first()
    if not song:
        raise HTTPException(status_code=404, detail="Song not found")

    if payload.title is not None:
        song.title = payload.title
    if payload.artist is not None:
        song.artist = payload.artist
    if payload.album is not None:
        song.album = payload.album
    if payload.genre is not None:
        song.genre = payload.genre

    db.commit()
    db.refresh(song)
    
    # Reload with joined playlist info
    return db.query(models.Song).options(joinedload(models.Song.playlist)).filter(models.Song.id == song_id).first()

@router.get("/{song_id}/cover")
def get_song_cover(
    song_id: int,
    db: Session = Depends(get_db)
):
    """
    Serves the cover image of the song by decoding the base64 data stored in the DB.
    Does not require authentication to let the audio player fetch images easily in img elements.
    """
    song = db.query(models.Song).filter(models.Song.id == song_id).first()
    if song and song.cover_url and song.cover_url.startswith("data:"):
        try:
            # Format: "data:image/png;base64,iVBORw0KG..."
            header, base64_data = song.cover_url.split(",", 1)
            mime_type = header.split(";")[0].split(":")[1]
            image_bytes = base64.b64decode(base64_data)
            return Response(content=image_bytes, media_type=mime_type)
        except Exception as e:
            print(f"Error decoding cover art base64: {e}")
            
    # Return beautiful SVG fallback if no cover art is cached
    return Response(content=DEFAULT_COVER_SVG, media_type="image/svg+xml")
```

### 24. `backend/routers/playlists.py`
[playlists.py](file:///e:/PROJECT SONDRA/sondra/backend/routers/playlists.py)
```python
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session, joinedload
from typing import List, Optional
from database import get_db
from routers.auth import get_current_admin
import models
from pydantic import BaseModel
from datetime import datetime

router = APIRouter(prefix="/playlists", tags=["Playlists"])

# Song representation inside playlists list/detail
class PlaylistSongResponse(BaseModel):
    id: int
    gdrive_file_id: str
    title: Optional[str] = None
    artist: Optional[str] = None
    album: Optional[str] = None
    genre: Optional[str] = None
    duration_seconds: int = 0
    cover_url: Optional[str] = None
    playlist_id: Optional[int] = None
    created_at: datetime

    class Config:
        orm_mode = True

# Main playlist list structure
class PlaylistListResponse(BaseModel):
    id: int
    gdrive_folder_id: str
    name: str
    created_at: datetime
    songs: List[PlaylistSongResponse]
    song_count: int

    class Config:
        orm_mode = True

@router.get("", response_model=List[PlaylistListResponse])
def get_playlists(
    db: Session = Depends(get_db),
    admin: str = Depends(get_current_admin)
):
    """Retrieves all synced playlists with song lists and count metrics."""
    playlists = db.query(models.Playlist).options(joinedload(models.Playlist.songs)).all()
    for p in playlists:
        p.song_count = len(p.songs)
    return playlists


@router.get("/{playlist_id}", response_model=PlaylistListResponse)
def get_playlist(
    playlist_id: int,
    db: Session = Depends(get_db),
    admin: str = Depends(get_current_admin)
):
    """Retrieves a single playlist, sorting the songs array by created_at."""
    playlist = db.query(models.Playlist).filter(models.Playlist.id == playlist_id).first()
    if not playlist:
        raise HTTPException(status_code=404, detail="Playlist not found")

    # Query songs explicitly sorted by created_at
    sorted_songs = db.query(models.Song)\
        .filter(models.Song.playlist_id == playlist_id)\
        .order_by(models.Song.created_at.asc())\
        .all()

    playlist.songs = sorted_songs
    playlist.song_count = len(sorted_songs)
    return playlist
```

### 25. `backend/routers/sync.py`
[sync.py](file:///e:/PROJECT SONDRA/sondra/backend/routers/sync.py)
```python
import os
import asyncio
import json
from datetime import datetime
from typing import List, Optional, Set
from fastapi import APIRouter, Depends, BackgroundTasks, HTTPException, Request
from fastapi.responses import StreamingResponse
from sqlalchemy.orm import Session
from database import get_db, SessionLocal
from routers.auth import get_current_admin
import gdrive
import models
from googleapiclient.errors import HttpError

router = APIRouter(prefix="/sync", tags=["Sync"])

# Set of active SSE connection queues
sse_listeners: Set[asyncio.Queue] = set()

# In-memory sync status tracking
class SyncStateManager:
    def __init__(self):
        self.last_sync: Optional[datetime] = None
        self.is_syncing: bool = False
        
    def set_syncing(self, status: bool):
        self.is_syncing = status
        
    def mark_completed(self):
        self.last_sync = datetime.utcnow()
        self.is_syncing = False

sync_manager = SyncStateManager()

# In-memory sync log array tracking last 10 synchronization cycles
sync_logs = []

async def broadcast_sse_event(event_type: str, data: dict = None):
    """Broadcasts an SSE event to all connected listeners."""
    event = {"type": event_type}
    if data:
        event.update(data)
    
    # Send event to all client queues
    for queue in list(sse_listeners):
        try:
            await queue.put(event)
        except Exception:
            pass

def sync_library_logic():
    """
    Synchronous Google Drive library synchronization.
    Runs in a background thread to prevent event loop blockage.
    """
    db = SessionLocal()
    sync_manager.set_syncing(True)
    songs_added = 0
    songs_removed = 0
    try:
        root_id = os.getenv("GDRIVE_ROOT_FOLDER_ID")
        if not root_id:
            print("Sync Error: GDRIVE_ROOT_FOLDER_ID environment variable is missing.")
            return

        # 1. Fetch playlist folders inside Root Folder from Drive
        drive_folders = gdrive.list_playlist_folders(root_id)
        
        all_seen_folder_ids = set()
        all_seen_song_ids = set()

        # 2. For each folder: Upsert Playlist row
        for folder in drive_folders:
            folder_id = folder["id"]
            all_seen_folder_ids.add(folder_id)
            
            db_playlist = db.query(models.Playlist).filter(models.Playlist.gdrive_folder_id == folder_id).first()
            if not db_playlist:
                db_playlist = models.Playlist(
                    gdrive_folder_id=folder_id,
                    name=folder["name"]
                )
                db.add(db_playlist)
                db.commit()
                db.refresh(db_playlist)
            else:
                if db_playlist.name != folder["name"]:
                    db_playlist.name = folder["name"]
                    db.commit()

            # 3. For each playlist folder: Fetch songs
            songs = gdrive.list_songs_in_folder(folder_id)
            
            for song in songs:
                song_id = song["id"]
                all_seen_song_ids.add(song_id)
                
                # Check if song exists in DB
                db_song = db.query(models.Song).filter(models.Song.gdrive_file_id == song_id).first()
                if not db_song:
                    # 4. If song not in DB: Fetch metadata and insert
                    print(f"Sync: Downloading and extracting metadata for: {song['name']}")
                    meta = gdrive.get_file_metadata(song_id)
                    
                    new_song = models.Song(
                        gdrive_file_id=song_id,
                        title=meta["title"],
                        artist=meta["artist"],
                        album=meta["album"],
                        genre=meta["genre"],
                        duration_seconds=meta["duration_seconds"],
                        cover_url=meta["cover_url"], # base64 data URI
                        playlist_id=db_playlist.id
                    )
                    db.add(new_song)
                    db.commit()
                    songs_added += 1
                else:
                    # Make sure it's linked to the correct playlist (if moved)
                    if db_song.playlist_id != db_playlist.id:
                        db_song.playlist_id = db_playlist.id
                        db.commit()

        # 5. Delete Song rows whose gdrive_file_id no longer exists in Drive
        songs_removed = db.query(models.Song).filter(~models.Song.gdrive_file_id.in_(all_seen_song_ids)).delete(synchronize_session=False)
        
        # 6. Delete Playlist rows whose gdrive_folder_id no longer exists in Drive
        db.query(models.Playlist).filter(~models.Playlist.gdrive_folder_id.in_(all_seen_folder_ids)).delete(synchronize_session=False)
        
        db.commit()
        sync_manager.mark_completed()
        
        # Write successful run log
        sync_logs.append({
            "timestamp": datetime.utcnow().isoformat(),
            "songs_added": songs_added,
            "songs_removed": songs_removed,
            "errors": "None"
        })
        if len(sync_logs) > 10:
            sync_logs.pop(0)
            
        print("Sync completed successfully.")

    except HttpError as e:
        sync_manager.set_syncing(False)
        err_msg = "Google Drive API quota exceeded. Skipping sync." if (e.resp.status in [403, 429] and any(kw in str(e).lower() for kw in ["quota", "rate", "limit", "exhausted", "exceeded"])) else f"Sync failed with Google HTTP error: {e}"
        print(f"WARNING: {err_msg}" if "quota" in err_msg.lower() else err_msg)
        
        sync_logs.append({
            "timestamp": datetime.utcnow().isoformat(),
            "songs_added": songs_added,
            "songs_removed": 0,
            "errors": err_msg
        })
        if len(sync_logs) > 10:
            sync_logs.pop(0)
            
    except Exception as e:
        sync_manager.set_syncing(False)
        err_msg = f"Sync failed with error: {e}"
        print(err_msg)
        
        sync_logs.append({
            "timestamp": datetime.utcnow().isoformat(),
            "songs_added": songs_added,
            "songs_removed": 0,
            "errors": err_msg
        })
        if len(sync_logs) > 10:
            sync_logs.pop(0)
            
    finally:
        db.close()


async def execute_sync_and_broadcast():
    """Runs the sync in a thread pool and broadcasts SSE notification on completion."""
    await asyncio.to_thread(sync_library_logic)
    await broadcast_sse_event("library_updated")


@router.post("", status_code=202)
def trigger_sync(
    background_tasks: BackgroundTasks,
    admin: str = Depends(get_current_admin)
):
    """Manually triggers library synchronization in the background."""
    if sync_manager.is_syncing:
        raise HTTPException(status_code=409, detail="A synchronization is already running.")
        
    background_tasks.add_task(execute_sync_and_broadcast)
    return {"message": "Sync triggered successfully."}


@router.get("/status")
def get_sync_status(
    admin: str = Depends(get_current_admin)
):
    """Retrieves sync status and totals from the database."""
    db = SessionLocal()
    try:
        total_songs = db.query(models.Song).count()
        total_playlists = db.query(models.Playlist).count()
        
        try:
            interval = int(os.getenv("SYNC_INTERVAL_SECONDS", "900"))
        except Exception:
            interval = 900
            
        return {
            "last_sync": sync_manager.last_sync.isoformat() if sync_manager.last_sync else None,
            "total_songs": total_songs,
            "total_playlists": total_playlists,
            "is_syncing": sync_manager.is_syncing,
            "sync_interval_seconds": interval,
            "gdrive_root_folder_id": os.getenv("GDRIVE_ROOT_FOLDER_ID", "Not Configured")
        }
    finally:
        db.close()

@router.get("/logs")
def get_sync_logs(
    admin: str = Depends(get_current_admin)
):
    """Retrieves the last 10 sync log details."""
    return sync_logs


@router.get("/events")
async def sse_events_endpoint(request: Request):
    """
    SSE stream endpoint. Clients connect here to receive
    real-time event broadcasts such as library updates.
    """
    queue = asyncio.Queue()
    sse_listeners.add(queue)
    
    async def sse_generator():
        try:
            while True:
                if await request.is_disconnected():
                    break
                try:
                    event = await asyncio.wait_for(queue.get(), timeout=20.0)
                    yield f"data: {json.dumps(event)}\n\n"
                except asyncio.TimeoutError:
                    # Keep-alive ping
                    yield ": ping\n\n"
        finally:
            sse_listeners.remove(queue)
            
    return StreamingResponse(sse_generator(), media_type="text/event-stream")
```

### 26. `backend/routers/stream.py`
[stream.py](file:///e:/PROJECT SONDRA/sondra/backend/routers/stream.py)
```python
import io
import googleapiclient.http
from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.responses import StreamingResponse
from sqlalchemy.orm import Session
import httpx
from database import get_db
import gdrive
import models
from jose import jwt
from routers.auth import JWT_SECRET, ALGORITHM, ADMIN_USERNAME
from pydantic import BaseModel
from datetime import datetime
from typing import Optional

router = APIRouter(prefix="/stream", tags=["Streaming"])

class ListenLogRequest(BaseModel):
    position_seconds: int

def verify_token(request: Request):
    """Verifies token from either Authorization header or 'token' query parameter."""
    token = None
    auth_header = request.headers.get("authorization")
    if auth_header and auth_header.startswith("Bearer "):
        token = auth_header.split(" ")[1]
    else:
        token = request.query_params.get("token")

    if not token:
        raise HTTPException(status_code=401, detail="Authentication token required")

    try:
        payload = jwt.decode(token, JWT_SECRET, algorithms=[ALGORITHM])
        username: str = payload.get("sub")
        if username is None or username != ADMIN_USERNAME:
            raise HTTPException(status_code=401, detail="Invalid token username")
        return username
    except Exception:
        raise HTTPException(status_code=401, detail="Invalid or expired token")

@router.get("/{song_id}")
def stream_song(
    song_id: int,
    request: Request,
    db: Session = Depends(get_db),
    admin: str = Depends(verify_token)
):
    """
    Returns the backend proxy stream URL for a given song ID in a JSON payload.
    """
    song = db.query(models.Song).filter(models.Song.id == song_id).first()
    if not song:
        raise HTTPException(status_code=404, detail="Song not found")

    # Get the JWT token from headers or query params
    token = None
    auth_header = request.headers.get("authorization")
    if auth_header and auth_header.startswith("Bearer "):
        token = auth_header.split(" ")[1]
    else:
        token = request.query_params.get("token")

    # Construct the proxy URL using Render host domain if available
    host = request.headers.get("host", "localhost:8000")
    scheme = "https" if "render.com" in host or request.headers.get("x-forwarded-proto") == "https" else "http"
    proxy_url = f"{scheme}://{host}/api/stream/{song.id}/proxy?token={token}"

    return {"stream_url": proxy_url}

@router.get("/{song_id}/proxy")
async def stream_song_proxy(
    song_id: int,
    token: str,
    request: Request,
    db: Session = Depends(get_db)
):
    """
    Streams the song content from Google Drive acting as an authenticated proxy.
    Supports Range requests for seeking compatibility in browsers.
    """
    try:
        # Validate JWT token
        payload = jwt.decode(token, JWT_SECRET, algorithms=[ALGORITHM])
        username: str = payload.get("sub")
        if username is None or username != ADMIN_USERNAME:
            raise HTTPException(status_code=401, detail="Invalid token")
    except Exception:
        raise HTTPException(status_code=401, detail="Invalid token")

    song = db.query(models.Song).filter(models.Song.id == song_id).first()
    if not song:
        raise HTTPException(status_code=404, detail="Song not found")

    try:
        access_token = gdrive.get_access_token()
        url = f"https://www.googleapis.com/drive/v3/files/{song.gdrive_file_id}?alt=media"

        # Pass through the Range header if requested by the browser
        headers = {"Authorization": f"Bearer {access_token}"}
        client_range = request.headers.get("range")
        if client_range:
            headers["Range"] = client_range

        # Fetch file info from GDrive to get the actual filename and mimeType
        gdrive_name = ""
        gdrive_mime = ""
        async with httpx.AsyncClient() as meta_client:
            meta_res = await meta_client.get(
                f"https://www.googleapis.com/drive/v3/files/{song.gdrive_file_id}?fields=name,mimeType",
                headers={"Authorization": f"Bearer {access_token}"}
            )
            if meta_res.status_code == 200:
                gdrive_info = meta_res.json()
                gdrive_name = gdrive_info.get("name", "").lower()
                gdrive_mime = gdrive_info.get("mimeType", "")

        # Determine exact content type
        content_type = "audio/mpeg"
        if gdrive_mime and "audio" in gdrive_mime:
            content_type = gdrive_mime
        elif gdrive_name.endswith(".flac"):
            content_type = "audio/flac"
        elif gdrive_name.endswith(".m4a") or gdrive_name.endswith(".mp4"):
            content_type = "audio/mp4"
        elif gdrive_name.endswith(".wav"):
            content_type = "audio/wav"

        # Create an async client and stream the response
        client = httpx.AsyncClient()
        response = await client.send(
            client.build_request("GET", url, headers=headers),
            stream=True
        )

        if response.status_code not in [200, 206]:
            await response.aclose()
            await client.aclose()
            raise HTTPException(
                status_code=response.status_code, 
                detail=f"Google Drive API error: {response.status_code}"
            )

        # Set up response headers
        resp_headers = {
            "Accept-Ranges": "bytes",
            "Cache-Control": "no-cache",
        }
        if "content-range" in response.headers:
            resp_headers["Content-Range"] = response.headers["content-range"]
        if "content-length" in response.headers:
            resp_headers["Content-Length"] = response.headers["content-length"]

        async def stream_generator():
            try:
                async for chunk in response.aiter_bytes(chunk_size=1024*128):
                    yield chunk
            finally:
                await response.aclose()
                await client.aclose()

        return StreamingResponse(
            stream_generator(),
            status_code=response.status_code,
            media_type=content_type,
            headers=resp_headers
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Proxy streaming failed: {str(e)}")

@router.post("/{song_id}/listen")
def record_listen(
    song_id: int,
    log_data: ListenLogRequest,
    db: Session = Depends(get_db),
    admin: str = Depends(verify_token)
):
    """Records a listening session/position milestone in history."""
    song = db.query(models.Song).filter(models.Song.id == song_id).first()
    if not song:
        raise HTTPException(status_code=404, detail="Song not found")

    history_entry = models.ListenHistory(
        song_id=song.id,
        position_seconds=log_data.position_seconds,
        listened_at=datetime.utcnow()
    )
    db.add(history_entry)
    db.commit()
    db.refresh(history_entry)

    return {"message": "Listen event logged.", "id": history_entry.id}
```

### 27. `admin/src/api.ts`
[api.ts](file:///e:/PROJECT SONDRA/sondra/admin/src/api.ts)
```typescript
import axios from "axios";

const api = axios.create({
  baseURL: import.meta.env.VITE_API_URL || "https://sondra-backend.onrender.com",
});

// Request Interceptor: Attach JWT bearer token if available
api.interceptors.request.use(
  (config) => {
    const token = localStorage.getItem("sondra_token");
    if (token && config.headers) {
      config.headers.Authorization = `Bearer ${token}`;
    }
    return config;
  },
  (error) => {
    return Promise.reject(error);
  }
);

// Response Interceptor: Handle 401 Unauthorized globally
api.interceptors.response.use(
  (response) => response,
  (error) => {
    if (error.response && error.response.status === 401) {
      console.warn("Session expired. Logging out...");
      localStorage.removeItem("sondra_token");
      // Trigger redirect or page reload to prompt login
      window.location.reload();
    }
    return Promise.reject(error);
  }
);

export default api;
```

### 28. `admin/src/App.tsx`
[App.tsx](file:///e:/PROJECT SONDRA/sondra/admin/src/App.tsx)
```typescript
import { useState, useEffect, useRef } from "react";
import { 
  Play, 
  Pause, 
  SkipForward, 
  SkipBack, 
  Volume2, 
  VolumeX, 
  Search, 
  Music, 
  LayoutDashboard, 
  LogOut, 
  ListMusic,
  Settings as SettingsIcon,
  Edit2,
  X,
  Clock
} from "lucide-react";
import api from "./api";
import "./App.css";

// Interfaces
interface Playlist {
  id: number;
  gdrive_folder_id: string;
  name: string;
  created_at: string;
  song_count: number;
  songs: Song[];
}

interface Song {
  id: number;
  gdrive_file_id: string;
  title: string | null;
  artist: string | null;
  album: string | null;
  genre: string | null;
  duration_seconds: number;
  cover_url: string | null;
  playlist_id: number | null;
  created_at: string;
  playlist?: {
    id: number;
    gdrive_folder_id: string;
    name: string;
  } | null;
}

const getSeededColors = (title: string) => {
  const songTitle = title || "";
  let hash = 0;
  for (let i = 0; i < songTitle.length; i++) {
    hash = songTitle.charCodeAt(i) + ((hash << 5) - hash);
  }
  
  const palettes = [
    ["#F43F5E", "#FB7185"], // Rose
    ["#EC4899", "#F472B6"], // Pink
    ["#D946EF", "#E879F9"], // Fuchsia
    ["#A855F7", "#C084FC"], // Purple
    ["#8B5CF6", "#A78BFA"], // Violet
    ["#6366F1", "#818CF8"], // Indigo
    ["#3B82F6", "#60A5FA"], // Blue
    ["#0EA5E9", "#38BDF8"], // Light Blue
    ["#06B6D4", "#22D3EE"], // Cyan
    ["#14B8A6", "#2DD4BF"], // Teal
    ["#10B981", "#34D399"], // Emerald
    ["#22C55E", "#4ADE80"], // Green
    ["#EAB308", "#FACC15"], // Yellow
    ["#F97316", "#FB923C"], // Orange
    ["#EF4444", "#F87171"], // Red
  ];
  
  const index = Math.abs(hash) % palettes.length;
  return palettes[index];
};

const SongCover = ({ song, size = "40px", fontSize = "14px" }: { song: Song; size?: string; fontSize?: string }) => {
  const [hasError, setHasError] = useState(false);
  const title = song.title || "Unknown";
  const initial = title.charAt(0).toUpperCase() || "♫";

  const apiBase = import.meta.env.VITE_API_URL || "";
  const cleanApiBase = apiBase.endsWith("/") ? apiBase.slice(0, -1) : apiBase;
  const coverUrl = song.cover_url || `${cleanApiBase}/api/songs/${song.id}/cover`;

  if (hasError || !song.cover_url) {
    const colors = getSeededColors(title);
    return (
      <div 
        style={{
          width: size,
          height: size,
          borderRadius: "6px",
          background: `linear-gradient(135deg, ${colors[0]}, ${colors[1]})`,
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          color: "#ffffff",
          fontWeight: "bold",
          fontSize: fontSize,
          textShadow: "1px 2px 4px rgba(0,0,0,0.35)",
          flexShrink: 0,
        }}
      >
        {initial}
      </div>
    );
  }

  return (
    <img
      src={coverUrl}
      onError={() => setHasError(true)}
      style={{
        width: size,
        height: size,
        borderRadius: "6px",
        objectFit: "cover",
        flexShrink: 0,
      }}
      alt=""
    />
  );
};

function App() {
  const [token, setToken] = useState<string | null>(localStorage.getItem("sondra_token"));
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [loginError, setLoginError] = useState("");
  const [isLoading, setIsLoading] = useState(false);

  // Navigation state
  const [activeTab, setActiveTab] = useState<"dashboard" | "library" | "playlists" | "settings">("dashboard");
  
  // Data lists
  const [playlists, setPlaylists] = useState<Playlist[]>([]);
  const [songs, setSongs] = useState<Song[]>([]);
  const [filteredSongs, setFilteredSongs] = useState<Song[]>([]);

  // Search & Modals
  const [searchQuery, setSearchQuery] = useState("");
  const [editingSong, setEditingSong] = useState<Song | null>(null);
  const [editTitle, setEditTitle] = useState("");
  const [editArtist, setEditArtist] = useState("");
  const [editAlbum, setEditAlbum] = useState("");
  const [editGenre, setEditGenre] = useState("");
  const [expandedPlaylist, setExpandedPlaylist] = useState<Playlist | null>(null);

  // Settings states
  const [currentPassword, setCurrentPassword] = useState("");
  const [newPassword, setNewPassword] = useState("");
  const [passwordError, setPasswordError] = useState("");
  const [passwordSuccess, setPasswordSuccess] = useState("");

  // Persistent Player states
  const [currentSong, setCurrentSong] = useState<Song | null>(null);
  const [isPlaying, setIsPlaying] = useState(false);
  const [currentTime, setCurrentTime] = useState(0);
  const [duration, setDuration] = useState(0);
  const [volume, setVolume] = useState(0.8);
  const [isMuted, setIsMuted] = useState(false);
  const [shuffle] = useState(false);
  const [repeat] = useState<"none" | "one" | "all">("none");
  const [activePlaylistSongs, setActivePlaylistSongs] = useState<Song[]>([]);
  const [songQueue, setSongQueue] = useState<Song[]>([]);
  const [showQueue, setShowQueue] = useState(false);

  const audioRef = useRef<HTMLAudioElement | null>(null);

  const addToQueue = (song: Song) => {
    setSongQueue((prev) => [...prev, song]);
  };

  const removeFromQueue = (index: number) => {
    setSongQueue((prev) => prev.filter((_, i) => i !== index));
  };

  const clearQueue = () => {
    setSongQueue([]);
  };

  // Auth Handling
  const handleLogin = async (e: React.FormEvent) => {
    e.preventDefault();
    setLoginError("");
    setIsLoading(true);
    try {
      const response = await api.post("/auth/login", { username, password });
      const { access_token } = response.data;
      localStorage.setItem("sondra_token", access_token);
      setToken(access_token);
    } catch (err: any) {
      const errorMsg = err.response?.data?.error || "Invalid credentials.";
      setLoginError(errorMsg);
    } finally {
      setIsLoading(false);
    }
  };

  const handleLogout = () => {
    localStorage.removeItem("sondra_token");
    setToken(null);
    setCurrentSong(null);
    setIsPlaying(false);
    if (audioRef.current) {
      audioRef.current.pause();
    }
  };

  // Load Library Data
  const loadLibraryData = async () => {
    try {
      const [playlistsRes, songsRes] = await Promise.all([
        api.get("/api/playlists"),
        api.get("/api/songs"),
      ]);

      setPlaylists(playlistsRes.data);
      setSongs(songsRes.data);
      setFilteredSongs(songsRes.data);
    } catch (err: any) {
      console.error("Error loading library data:", err);
    }
  };

  useEffect(() => {
    if (token) {
      loadLibraryData();
    }
  }, [token]);

  // SSE Broadcast alerts — silently reloads library data on backend updates
  useEffect(() => {
    if (!token) return;

    const apiBase = import.meta.env.VITE_API_URL || "";
    const cleanApiBase = apiBase.endsWith("/") ? apiBase.slice(0, -1) : apiBase;
    const eventSource = new EventSource(`${cleanApiBase}/api/events?token=${token}`);

    eventSource.onmessage = (event) => {
      try {
        const data = JSON.parse(event.data);
        if (data.type === "library_updated") {
          loadLibraryData();
        }
      } catch (err) {
        console.error("SSE parse error:", err);
      }
    };

    eventSource.onerror = () => {
      console.warn("SSE disconnected. Reconnecting automatically...");
    };

    return () => {
      eventSource.close();
    };
  }, [token]);

  // Handle Search Filtering
  useEffect(() => {
    if (!token) return;

    const performSearch = async () => {
      if (!searchQuery) {
        setFilteredSongs(songs);
        return;
      }
      try {
        const res = await api.get(`/api/songs/search?q=${encodeURIComponent(searchQuery)}`);
        setFilteredSongs(res.data);
      } catch (err) {
        console.error("Search failed:", err);
      }
    };

    const timeout = setTimeout(performSearch, 300);
    return () => clearTimeout(timeout);
  }, [searchQuery, songs, token]);

  // PATCH Password
  const handlePasswordChange = async (e: React.FormEvent) => {
    e.preventDefault();
    setPasswordError("");
    setPasswordSuccess("");
    try {
      await api.patch("/auth/password", {
        current_password: currentPassword,
        new_password: newPassword,
      });
      setPasswordSuccess("Password changed successfully!");
      setCurrentPassword("");
      setNewPassword("");
    } catch (err: any) {
      const errorMsg = err.response?.data?.error || "Failed to change password.";
      setPasswordError(errorMsg);
    }
  };

  // Metadata editor modal trigger
  const handleOpenEditModal = (song: Song) => {
    setEditingSong(song);
    setEditTitle(song.title || "");
    setEditArtist(song.artist || "");
    setEditAlbum(song.album || "");
    setEditGenre(song.genre || "");
  };

  const handleSaveMetadata = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!editingSong) return;
    try {
      const res = await api.patch(`/api/songs/${editingSong.id}`, {
        title: editTitle,
        artist: editArtist,
        album: editAlbum,
        genre: editGenre,
      });
      
      // Update local states
      setSongs((prev) => prev.map((s) => (s.id === editingSong.id ? res.data : s)));
      setFilteredSongs((prev) => prev.map((s) => (s.id === editingSong.id ? res.data : s)));
      
      // Update current song if it's the one being modified
      if (currentSong?.id === editingSong.id) {
        setCurrentSong(res.data);
      }

      setEditingSong(null);
    } catch (err: any) {
      const errorMsg = err.response?.data?.error || "Failed to update metadata.";
      console.error(errorMsg);
    }
  };

  const handlePlaySong = (song: Song, playlistSongsList: Song[] = []) => {
    setCurrentSong(song);
    setIsPlaying(true);
    setActivePlaylistSongs(playlistSongsList.length > 0 ? playlistSongsList : songs);
    
    const apiBase = import.meta.env.VITE_API_URL || "";
    const cleanApiBase = apiBase.endsWith("/") ? apiBase.slice(0, -1) : apiBase;
    const streamUrl = `${cleanApiBase}/api/stream/${song.id}/proxy?token=${token}`;
    
    if (audioRef.current) {
      audioRef.current.src = streamUrl;
      audioRef.current.load();
      audioRef.current.play().catch((err) => console.error("Playback error:", err));
    }
  };

  const togglePlay = () => {
    if (!currentSong) {
      if (filteredSongs.length > 0) {
        handlePlaySong(filteredSongs[0]);
      }
      return;
    }
    
    if (isPlaying) {
      audioRef.current?.pause();
      setIsPlaying(false);
    } else {
      audioRef.current?.play().catch((err) => console.error("Playback resume error:", err));
      setIsPlaying(true);
    }
  };

  const handleAudioEnded = () => {
    handleNextSong();
  };

  const handleNextSong = () => {
    if (songQueue.length > 0) {
      const next = songQueue[0];
      setSongQueue((prev) => prev.slice(1));
      handlePlaySong(next, activePlaylistSongs);
      return;
    }

    if (activePlaylistSongs.length === 0) return;
    const currentIndex = activePlaylistSongs.findIndex((s) => s.id === currentSong?.id);
    let nextIndex = 0;

    if (shuffle) {
      nextIndex = Math.floor(Math.random() * activePlaylistSongs.length);
    } else if (currentIndex !== -1) {
      nextIndex = currentIndex + 1;
      if (nextIndex >= activePlaylistSongs.length) {
        if (repeat === "all") {
          nextIndex = 0;
        } else {
          setIsPlaying(false);
          return;
        }
      }
    }
    handlePlaySong(activePlaylistSongs[nextIndex], activePlaylistSongs);
  };

  const handlePrevSong = () => {
    if (activePlaylistSongs.length === 0 || !currentSong) return;

    if (currentTime > 3) {
      if (audioRef.current) audioRef.current.currentTime = 0;
      return;
    }

    const currentIndex = activePlaylistSongs.findIndex((s) => s.id === currentSong.id);
    let prevIndex = 0;

    if (shuffle) {
      prevIndex = Math.floor(Math.random() * activePlaylistSongs.length);
    } else if (currentIndex !== -1) {
      prevIndex = currentIndex - 1;
      if (prevIndex < 0) {
        if (repeat === "all") {
          prevIndex = activePlaylistSongs.length - 1;
        } else {
          prevIndex = 0;
        }
      }
    }
    handlePlaySong(activePlaylistSongs[prevIndex], activePlaylistSongs);
  };

  useEffect(() => {
    if (audioRef.current) {
      audioRef.current.volume = isMuted ? 0 : volume;
    }
  }, [volume, isMuted]);

  const onTimeUpdate = () => {
    if (audioRef.current) {
      setCurrentTime(audioRef.current.currentTime);
    }
  };

  const onLoadedMetadata = () => {
    if (audioRef.current) {
      setDuration(audioRef.current.duration);
    }
  };

  const formatTime = (seconds: number) => {
    if (isNaN(seconds)) return "00:00";
    const mins = Math.floor(seconds / 60);
    const secs = Math.floor(seconds % 60);
    return `${mins.toString().padStart(2, "0")}:${secs.toString().padStart(2, "0")}`;
  };

  if (!token) {
    return (
      <div className="login-container">
        <div className="glass-card login-card">
          <div className="login-logo flex-center">
            <Music color="#ffffff" size={28} />
          </div>
          <h1 className="login-title">Sondra</h1>
          <p className="login-subtitle">Personal Admin Music Streaming</p>
          
          <form className="login-form" onSubmit={handleLogin}>
            {loginError && <div className="login-error">{loginError}</div>}
            
            <div className="form-group">
              <label className="form-label">Admin Username</label>
              <input
                type="text"
                placeholder="Enter username"
                value={username}
                onChange={(e) => setUsername(e.target.value)}
                required
              />
            </div>
            
            <div className="form-group">
              <label className="form-label">Password</label>
              <input
                type="password"
                placeholder="Enter password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                required
              />
            </div>
            
            <button type="submit" className="btn-primary" style={{ marginTop: "12px" }} disabled={isLoading}>
              {isLoading ? "Authenticating..." : "Log In"}
            </button>
          </form>
        </div>
      </div>
    );
  }

  return (
    <div className="app-container">
      <audio
        ref={audioRef}
        onTimeUpdate={onTimeUpdate}
        onLoadedMetadata={onLoadedMetadata}
        onEnded={handleAudioEnded}
      />

      {/* Sidebar Layout */}
      <aside className="sidebar glass" style={{ width: "220px" }}>
        <div className="logo-container">
          <div className="logo-icon flex-center">
            <Music color="#ffffff" size={20} />
          </div>
          <span className="logo-text">Sondra</span>
        </div>

        <nav className="nav-menu">
          <button
            className={`nav-item ${activeTab === "dashboard" ? "active" : ""}`}
            onClick={() => setActiveTab("dashboard")}
          >
            <LayoutDashboard size={18} />
            Dashboard
          </button>
          <button
            className={`nav-item ${activeTab === "library" ? "active" : ""}`}
            onClick={() => setActiveTab("library")}
          >
            <Music size={18} />
            Library
          </button>
          <button
            className={`nav-item ${activeTab === "playlists" ? "active" : ""}`}
            onClick={() => {
              setActiveTab("playlists");
              setExpandedPlaylist(null);
            }}
          >
            <ListMusic size={18} />
            Playlists
          </button>
          <button
            className={`nav-item ${activeTab === "settings" ? "active" : ""}`}
            onClick={() => setActiveTab("settings")}
          >
            <SettingsIcon size={18} />
            Settings
          </button>
        </nav>

        <button className="nav-item" onClick={handleLogout} style={{ marginTop: "auto", color: "var(--color-danger)" }}>
          <LogOut size={18} />
          Logout
        </button>
      </aside>

      {/* Main Panel Area */}
      <main className="main-content">
        <div className="top-bar">
          <h2 style={{ fontSize: "22px" }}>
            {activeTab === "dashboard" && "Dashboard"}
            {activeTab === "library" && "Music Library"}
            {activeTab === "playlists" && "Playlists"}
            {activeTab === "settings" && "Platform Settings"}
          </h2>
          <div className="user-profile">
            <span style={{ fontSize: "14px", fontWeight: 500 }}>Admin Portal</span>
            <div className="avatar flex-center">A</div>
          </div>
        </div>

        <div className="content-pane">
          {/* Dashboard Tab */}
          {activeTab === "dashboard" && (
            <div>
              <div className="stats-grid">
                <div className="glass-card stat-card">
                  <div className="stat-icon flex-center">
                    <Music size={24} />
                  </div>
                  <div>
                    <div className="stat-value">{songs.length}</div>
                    <div className="stat-label">Total Songs</div>
                  </div>
                </div>

                <div className="glass-card stat-card">
                  <div className="stat-icon flex-center">
                    <ListMusic size={24} />
                  </div>
                  <div>
                    <div className="stat-value">{playlists.length}</div>
                    <div className="stat-label">Total Playlists</div>
                  </div>
                </div>

              </div>
            </div>
          )}

          {/* Library Tab */}
          {activeTab === "library" && (
            <div>
              <div className="search-container">
                <div className="search-input-wrapper">
                  <Search size={18} className="search-icon" />
                  <input
                    type="text"
                    placeholder="Search by title, artist, album..."
                    value={searchQuery}
                    onChange={(e) => setSearchQuery(e.target.value)}
                  />
                </div>
              </div>

              <div className="glass-card" style={{ overflow: "hidden" }}>
                <table className="song-table">
                  <thead>
                    <tr>
                      <th>Title</th>
                      <th>Artist</th>
                      <th>Album</th>
                      <th>Folder Playlist (Read Only)</th>
                      <th><Clock size={14} /></th>
                      <th>Edit</th>
                    </tr>
                  </thead>
                  <tbody>
                    {filteredSongs.map((song) => (
                      <tr key={song.id} className="song-row">
                        <td onClick={() => handlePlaySong(song, filteredSongs)}>
                          <div className="song-info-cell">
                            <SongCover song={song} size="40px" fontSize="14px" />
                            <span className="song-title">{song.title}</span>
                          </div>
                        </td>
                        <td onClick={() => handlePlaySong(song, filteredSongs)}>
                          <span className="song-artist">{song.artist}</span>
                        </td>
                        <td onClick={() => handlePlaySong(song, filteredSongs)}>
                          <span className="song-album-cell">{song.album}</span>
                        </td>
                        <td>
                          <span style={{ color: "var(--color-primary)", fontWeight: 500 }}>
                            {song.playlist?.name || "Root Folder"}
                          </span>
                        </td>
                        <td>
                          <span className="song-duration">{formatTime(song.duration_seconds)}</span>
                        </td>
                        <td>
                          <div className="flex-center" style={{ gap: "8px" }}>
                            <button
                              onClick={() => addToQueue(song)}
                              className="edit-metadata-btn flex-center"
                              style={{ color: "var(--color-primary)", padding: "6px" }}
                              title="Add to Queue"
                            >
                              <ListMusic size={14} />
                            </button>
                            <button
                              onClick={() => handleOpenEditModal(song)}
                              className="edit-metadata-btn flex-center"
                              style={{ color: "var(--text-muted)", padding: "6px" }}
                            >
                              <Edit2 size={14} />
                            </button>
                          </div>
                        </td>
                      </tr>
                    ))}
                    {filteredSongs.length === 0 && (
                      <tr>
                        <td colSpan={6} style={{ textAlign: "center", padding: "40px", color: "var(--text-muted)" }}>
                          No songs found. Add music folders in Google Drive to populate the library.
                        </td>
                      </tr>
                    )}
                  </tbody>
                </table>
              </div>
            </div>
          )}

          {/* Playlists Tab */}
          {activeTab === "playlists" && (
            <div>
              {!expandedPlaylist ? (
                <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(280px, 1fr))", gap: "24px" }}>
                  {playlists.map((playlist) => (
                    <div
                      key={playlist.id}
                      className="glass-card playlist-grid-card"
                      onClick={() => setExpandedPlaylist(playlist)}
                      style={{ cursor: "pointer", padding: "24px", minHeight: "200px", display: "flex", flexDirection: "column" }}
                    >
                      <div className="flex-center" style={{ justifyContent: "space-between", marginBottom: "12px" }}>
                        <h4 style={{ fontSize: "18px" }}>{playlist.name}</h4>
                        <span style={{ fontSize: "12px", background: "rgba(124, 58, 237, 0.15)", color: "var(--color-primary)", padding: "4px 8px", borderRadius: "12px", fontWeight: 600 }}>
                          {playlist.song_count} songs
                        </span>
                      </div>
                      
                      {/* Short list of titles preview */}
                      <div style={{ flex: 1, display: "flex", flexDirection: "column", gap: "4px", color: "var(--text-secondary)", fontSize: "13px", marginTop: "8px", overflow: "hidden" }}>
                        {playlist.songs.slice(0, 3).map((song) => (
                          <div key={song.id} style={{ whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>
                            • {song.title}
                          </div>
                        ))}
                        {playlist.songs.length > 3 && (
                          <div style={{ color: "var(--text-muted)", fontSize: "11px", marginTop: "4px" }}>
                            + {playlist.songs.length - 3} more tracks...
                          </div>
                        )}
                      </div>
                    </div>
                  ))}
                  {playlists.length === 0 && (
                    <div style={{ color: "var(--text-muted)" }}>No playlists found. Add folders in Google Drive to get started.</div>
                  )}
                </div>
              ) : (
                <div>
                  <button className="btn-secondary" onClick={() => setExpandedPlaylist(null)} style={{ marginBottom: "20px" }}>
                    ← Back to Playlists
                  </button>
                  <div className="glass-card" style={{ padding: "28px" }}>
                    <div className="flex-center" style={{ justifyContent: "space-between", marginBottom: "20px" }}>
                      <h3 style={{ fontSize: "22px" }}>{expandedPlaylist.name} Details</h3>
                      <span style={{ fontSize: "14px", color: "var(--text-muted)" }}>
                        {expandedPlaylist.song_count} total songs
                      </span>
                    </div>

                    <table className="song-table">
                      <thead>
                        <tr>
                          <th>Title</th>
                          <th>Artist</th>
                          <th>Album</th>
                          <th>Duration</th>
                        </tr>
                      </thead>
                      <tbody>
                        {expandedPlaylist.songs.map((song) => (
                          <tr key={song.id} className="song-row" onClick={() => handlePlaySong(song, expandedPlaylist.songs)}>
                            <td>{song.title}</td>
                            <td>{song.artist}</td>
                            <td>{song.album}</td>
                            <td>{formatTime(song.duration_seconds)}</td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>
                </div>
              )}
            </div>
          )}

          {/* Settings Tab */}
          {activeTab === "settings" && (
            <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: "32px" }}>
              {/* Password Editor Form */}
              <div className="glass-card" style={{ padding: "28px" }}>
                <h3 style={{ fontSize: "18px", marginBottom: "20px" }}>Change Admin Password</h3>
                <form onSubmit={handlePasswordChange} className="login-form">
                  {passwordError && <div className="login-error">{passwordError}</div>}
                  {passwordSuccess && <div style={{ color: "var(--color-success)", padding: "10px", borderRadius: "6px", background: "rgba(16,185,129,0.1)", textAlign: "center", fontSize: "14px" }}>{passwordSuccess}</div>}
                  
                  <div className="form-group">
                    <label className="form-label">Current Password</label>
                    <input
                      type="password"
                      placeholder="Enter current password"
                      value={currentPassword}
                      onChange={(e) => setCurrentPassword(e.target.value)}
                      required
                    />
                  </div>

                  <div className="form-group">
                    <label className="form-label">New Password</label>
                    <input
                      type="password"
                      placeholder="Enter new password"
                      value={newPassword}
                      onChange={(e) => setNewPassword(e.target.value)}
                      required
                    />
                  </div>

                  <button type="submit" className="btn-primary" style={{ marginTop: "12px" }}>
                    Update Password
                  </button>
                </form>
              </div>

              {/* Drive Integration Parameters */}
              <div className="glass-card" style={{ padding: "28px" }}>
                <h3 style={{ fontSize: "18px", marginBottom: "20px" }}>Drive Integration Parameters</h3>
                <p style={{ color: "var(--text-muted)", fontSize: "14px" }}>
                  Configure your GDRIVE_ROOT_FOLDER_ID and OAuth in the backend environment variables.
                </p>
              </div>
            </div>
          )}
        </div>
      </main>

      {/* Persistent mini-player bar at the bottom */}
      {currentSong && (
        <div className="player-bar glass" style={{ height: "80px", gridTemplateColumns: "1fr 2fr 1fr", position: "fixed", bottom: 0, left: 0, width: "100%", borderTop: "1px solid var(--border-glass)" }}>
          <div className="player-song-details">
            <SongCover song={currentSong} size="48px" fontSize="16px" />
            <div className="player-song-meta">
              <span className="player-title">{currentSong.title}</span>
              <span className="player-artist">{currentSong.artist}</span>
            </div>
          </div>

          <div className="player-center">
            <div className="player-controls" style={{ gap: "16px" }}>
              <button className="control-btn" onClick={handlePrevSong}>
                <SkipBack size={18} fill="currentColor" />
              </button>
              <button className="play-pause-btn flex-center" onClick={togglePlay} style={{ width: "36px", height: "36px" }}>
                {isPlaying ? <Pause size={16} fill="currentColor" /> : <Play size={16} fill="currentColor" style={{ marginLeft: "2px" }} />}
              </button>
              <button className="control-btn" onClick={handleNextSong}>
                <SkipForward size={18} fill="currentColor" />
              </button>
            </div>
            <div className="player-timeline" style={{ width: "100%", maxWidth: "420px" }}>
              <span>{formatTime(currentTime)}</span>
              <div className="timeline-slider-container">
                <input
                  type="range"
                  min="0"
                  max={duration || 0}
                  value={currentTime}
                  onChange={(e) => {
                    const targetVal = Number(e.target.value);
                    if (audioRef.current) {
                      audioRef.current.currentTime = targetVal;
                      setCurrentTime(targetVal);
                    }
                  }}
                />
              </div>
              <span>{formatTime(duration)}</span>
            </div>
          </div>

          <div className="player-right">
            <button 
              onClick={() => setShowQueue(!showQueue)} 
              className="control-btn" 
              style={{ color: showQueue ? "var(--color-primary)" : "inherit", marginRight: "8px" }}
              title="Play Queue"
            >
              <ListMusic size={16} />
            </button>
            <button onClick={() => setIsMuted(!isMuted)} className="control-btn">
              {isMuted || volume === 0 ? <VolumeX size={16} /> : <Volume2 size={16} />}
            </button>
            <div className="volume-container">
              <input
                type="range"
                min="0"
                max="1"
                step="0.05"
                value={isMuted ? 0 : volume}
                onChange={(e) => {
                  const targetVol = Number(e.target.value);
                  setVolume(targetVol);
                  setIsMuted(false);
                }}
              />
            </div>
          </div>
        </div>
      )}

      {/* Queue Drawer Panel */}
      {showQueue && (
        <aside className="sidebar glass" style={{ width: "300px", position: "fixed", right: 0, top: 0, height: "calc(100% - 80px)", zIndex: 10, padding: "20px", display: "flex", flexDirection: "column", borderLeft: "1px solid var(--border-glass)" }}>
          <div className="flex-center" style={{ justifyContent: "space-between", marginBottom: "16px" }}>
            <h3 style={{ fontSize: "16px", fontWeight: "bold", display: "flex", alignItems: "center", gap: "8px", margin: 0 }}><ListMusic size={18} /> Play Queue</h3>
            <button onClick={() => setShowQueue(false)} className="control-btn" style={{ padding: "4px" }}><X size={18} /></button>
          </div>

          <div style={{ flex: 1, overflowY: "auto", display: "flex", flexDirection: "column", gap: "16px" }}>
            {/* Now Playing */}
            {currentSong && (
              <div>
                <span style={{ fontSize: "11px", color: "var(--text-muted)", textTransform: "uppercase", fontWeight: 600 }}>Now Playing</span>
                <div style={{ display: "flex", alignItems: "center", gap: "10px", marginTop: "8px" }}>
                  <SongCover song={currentSong} size="36px" fontSize="12px" />
                  <div style={{ overflow: "hidden" }}>
                    <div style={{ fontWeight: 600, fontSize: "13px", color: "var(--color-primary)", whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>{currentSong.title}</div>
                    <div style={{ fontSize: "11px", color: "var(--text-muted)", whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>{currentSong.artist}</div>
                  </div>
                </div>
              </div>
            )}

            {/* Next In Queue (Manual) */}
            <div>
              <div className="flex-center" style={{ justifyContent: "space-between", marginBottom: "8px" }}>
                <span style={{ fontSize: "11px", color: "var(--text-muted)", textTransform: "uppercase", fontWeight: 600 }}>Next in Queue</span>
                {songQueue.length > 0 && <button onClick={clearQueue} style={{ fontSize: "11px", background: "none", border: "none", color: "var(--color-danger)", cursor: "pointer", padding: 0 }}>Clear</button>}
              </div>
              <div style={{ display: "flex", flexDirection: "column", gap: "8px" }}>
                {songQueue.map((s, idx) => (
                  <div key={idx} style={{ display: "flex", alignItems: "center", gap: "10px", padding: "6px", background: "rgba(255,255,255,0.02)", borderRadius: "6px" }}>
                    <SongCover song={s} size="32px" fontSize="11px" />
                    <div style={{ flex: 1, overflow: "hidden" }}>
                      <div style={{ fontWeight: 500, fontSize: "12px", whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>{s.title}</div>
                      <div style={{ fontSize: "10px", color: "var(--text-muted)", whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>{s.artist}</div>
                    </div>
                    <button onClick={() => removeFromQueue(idx)} style={{ background: "none", border: "none", color: "rgba(255,255,255,0.3)", cursor: "pointer", fontSize: "16px", padding: "0 4px" }}>&times;</button>
                  </div>
                ))}
                {songQueue.length === 0 && <div style={{ fontSize: "12px", color: "var(--text-muted)", fontStyle: "italic" }}>Queue is empty</div>}
              </div>
            </div>

            {/* Next Up (Remaining Playlist) */}
            {activePlaylistSongs.length > 0 && currentSong && (
              <div>
                <span style={{ fontSize: "11px", color: "var(--text-muted)", textTransform: "uppercase", fontWeight: 600 }}>Next Up from List</span>
                <div style={{ display: "flex", flexDirection: "column", gap: "8px", marginTop: "8px" }}>
                  {(() => {
                    const idx = activePlaylistSongs.findIndex(s => s.id === currentSong.id);
                    if (idx === -1) return null;
                    const upcoming = activePlaylistSongs.slice(idx + 1, idx + 6); // next 5 songs
                    if (upcoming.length === 0) return <div style={{ fontSize: "12px", color: "var(--text-muted)", fontStyle: "italic" }}>No more songs in list</div>;
                    return upcoming.map((s, uIdx) => (
                      <div key={uIdx} style={{ display: "flex", alignItems: "center", gap: "10px", padding: "4px" }}>
                        <SongCover song={s} size="32px" fontSize="11px" />
                        <div style={{ overflow: "hidden" }}>
                          <div style={{ fontWeight: 500, fontSize: "12px", whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>{s.title}</div>
                          <div style={{ fontSize: "10px", color: "var(--text-muted)", whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>{s.artist}</div>
                        </div>
                      </div>
                    ));
                  })()}
                </div>
              </div>
            )}
          </div>
        </aside>
      )}

      {/* Metadata Editor Inline Modal Overlay */}
      {editingSong && (
        <div className="modal-overlay flex-center" style={{ position: "fixed", top: 0, left: 0, width: "100vw", height: "100vh", background: "rgba(0,0,0,0.6)", zIndex: 1000 }}>
          <div className="glass-card" style={{ width: "480px", padding: "32px", borderRadius: "16px", position: "relative" }}>
            <button
              onClick={() => setEditingSong(null)}
              style={{ position: "absolute", top: "20px", right: "20px", color: "var(--text-muted)" }}
            >
              <X size={20} />
            </button>
            <h3 style={{ fontSize: "20px", marginBottom: "24px" }} className="flex-center">
              Edit Track Metadata
            </h3>
            
            <form onSubmit={handleSaveMetadata} className="login-form">
              <div className="form-group">
                <label className="form-label">Track Title</label>
                <input
                  type="text"
                  value={editTitle}
                  onChange={(e) => setEditTitle(e.target.value)}
                  required
                />
              </div>

              <div className="form-group">
                <label className="form-label">Artist</label>
                <input
                  type="text"
                  value={editArtist}
                  onChange={(e) => setEditArtist(e.target.value)}
                  required
                />
              </div>

              <div className="form-group">
                <label className="form-label">Album Name</label>
                <input
                  type="text"
                  value={editAlbum}
                  onChange={(e) => setEditAlbum(e.target.value)}
                />
              </div>

              <div className="form-group">
                <label className="form-label">Genre</label>
                <input
                  type="text"
                  value={editGenre}
                  onChange={(e) => setEditGenre(e.target.value)}
                />
              </div>

              <div className="flex-center" style={{ gap: "16px", marginTop: "24px" }}>
                <button type="button" className="btn-secondary" style={{ flex: 1 }} onClick={() => setEditingSong(null)}>
                  Cancel
                </button>
                <button type="submit" className="btn-primary" style={{ flex: 1 }}>
                  Save Changes
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
}

export default App;
```

### 29. `admin/src/index.css`
[index.css](file:///e:/PROJECT SONDRA/sondra/admin/src/index.css)
```css
@import url('https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700&family=Outfit:wght@400;500;600;700;800&display=swap');

:root {
  --bg-primary: #08070d;
  --bg-secondary: #111019;
  --bg-tertiary: #191724;
  --bg-glass: rgba(25, 23, 36, 0.65);
  --border-glass: rgba(255, 255, 255, 0.06);
  --border-glass-focus: rgba(255, 255, 255, 0.15);
  
  --primary-gradient: linear-gradient(135deg, #7c3aed 0%, #3b82f6 100%);
  --accent-gradient: linear-gradient(135deg, #ec4899 0%, #8b5cf6 100%);
  --text-primary: #f3f4f6;
  --text-secondary: #9ca3af;
  --text-muted: #6b7280;
  
  --color-primary: #8b5cf6;
  --color-primary-glow: rgba(139, 92, 246, 0.35);
  --color-success: #10b981;
  --color-danger: #ef4444;
  --color-warning: #f59e0b;
  
  --transition-smooth: all 0.3s cubic-bezier(0.4, 0, 0.2, 1);
  --transition-fast: all 0.15s ease-out;
  
  --shadow-lg: 0 10px 30px -10px rgba(0, 0, 0, 0.7);
  --shadow-glow: 0 0 20px var(--color-primary-glow);
}

* {
  margin: 0;
  padding: 0;
  box-sizing: border-box;
  font-family: 'Inter', sans-serif;
  -webkit-font-smoothing: antialiased;
  -moz-osx-font-smoothing: grayscale;
}

body {
  background-color: var(--bg-primary);
  color: var(--text-primary);
  overflow: hidden;
  height: 100vh;
  width: 100vw;
}

/* Custom Scrollbar */
::-webkit-scrollbar {
  width: 6px;
  height: 6px;
}
::-webkit-scrollbar-track {
  background: var(--bg-primary);
}
::-webkit-scrollbar-thumb {
  background: var(--bg-tertiary);
  border-radius: 3px;
}
::-webkit-scrollbar-thumb:hover {
  background: var(--color-primary);
}

/* Glassmorphism Classes */
.glass {
  background: var(--bg-glass);
  backdrop-filter: blur(16px);
  -webkit-backdrop-filter: blur(16px);
  border: 1px solid var(--border-glass);
}

.glass-card {
  background: rgba(30, 28, 45, 0.45);
  backdrop-filter: blur(12px);
  border: 1px solid var(--border-glass);
  border-radius: 16px;
  box-shadow: var(--shadow-lg);
  transition: var(--transition-smooth);
}

.glass-card:hover {
  border-color: var(--border-glass-focus);
  box-shadow: 0 12px 40px -10px rgba(0, 0, 0, 0.8), 0 0 15px rgba(139, 92, 246, 0.1);
  transform: translateY(-2px);
}

/* Base Headings & UI Details */
h1, h2, h3, h4, .title-font {
  font-family: 'Outfit', sans-serif;
  font-weight: 700;
  letter-spacing: -0.02em;
}

/* Range Slider Styling */
input[type="range"] {
  -webkit-appearance: none;
  width: 100%;
  height: 5px;
  border-radius: 5px;
  background: var(--bg-tertiary);
  outline: none;
  cursor: pointer;
  transition: var(--transition-fast);
}

input[type="range"]::-webkit-slider-thumb {
  -webkit-appearance: none;
  appearance: none;
  width: 12px;
  height: 12px;
  border-radius: 50%;
  background: #ffffff;
  box-shadow: 0 0 10px rgba(0, 0, 0, 0.5);
  transition: var(--transition-fast);
}

input[type="range"]:hover::-webkit-slider-thumb {
  transform: scale(1.3);
  background: var(--color-primary);
  box-shadow: 0 0 10px var(--color-primary);
}

/* Button & Interactive styles */
button {
  cursor: pointer;
  border: none;
  outline: none;
  background: none;
  color: inherit;
  transition: var(--transition-fast);
}

.btn-primary {
  background: var(--primary-gradient);
  color: #ffffff;
  padding: 10px 20px;
  border-radius: 8px;
  font-weight: 600;
  box-shadow: 0 4px 15px rgba(124, 58, 237, 0.3);
}

.btn-primary:hover {
  transform: translateY(-1px);
  box-shadow: 0 6px 20px rgba(124, 58, 237, 0.5), var(--shadow-glow);
}

.btn-primary:active {
  transform: translateY(1px);
}

.btn-secondary {
  background: var(--bg-tertiary);
  border: 1px solid var(--border-glass);
  color: var(--text-primary);
  padding: 10px 20px;
  border-radius: 8px;
  font-weight: 500;
}

.btn-secondary:hover {
  background: rgba(255, 255, 255, 0.05);
  border-color: var(--border-glass-focus);
}

/* Input Fields */
input[type="text"], input[type="password"] {
  width: 100%;
  background: rgba(255, 255, 255, 0.03);
  border: 1px solid var(--border-glass);
  color: #ffffff;
  padding: 12px 16px;
  border-radius: 8px;
  outline: none;
  font-size: 15px;
  transition: var(--transition-fast);
}

input[type="text"]:focus, input[type="password"]:focus {
  background: rgba(255, 255, 255, 0.05);
  border-color: var(--color-primary);
  box-shadow: 0 0 0 3px var(--color-primary-glow);
}

/* Utility Layouts */
.flex-center {
  display: flex;
  align-items: center;
  justify-content: center;
}

/* Micro-animations */
@keyframes pulse-glow {
  0%, 100% {
    opacity: 0.6;
    box-shadow: 0 0 10px rgba(139, 92, 246, 0.2);
  }
  50% {
    opacity: 1;
    box-shadow: 0 0 25px rgba(139, 92, 246, 0.6);
  }
}

.pulse-glowing {
  animation: pulse-glow 2s infinite ease-in-out;
}

@keyframes spin-slow {
  from { transform: rotate(0deg); }
  to { transform: rotate(360deg); }
}

.spin-slow {
  animation: spin-slow 20s infinite linear;
}
```
