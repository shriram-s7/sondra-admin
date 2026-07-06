import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:smtc_windows/smtc_windows.dart';
import 'package:audio_session/audio_session.dart';

class SondraAudioHandler extends BaseAudioHandler {
  final AudioPlayer _player = AudioPlayer(
    audioLoadConfiguration: const AudioLoadConfiguration(
      androidLoadControl: AndroidLoadControl(
        minBufferDuration: Duration(seconds: 15),
        maxBufferDuration: Duration(seconds: 50),
        bufferForPlaybackDuration: Duration(milliseconds: 1000),
        bufferForPlaybackAfterRebufferDuration: Duration(seconds: 5),
      ),
    ),
  );
  SMTCWindows? _smtc;
  Future<void>? _initFuture;
  // Callbacks hooked by the Riverpod notifier
  Future<void> Function()? onSkipToNext;
  Future<void> Function()? onSkipToPrevious;
  void Function(bool)? onPlayingChanged;
  double _preInterruptionVolume = 0.8;
  bool _ignoreSmtcEvents = false;

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
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playback,
        avAudioSessionMode: AVAudioSessionMode.defaultMode,
        androidAudioAttributes: AndroidAudioAttributes(
          contentType: AndroidAudioContentType.music,
          usage: AndroidAudioUsage.media,
        ),
        androidAudioFocusGainType: AndroidAudioFocusGainType.gainTransientMayDuck,
        androidWillPauseWhenDucked: false,
      ));

      bool interrupted = false;
      bool ducked = false;

      session.interruptionEventStream.listen((event) async {
        if (event.begin) {
          switch (event.type) {
            case AudioInterruptionType.duck:
              _preInterruptionVolume = _player.volume;
              await _player.setVolume(_preInterruptionVolume * 0.3);
              ducked = true;
              break;
            case AudioInterruptionType.pause:
              await pause();
              interrupted = true;
              break;
            case AudioInterruptionType.unknown:
              break;
          }
        } else {
          switch (event.type) {
            case AudioInterruptionType.duck:
              if (ducked) {
                await _player.setVolume(_preInterruptionVolume);
                await play();
                ducked = false;
              }
              break;
            case AudioInterruptionType.pause:
              if (interrupted) {
                await play();
                interrupted = false;
              }
              break;
            case AudioInterruptionType.unknown:
              break;
          }
        }
      });

      session.becomingNoisyEventStream.listen((event) async {
        await pause();
      });
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
      if (_ignoreSmtcEvents) {
        print("Ignoring SMTC event during active programmatic transition: $event");
        return;
      }
      switch (event) {
        case PressedButton.play:
          play();
          break;
        case PressedButton.pause:
          pause();
          break;
        case PressedButton.next:
          click(MediaButton.next);
          break;
        case PressedButton.previous:
          click(MediaButton.previous);
          break;
        default:
          break;
      }
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

  void setSmtcPlaying(bool playing) {
    if (_smtc != null) {
      _smtc!.setPlaybackStatus(
        playing ? PlaybackStatus.Playing : PlaybackStatus.Paused
      );
      _smtc!.setIsNextEnabled(true);
      _smtc!.setIsPrevEnabled(true);
      _smtc!.setIsPlayEnabled(true);
      _smtc!.setIsPauseEnabled(true);
    }
  }

  Future<void> playUri(String uri, MediaItem item, {bool autoPlay = true}) async {
    final isWindows = !kIsWeb && Platform.isWindows;
    if (isWindows) {
      _ignoreSmtcEvents = true;
    }
    try {
      await ensureInitialized();

      mediaItem.add(item);

      if (_smtc != null) {
        _smtc!.setTitle(item.title);
        _smtc!.setArtist(item.artist ?? "Unknown Artist");
        if (item.album != null) {
          _smtc!.setAlbum(item.album!);
        }
      }

      final isLocalFilePath = uri.startsWith('/') || 
          (uri.length > 2 && uri[1] == ':');
      
      if (!kIsWeb && Platform.isAndroid) {
        if (isLocalFilePath) {
          await _player.setAudioSource(
            AudioSource.file(uri, tag: item),
          );
        } else {
          final parsedUri = Uri.parse(uri);
          if (parsedUri.scheme == 'file') {
            await _player.setAudioSource(
              AudioSource.file(parsedUri.toFilePath(), tag: item),
            );
          } else {
            await _player.setAudioSource(
              AudioSource.uri(parsedUri, tag: item),
            );
          }
        }
      } else {
        if (isLocalFilePath) {
          await _player.setAudioSource(AudioSource.file(uri));
        } else {
          final parsedUri = Uri.parse(uri);
          if (parsedUri.scheme == 'file') {
            await _player.setAudioSource(AudioSource.file(parsedUri.toFilePath()));
          } else {
            await _player.setAudioSource(
              AudioSource.uri(parsedUri, tag: item),
            );
          }
        }
      }
      if (isWindows && autoPlay) {
        await _player.play();
        if (_smtc != null) {
          _smtc!.setPlaybackStatus(PlaybackStatus.Playing);
        }
      }
      if (autoPlay) {
        if (!isWindows) {
          if (_player.processingState != ProcessingState.ready) {
            await _player.processingStateStream.firstWhere(
              (state) => state == ProcessingState.ready || state == ProcessingState.idle,
            ).timeout(const Duration(seconds: 15));
          }
          if (_player.processingState == ProcessingState.idle) {
            throw Exception("Audio source failed to load");
          }
          await _player.play();
          if (!_player.playing) {
            await _player.playingStream.firstWhere((playing) => playing);
          }
        }
        playbackState.add(_transformEvent(_player.playbackEvent));
        onPlayingChanged?.call(true);
      }
    } catch (e) {
      print("Audio player setSource error: $e");
      playbackState.add(playbackState.value.copyWith(
        errorMessage: e.toString(),
      ));
    } finally {
      if (isWindows) {
        Future.delayed(const Duration(milliseconds: 500), () {
          _ignoreSmtcEvents = false;
        });
      }
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
    if (!_player.playing) {
      await _player.playingStream.firstWhere((playing) => playing);
    }
    onPlayingChanged?.call(true);
  }

  @override
  Future<void> pause() async {
    await _player.pause();
    if (_player.playing) {
      await _player.playingStream.firstWhere((playing) => !playing);
    }
    onPlayingChanged?.call(false);
  }

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
