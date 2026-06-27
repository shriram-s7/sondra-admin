import 'package:flutter/material';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:audio_service/audio_service.dart';
import 'services/audio_handler.dart';
import 'providers/player_provider.dart';
import 'screens/setup_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Register background Audio Handler
  globalAudioHandler = await AudioService.init(
    builder: () => SondraAudioHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.sondra.music.channel.audio',
      androidNotificationChannelName: 'Sondra Music Playback',
      androidNotificationOngoing: true,
      androidShowNotificationBadge: true,
    ),
  );

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
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: const Color(0xFF7C3AED),
        useMaterial3: true,
      ),
      home: const SetupScreen(),
    );
  }
}
