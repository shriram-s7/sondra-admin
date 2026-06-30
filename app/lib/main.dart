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

  try {
    globalAudioHandler = await AudioService.init(
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
                ],
              ),
            );
          },
        );
      },
      home: const AppEntryPoint(),
    );
  }
}

class AppEntryPoint extends StatelessWidget {
  const AppEntryPoint({super.key});

  @override
  Widget build(BuildContext context) {
    return const HomeScreen();
  }
}
