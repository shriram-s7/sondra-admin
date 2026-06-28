import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import '../services/api_service.dart';
import '../services/audio_handler.dart';

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

  Future<void> playSong(Map<String, dynamic> song, List<Map<String, dynamic>> playlist, {int? startSeconds}) async {
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
      // Seed a randomized queue
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

    // 1. Check if there are items in the manual queue
    if (state.queue.isNotEmpty) {
      final nextSong = state.queue.first;
      final remainingQueue = List<Map<String, dynamic>>.from(state.queue)..removeAt(0);
      state = state.copyWith(queue: remainingQueue);
      
      // Play the song (keeping activePlaylist and originalPlaylist intact)
      playSong(nextSong, state.originalPlaylist);
      return;
    }

    // 2. Otherwise play the next song in the active playlist
    if (state.activePlaylist.isEmpty) return;
    int idx = state.activePlaylist.indexWhere((s) => s["id"] == state.currentSong!["id"]);
    
    if (idx != -1) {
      int nextIdx = idx + 1;
      if (nextIdx >= state.activePlaylist.length) {
        if (state.repeat == "all") {
          nextIdx = 0;
        } else {
          // If repeat is off or single, stop playback at end of queue
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
