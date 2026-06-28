import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:smtc_windows/smtc_windows.dart';

class SondraAudioHandler extends BaseAudioHandler {
  final AudioPlayer _player = AudioPlayer();
  SMTCWindows? _smtc;

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
  }

  void _initWindowsSmtc() {
    _smtc = SMTCWindows();
    
    // Listen to button press streams
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
      _player.play();
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
  Future<void> play() => _player.play();

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
