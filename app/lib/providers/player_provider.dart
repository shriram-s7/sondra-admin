import 'dart:async';
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
  final Duration position;
  final Duration duration;
  final bool shuffle;
  final String repeat; // "none" | "one" | "all"
  final double volume;
  final List<Map<String, dynamic>> activePlaylist;

  PlayerState({
    this.currentSong,
    this.isPlaying = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.shuffle = false,
    this.repeat = "none",
    this.volume = 0.8,
    this.activePlaylist = const [],
  });

  PlayerState copyWith({
    Map<String, dynamic>? currentSong,
    bool? isPlaying,
    Duration? position,
    Duration? duration,
    bool? shuffle,
    String? repeat,
    double? volume,
    List<Map<String, dynamic>>? activePlaylist,
  }) {
    return PlayerState(
      currentSong: currentSong ?? this.currentSong,
      isPlaying: isPlaying ?? this.isPlaying,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      shuffle: shuffle ?? this.shuffle,
      repeat: repeat ?? this.repeat,
      volume: volume ?? this.volume,
      activePlaylist: activePlaylist ?? this.activePlaylist,
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
      state = state.copyWith(isPlaying: pState.playing);
      if (pState.processingState == ProcessingState.completed) {
        handleNext();
      }
    });

    // Save playback progress every 10 seconds
    _positionLogTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (state.isPlaying && state.currentSong != null) {
        _api.logHistory(state.currentSong!["id"], state.position.inSeconds);
      }
    });
  }

  Future<void> playSong(Map<String, dynamic> song, List<Map<String, dynamic>> playlist, {int? startSeconds}) async {
    state = state.copyWith(
      currentSong: song,
      activePlaylist: playlist,
      position: startSeconds != null ? Duration(seconds: startSeconds) : Duration.zero,
    );

    try {
      final directUrl = await _api.getDirectStreamUrl(song["id"]);
      
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
    state = state.copyWith(shuffle: !state.shuffle);
  }

  void cycleRepeat() {
    String nextRepeat = "none";
    if (state.repeat == "none") {
      nextRepeat = "all";
    } else if (state.repeat == "all") {
      nextRepeat = "one";
    }
    state = state.copyWith(repeat: nextRepeat);
    globalAudioHandler.player.setLoopMode(
      nextRepeat == "one" ? LoopMode.one : LoopMode.off
    );
  }

  void setVolume(double vol) {
    state = state.copyWith(volume: vol);
    globalAudioHandler.player.setVolume(vol);
  }

  void handleNext() {
    if (state.activePlaylist.isEmpty || state.currentSong == null) return;
    int idx = state.activePlaylist.indexWhere((s) => s["id"] == state.currentSong!["id"]);
    
    int nextIdx = 0;
    if (state.shuffle) {
      nextIdx = (state.activePlaylist.length > 1) 
          ? (idx + 1 + (state.activePlaylist.length - 1)) % state.activePlaylist.length // simplified mock random or index jump
          : 0;
    } else if (idx != -1) {
      nextIdx = idx + 1;
      if (nextIdx >= state.activePlaylist.length) {
        if (state.repeat == "all") {
          nextIdx = 0;
        } else {
          globalAudioHandler.pause();
          return;
        }
      }
    }
    playSong(state.activePlaylist[nextIdx], state.activePlaylist);
  }

  void handlePrev() {
    if (state.activePlaylist.isEmpty || state.currentSong == null) return;
    if (state.position.inSeconds > 3) {
      seek(Duration.zero);
      return;
    }

    int idx = state.activePlaylist.indexWhere((s) => s["id"] == state.currentSong!["id"]);
    int prevIdx = 0;
    if (idx != -1) {
      prevIdx = idx - 1;
      if (prevIdx < 0) {
        prevIdx = state.repeat == "all" ? state.activePlaylist.length - 1 : 0;
      }
    }
    playSong(state.activePlaylist[prevIdx], state.activePlaylist);
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
