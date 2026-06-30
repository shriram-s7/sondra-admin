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
  bool _pendingPlaybackStart = false;
  DateTime? _lastActionTime;
  Timer? _bufferingTimer;
  Timer? _bufferingSevereTimer;

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
      if (_isBusy) return;

      // When a song just started playing, ignore the first stale "playing: false"
      // event that was queued during the transition. Without this the state stream
      // overwrites the optimistic isPlaying:true set in playSong(), causing a
      // visible "paused" flash on Bluetooth earbud skips.
      if (_pendingPlaybackStart) {
        _pendingPlaybackStart = false;
        if (!pState.playing && state.isPlaying) return;
      }

      final wasBuffering = state.isBuffering;
      final nowBuffering = pState.processingState == ProcessingState.buffering ||
                           pState.processingState == ProcessingState.loading;

      state = state.copyWith(
        isPlaying: pState.playing,
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

    globalAudioHandler.onSkipToNext = () => handleNext();
    globalAudioHandler.onSkipToPrevious = () => handlePrev();
  }

  Future<void> playSong(Map<String, dynamic> song, List<Map<String, dynamic>> playlist, {int? startSeconds, String? playlistName, bool internalCall = false}) async {
    if (_isBusy && !internalCall) return;
    _isBusy = true;
    try {
      // 1. setAudioSource() handles internal source replacement - no stop/seek needed.
      //    Removing redundant stop+seek saves ~50-150ms per transition.
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
        artUri: Uri.parse("${_api.baseUrl}/api/songs/${song["id"]}/cover?v=${song["id"]}"),
      );

      // Start warming the connection for the song after [song] NOW, before
      // playUri() even begins, so by the time the next transition fires the
      // backend proxy/Google-Drive fetch is already warmed. The early call is
      // sufficient; the Range request is idempotent so a second call is waste.
      _warmNextSong(currentSong: song);

      try {
        await globalAudioHandler.playUri(directUrl, mediaItem);

        // Ensure the player is actually playing (fixes Bluetooth earbud paused-after-skip bug)
        if (!globalAudioHandler.player.playing) {
          await globalAudioHandler.player.play();
        }

        // CHANGE 6: Only now that playUri() has succeeded do we update the banner song.
        _pendingPlaybackStart = true;
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
        // Retry up to 3 times with 1.5s delay before skipping (Improvement 1)
        bool retrySuccess = false;
        for (int attempt = 1; attempt <= 3; attempt++) {
          await Future.delayed(const Duration(milliseconds: 1500));
          state = state.copyWith(
            isBuffering: true,
            bufferingMessage: "Reconnecting... (attempt $attempt/3)",
          );
          try {
            await globalAudioHandler.playUri(directUrl, mediaItem);
            retrySuccess = true;
            break;
          } catch (retryErr) {
            print("Retry $attempt/3 failed: $retryErr");
          }
        }
        if (retrySuccess) {
          _pendingPlaybackStart = true;
          state = state.copyWith(
            currentSong: song,
            isBuffering: false,
            isPlaying: true,
            bufferingMessage: null,
          );
          if (startSeconds != null) {
            await globalAudioHandler.seek(Duration(seconds: startSeconds));
          }
        } else {
          handleNext();
        }
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

    if (_isBusy) {
      // Don't drop the command — wait briefly for the current transition to finish
      for (int i = 0; i < 20; i++) {
        await Future.delayed(const Duration(milliseconds: 50));
        if (!_isBusy) break;
      }
      if (_isBusy) return;
    }
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
          if (state.shuffle && state.originalPlaylist.isNotEmpty) {
            // Shuffle mode: generate next valid shuffled playback sequence (or restart it)
            final newShuffled = List<Map<String, dynamic>>.from(state.originalPlaylist);
            _secureShuffle(newShuffled);
            if (newShuffled.length > 1 && newShuffled.first["id"] == state.currentSong!["id"]) {
              // Swap the first song with the second to avoid immediate repeat
              final temp = newShuffled[0];
              newShuffled[0] = newShuffled[1];
              newShuffled[1] = temp;
            }
            state = state.copyWith(activePlaylist: newShuffled);
            await playSong(newShuffled.first, state.originalPlaylist, internalCall: true);
          } else if (state.activePlaylist.isNotEmpty) {
            // Linear mode: loop back to the first song, looping forever
            await playSong(state.activePlaylist[0], state.originalPlaylist, internalCall: true);
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

    if (_isBusy) {
      for (int i = 0; i < 20; i++) {
        await Future.delayed(const Duration(milliseconds: 50));
        if (!_isBusy) break;
      }
      if (_isBusy) return;
    }
    _isBusy = true;

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

  /// Warms up the streaming connection for the song that comes after [currentSong]
  /// in the active playlist. This is called early during playSong() so the CDN/
  /// proxy connection is already warmed by the time the next transition occurs.
  void _warmNextSong({Map<String, dynamic>? currentSong}) {
    final song = currentSong ?? state.currentSong;
    if (song == null) return;
    unawaited(_warmNextSongAsync(song));
  }

  Future<void> _warmNextSongAsync(Map<String, dynamic> song) async {
    Map<String, dynamic>? nextSong;
    if (state.queue.isNotEmpty) {
      nextSong = state.queue.first;
    } else if (state.activePlaylist.isNotEmpty) {
      final idx = state.activePlaylist.indexWhere((s) => s["id"] == song["id"]);
      if (idx != -1 && idx + 1 < state.activePlaylist.length) {
        nextSong = state.activePlaylist[idx + 1];
      } else if (state.repeat == "all" && state.activePlaylist.isNotEmpty) {
        nextSong = state.activePlaylist[0];
      }
    }
    if (nextSong == null) return;
    try {
      final localPath = nextSong["local_file_path"];
      if (localPath != null && await File(localPath).exists()) return;
      final url = "${_api.baseUrl}/api/stream/${nextSong["id"]}/proxy?token=${_api.token}";
      final request = await HttpClient().getUrl(Uri.parse(url));
      request.headers.set("Range", "bytes=0-131072");
      final response = await request.close();
      await response.drain();
    } catch (_) {}
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
