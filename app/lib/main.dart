import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:audio_service/audio_service.dart';
import 'services/audio_handler.dart';
import 'services/offline_storage.dart';
import 'services/api_service.dart';
import 'providers/player_provider.dart';
import 'screens/home_screen.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await OfflineStorage().init();
  await ApiService().init();

  if (!kIsWeb && Platform.isAndroid) {
    try {
      await const MethodChannel('com.sondra.music/notification')
          .invokeMethod('ensureChannel');
    } catch (_) {}
  }

  runApp(
    const ProviderScope(
      child: SondraApp(),
    ),
  );
}

class SondraApp extends StatefulWidget {
  const SondraApp({super.key});

  @override
  State<SondraApp> createState() => _SondraAppState();
}

class _SondraAppState extends State<SondraApp> {
  bool _audioReady = false;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb && Platform.isAndroid) {
      _initAndroidAudio();
    } else {
      _initAudio();
    }
  }

  Future<void> _initAndroidAudio() async {
    final handler = SondraAudioHandler();
    globalAudioHandler = handler;
    try {
      await AudioService.init(
        builder: () => handler,
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'com.sondra.music.channel.audio',
          androidNotificationChannelName: 'Sondra Music Playback',
          androidNotificationChannelDescription: 'Music playback controls',
          androidNotificationOngoing: true,
          androidShowNotificationBadge: true,
        ),
      ).timeout(const Duration(seconds: 8));
    } catch (_) {
      // timeout or error — handler already set as direct, carry on
    }
    if (mounted) setState(() => _audioReady = true);
  }

  Future<void> _initAudio() async {
    globalAudioHandler = SondraAudioHandler();
    try {
      await AudioService.init(
        builder: () => SondraAudioHandler(),
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'com.sondra.music.channel.audio',
          androidNotificationChannelName: 'Sondra Music Playback',
          androidNotificationChannelDescription: 'Music playback controls',
          androidNotificationOngoing: true,
          androidShowNotificationBadge: true,
        ),
      );
    } catch (e) {
      debugPrint('AudioService.init failed ($e) — using direct handler');
    }
    if (mounted) setState(() => _audioReady = true);
  }

  @override
  Widget build(BuildContext context) {
    final showOverlay = !_audioReady && !kIsWeb && Platform.isAndroid;

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
      builder: (context, child) {
        return Consumer(
          builder: (ctx, ref, _) {
            final playerState = ref.watch(playerProvider);

            return Focus(
              autofocus: true,
              focusNode: FocusNode(debugLabel: 'GlobalAppFocus'),
              onKeyEvent: (node, event) {
                final isKeyDown = event is KeyDownEvent;
                if (isKeyDown) {
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
                  child!,
                  if (showOverlay)
                    _buildLoadingScreen(),
                ],
              ),
            );
          },
        );
      },
      home: const HomeScreen(),
    );
  }

  Widget _buildLoadingScreen() {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "Sondra",
              style: TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 24),
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF8B5CF6)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
