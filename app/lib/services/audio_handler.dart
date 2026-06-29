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
    
    // Explicitly enable next and previous buttons on the SMTC.
    // The default SMTCConfig has nextEnabled/prevEnabled=true, but
    // the system needs an explicit update to register them as active.
    _smtc!.setIsNextEnabled(true);
    _smtc!.setIsPrevEnabled(true);
    _smtc!.setIsPlayEnabled(true);
    _smtc!.setIsPauseEnabled(true);

    // Listen to button press streams from the system
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
  Future<void> click([MediaButton button = MediaButton.media]) async {
    switch (button) {
      case MediaButton.media:
        if (playbackState.value.playing) {
          await pause();
        } else {
          await play();
        }
        break;
      case MediaButton.next:
        await skipToNext();
        break;
      case MediaButton.previous:
        await skipToPrevious();
        break;
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
