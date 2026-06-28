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
    this.activePlaylistName = "Music Library",
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

    // Save playback progress every 10 seconds
    _positionLogTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (state.isPlaying && state.currentSong != null) {
        _api.logHistory(state.currentSong!["id"], state.position.inSeconds);
      }
    });

    // Register Media / Earbud skip controls callback from background handler
    globalAudioHandler.onSkipToNext = () async {
      handleNext();
    };
    globalAudioHandler.onSkipToPrevious = () async {
      handlePrev();
    };
  }

  Future<void> playSong(Map<String, dynamic> song, List<Map<String, dynamic>> playlist, {int? startSeconds, String? playlistName}) async {
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

    state = state.copyWith(
      currentSong: song,
      originalPlaylist: newOriginal,
      activePlaylist: newActive,
      activePlaylistName: playlistName ?? (isNewQueue ? "Music Library" : state.activePlaylistName),
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
      
      if (startSeconds != null) {
        await globalAudioHandler.seek(Duration(seconds: startSeconds));
      }
    } catch (e) {
      print("Error loading song in provider: $e");
      // Skip to next song automatically on loading error (Rule 5)
      handleNext();
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
    if (state.currentSong == null) return;

    // RULE 1 - QUEUE PLAYS ACROSS PLAYLISTS
    if (state.queue.isNotEmpty) {
      final nextSong = state.queue.first;
      final remainingQueue = List<Map<String, dynamic>>.from(state.queue)..removeAt(0);
      state = state.copyWith(queue: remainingQueue);
      
      final contextResult = await _findPlaylistContextFor(nextSong);
      final plName = contextResult['name'] as String;
      final plSongs = contextResult['songs'] as List<Map<String, dynamic>>;
      
      await playSong(nextSong, plSongs, playlistName: plName);
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
          await playSong(state.activePlaylist[nextIdx], state.originalPlaylist);
        } else {
          // RULE 3 & 4 - WHAT HAPPENS WHEN PLAYLIST ENDS
          final allLibrary = await _api.getSongs();
          if (allLibrary.isEmpty) {
            globalAudioHandler.pause();
            seek(Duration.zero);
            return;
          }
          
          final rand = Random.secure();
          final randomSong = Map<String, dynamic>.from(allLibrary[rand.nextInt(allLibrary.length)]);
          
          final contextResult = await _findPlaylistContextFor(randomSong);
          final plName = contextResult['name'] as String;
          final plSongs = contextResult['songs'] as List<Map<String, dynamic>>;
          
          await playSong(randomSong, plSongs, playlistName: plName);
        }
      } else {
        await playSong(state.activePlaylist[nextIdx], state.originalPlaylist);
      }
    }
  }

  void handlePrev() {
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
