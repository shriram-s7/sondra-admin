import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:audio_service/audio_service.dart';
import 'services/audio_handler.dart';
import 'services/offline_storage.dart';
import 'providers/player_provider.dart';
import 'screens/setup_screen.dart';

// Global navigator key so the mini-player overlay can show modal sheets
// even when the context is above the navigator tree.
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize offline storage for offline playlists
  await OfflineStorage().init();

  // AudioService.init may fail silently on Windows/desktop; fall back to
  // direct handler so just_audio still works natively.
  try {
    globalAudioHandler = await AudioService.init(
      builder: () => SondraAudioHandler(),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.sondra.music.channel.audio',
        androidNotificationChannelName: 'Sondra Music Playback',
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

      // builder wraps the entire navigator stack, so the MiniPlayer
      // is rendered above ALL routes (home, playlists, now-playing, etc.)
      builder: (context, child) {
        return Consumer(
          builder: (ctx, ref, _) {
            final playerState = ref.watch(playerProvider);

            // Wrap in a global Focus widget to handle global Spacebar & 'P' keyboard shortcuts
            return Focus(
              autofocus: true,
              focusNode: FocusNode(debugLabel: 'GlobalAppFocus'),
              onKeyEvent: (node, event) {
                final isKeyDown = event is KeyDownEvent;
                if (isKeyDown) {
                  // Bypass hotkeys if a text input currently has active focus
                  final hasInputFocus = FocusManager.instance.primaryFocus?.context?.widget is EditableText;
                  if (hasInputFocus) return KeyEventResult.ignored;

                  final key = event.logicalKey;
                  if (key == LogicalKeyboardKey.space || 
                      key == LogicalKeyboardKey.keyP ||
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
                  // All app routes live inside `child`
                  child!,

                  // Android mobile floating mini-player overlay.
                  // Windows uses its own inline layout in HomeScreen.

                ],
              ),
            );
          },
        );
      },

      home: const SetupScreen(),
    );
  }
}
