import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart' show kIsWeb;
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
  final String? bufferingMessage;

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
    this.bufferingMessage,
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
    String? bufferingMessage,
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
      bufferingMessage: bufferingMessage,
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
  bool _advancingTrack = false;
  DateTime? _lastActionTime;
  Timer? _bufferingTimer;
  Timer? _bufferingSevereTimer;
  // Protection window: ignore playing=false events from the playingStream
  // within this period after a transition. Windows Media Foundation fires
  // delayed false events AFTER play() succeeds, which would override the
  // correct isPlaying=true state. This is the definitive fix.
  DateTime? _ignorePlayingFalseUntil;

  // Cache for playlist context lookups so the queue path in handleNext()
  // doesn't block on 1-3 sequential network calls per transition.
  List<Map<String, dynamic>>? _cachedPlaylists;
  List<Map<String, dynamic>>? _cachedLibrarySongs;
  DateTime? _cacheValidUntil;
  static const _cacheTtl = Duration(seconds: 30);

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
      final wasBuffering = state.isBuffering;
      final nowBuffering = pState.processingState == ProcessingState.buffering ||
                           pState.processingState == ProcessingState.loading;

      state = state.copyWith(
        isBuffering: nowBuffering,
      );

      // Buffering timeout management (Improvement 4)
      if (nowBuffering && !wasBuffering) {
        _bufferingTimer?.cancel();
        _bufferingSevereTimer?.cancel();
        _bufferingTimer = Timer(const Duration(seconds: 10), () {
          state = state.copyWith(
            bufferingMessage: "Slow connection, still buffering...",
          );
        });
        _bufferingSevereTimer = Timer(const Duration(seconds: 25), () {
          state = state.copyWith(
            bufferingMessage: null,
          );
          _retryCurrentSong();
        });
      } else if (!nowBuffering) {
        if (wasBuffering) {
          _bufferingTimer?.cancel();
          _bufferingSevereTimer?.cancel();
          _bufferingTimer = null;
          _bufferingSevereTimer = null;
        }
        if (state.bufferingMessage != null) {
          state = state.copyWith(bufferingMessage: null);
        }
      }

      if (pState.processingState == ProcessingState.completed) {
        if (state.repeat == "one") {
          state = state.copyWith(position: Duration.zero);
          seek(Duration.zero);
          globalAudioHandler.play();
        } else {
          if (_advancingTrack) return;
          _advancingTrack = true;
          // Use unawaited async call: handleNext() is async and must run
          // independently. The finally block would reset _advancingTrack
          // before playSong() runs if we used try/finally synchronously.
          handleNext().whenComplete(() {
            _advancingTrack = false;
          });
        }
      }
    });

    // Save playback progress every 10 seconds
    _positionLogTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (state.isPlaying && state.currentSong != null) {
        _api.logHistory(state.currentSong!["id"], state.position.inSeconds);
      }
    });

    globalAudioHandler.onSkipToNext = () => handleNext();
    globalAudioHandler.onSkipToPrevious = () => handlePrev();

    // onPlayingChanged is called directly from audio_handler after play()/pause()
    // confirms its result. This bypasses the playingStream which receives
    // delayed false events from Windows MF after transitions.
    globalAudioHandler.onPlayingChanged = (playing) {
      if (!playing) {
        // Ignore false events within the protection window.
        final until = _ignorePlayingFalseUntil;
        if (until != null && DateTime.now().isBefore(until)) return;
      }
      state = state.copyWith(isPlaying: playing);
      if (!kIsWeb && Platform.isWindows) {
        if (!state.isBuffering) {
          globalAudioHandler.setSmtcPlaying(playing);
        }
      }
    };

    globalAudioHandler.player.playingStream.listen((playing) {
      // Ignore transient false events from Windows MF within the protection window.
      // These are artifacts of the WMF pipeline firing playing=false after a
      // new source is loaded, even AFTER play() has successfully started audio.
      if (!playing) {
        final until = _ignorePlayingFalseUntil;
        if (until != null && DateTime.now().isBefore(until)) return;
      }
      state = state.copyWith(isPlaying: playing);
      if (!kIsWeb && Platform.isWindows) {
        if (!state.isBuffering) {
          globalAudioHandler.setSmtcPlaying(playing);
        }
      }
    });
  }

  Future<void> playSong(Map<String, dynamic> song, List<Map<String, dynamic>> playlist, {int? startSeconds, String? playlistName, bool internalCall = false, bool forcePlay = false}) async {
    if (_isBusy && !internalCall) return;
    _isBusy = true;
    try {
      // autoPlay rules:
      //  - Direct user action (internalCall=false): always play
      //  - forcePlay=true (from handleNext/handlePrev): always play  
      //  - Auto-advance (_advancingTrack=true): always play
      //  - Otherwise: inherit the current playing state
      final autoPlay = (!internalCall) || forcePlay || _advancingTrack || state.isPlaying || globalAudioHandler.player.playing;
      final isNewQueue = playlist.length != state.originalPlaylist.length ||
          playlist.asMap().entries.any((e) => state.originalPlaylist.length <= e.key || e.value["id"] != state.originalPlaylist[e.key]["id"]);

      List<Map<String, dynamic>> newActive = isNewQueue ? List.from(playlist) : state.activePlaylist;
      if (isNewQueue && state.shuffle) {
        _secureShuffle(newActive);
        newActive.removeWhere((s) => s["id"] == song["id"]);
        newActive.insert(0, song);
      }

      state = state.copyWith(
        originalPlaylist: isNewQueue ? playlist : state.originalPlaylist,
        activePlaylist: newActive,
        activePlaylistName: playlistName ?? (isNewQueue ? "Song Pool" : state.activePlaylistName),
        position: startSeconds != null ? Duration(seconds: startSeconds) : Duration.zero,
        currentSong: song,
        isBuffering: true,
      );

      final dlDir = await OfflineStorage().downloadsDir;
      final localFile = File('$dlDir/${song["id"]}.mp3');
      final localExists = await localFile.exists() && await localFile.length() > 0;
      final url = localExists
          ? localFile.path
          : "${_api.baseUrl}/api/stream/${song["id"]}/proxy?token=${_api.token}";

      final mediaItem = MediaItem(
        id: song["id"].toString(),
        album: song["album"] ?? "Unknown Album",
        title: song["title"] ?? "Unknown Title",
        artist: song["artist"] ?? "Unknown Artist",
        duration: Duration(seconds: song["duration_seconds"] ?? 0),
        artUri: Uri.parse("${_api.baseUrl}/api/songs/${song["id"]}/cover?v=${song["id"]}"),
      );

      await globalAudioHandler.playUri(url, mediaItem, autoPlay: autoPlay)
          .timeout(const Duration(seconds: 20));

      state = state.copyWith(isBuffering: false);

      if (autoPlay) {
        // Force the playing state TRUE immediately after playUri confirms.
        // Also set a 2-second protection window so any delayed WMF false
        // events from the playingStream are ignored.
        state = state.copyWith(isPlaying: true);
        if (!kIsWeb && Platform.isWindows) {
          _ignorePlayingFalseUntil = DateTime.now().add(const Duration(milliseconds: 2000));
          globalAudioHandler.setSmtcPlaying(true);
        }
      }

      if (startSeconds != null) {
        await globalAudioHandler.seek(Duration(seconds: startSeconds));
      }
    } catch (e) {
      state = state.copyWith(isBuffering: false, bufferingMessage: null);
      if (state.currentSong?["id"] == song["id"]) {
        state = state.copyWith(currentSong: null);
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
    // 1. Look up in local personal/offline playlists first (always fast, no cache needed)
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

    // 2. Use cached remote data if fresh, to avoid blocking network calls on every transition
    final now = DateTime.now();
    if (_cacheValidUntil != null && now.isBefore(_cacheValidUntil!)) {
      final lookupResult = _lookupInCache(song);
      if (lookupResult != null) return lookupResult;
    }

    // 3. Fetch remote playlists from ApiService (cache miss or expired)
    try {
      final remotePlaylists = await _api.getPlaylists();
      _cachedPlaylists = remotePlaylists.cast<Map<String, dynamic>>();
      for (final pl in remotePlaylists) {
        final songs = List<dynamic>.from(pl["songs"] ?? []);
        final exists = songs.any((s) => s["id"] == song["id"]);
        if (exists) {
          final name = pl["name"] ?? "Remote Playlist";
          final list = songs.map<Map<String, dynamic>>((s) => Map<String, dynamic>.from(s)).toList();
          _cacheValidUntil = now.add(_cacheTtl);
          return {'name': name, 'songs': list};
        }
      }
    } catch (e) {
      print("Error fetching remote playlists in _findPlaylistContextFor: $e");
    }

    // 4. Fallback to all library songs
    try {
      final allLibrary = await _api.getSongs();
      _cachedLibrarySongs = allLibrary.cast<Map<String, dynamic>>();
      _cacheValidUntil = now.add(_cacheTtl);
      final list = allLibrary.map<Map<String, dynamic>>((s) => Map<String, dynamic>.from(s)).toList();
      return {'name': "Music Library", 'songs': list};
    } catch (e) {
      print("Error fetching all library songs in _findPlaylistContextFor: $e");
    }

    return {'name': "Music Library", 'songs': [song]};
  }

  /// Tries to find [song] in the cached playlists or library, returning the
  /// context immediately without any network I/O. Returns null on cache miss.
  Map<String, dynamic>? _lookupInCache(Map<String, dynamic> song) {
    // Search cached remote playlists
    if (_cachedPlaylists != null) {
      for (final pl in _cachedPlaylists!) {
        final songs = List<dynamic>.from(pl["songs"] ?? []);
        if (songs.any((s) => s["id"] == song["id"])) {
          final name = pl["name"] ?? "Remote Playlist";
          final list = songs.map<Map<String, dynamic>>((s) => Map<String, dynamic>.from(s)).toList();
          return {'name': name, 'songs': list};
        }
      }
    }
    // Search cached library
    if (_cachedLibrarySongs != null) {
      if (_cachedLibrarySongs!.any((s) => s["id"] == song["id"])) {
        final list = _cachedLibrarySongs!
            .map<Map<String, dynamic>>((s) => Map<String, dynamic>.from(s))
            .toList();
        return {'name': "Music Library", 'songs': list};
      }
    }
    return null;
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

    // Wait for any in-progress operation to finish, but do NOT seize _isBusy here.
    // playSong() will seize it with internalCall=true (bypasses the busy guard).
    if (_isBusy) {
      while (_isBusy) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
    }

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

        // forcePlay=true: user explicitly pressed Next, always play regardless of current state
        await playSong(nextSong, plSongs, playlistName: plName, internalCall: true, forcePlay: true);
        return;
      }

      // RULE 2 - CURRENT PLAYLIST PLAYS THROUGH COMPLETELY
      if (state.activePlaylist.isEmpty) return;
      int idx = state.activePlaylist.indexWhere((s) => s["id"] == state.currentSong!["id"]);

      if (idx != -1) {
        int nextIdx = idx + 1;
        if (nextIdx >= state.activePlaylist.length) {
          if (state.shuffle && state.originalPlaylist.isNotEmpty) {
            final newShuffled = List<Map<String, dynamic>>.from(state.originalPlaylist);
            _secureShuffle(newShuffled);
            if (newShuffled.length > 1 && newShuffled.first["id"] == state.currentSong!["id"]) {
              final temp = newShuffled[0];
              newShuffled[0] = newShuffled[1];
              newShuffled[1] = temp;
            }
            state = state.copyWith(activePlaylist: newShuffled);
            await playSong(newShuffled.first, state.originalPlaylist, internalCall: true, forcePlay: true);
          } else if (state.activePlaylist.isNotEmpty) {
            await playSong(state.activePlaylist[0], state.originalPlaylist, internalCall: true, forcePlay: true);
          }
        } else {
          await playSong(state.activePlaylist[nextIdx], state.originalPlaylist, internalCall: true, forcePlay: true);
        }
      }
    } finally {
      // Do NOT touch _isBusy here — playSong() owns it for the async duration.
    }
  }

  Future<void> handlePrev() async {
    final now = DateTime.now();
    if (_lastActionTime != null &&
        now.difference(_lastActionTime!) < const Duration(milliseconds: 600)) {
      return;
    }
    _lastActionTime = now;

    // Same as handleNext: do NOT seize _isBusy — playSong() does it.
    if (_isBusy) {
      while (_isBusy) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
    }

    try {
      if (state.activePlaylist.isEmpty || state.currentSong == null) return;

      // Restart song if it has played past 3 seconds
      if (state.position.inSeconds > 3) {
        seek(Duration.zero);
        globalAudioHandler.play();
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
        // forcePlay=true: user explicitly pressed Prev, always play
        await playSong(state.activePlaylist[prevIdx], state.originalPlaylist, internalCall: true, forcePlay: true);
      }
    } finally {
      // Do NOT touch _isBusy here — playSong() owns it.
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

  Future<void> _retryCurrentSong() async {
    if (state.currentSong == null || state.activePlaylist.isEmpty) return;
    _isBusy = false;
    await playSong(
      state.currentSong!,
      state.activePlaylist,
      playlistName: state.activePlaylistName,
      internalCall: true,
    );
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _durSub?.cancel();
    _stateSub?.cancel();
    _positionLogTimer?.cancel();
    _bufferingTimer?.cancel();
    _bufferingSevereTimer?.cancel();
    super.dispose();
  }
}

final playerProvider = StateNotifierProvider<PlayerNotifier, PlayerState>((ref) {
  return PlayerNotifier();
});

final showNowPlayingProvider = StateProvider<bool>((ref) => false);
final showBottomNavBarProvider = StateProvider<bool>((ref) => false);
