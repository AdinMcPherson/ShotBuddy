import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ui/session_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Landscape-only, and not just for looks. The camera delivers frames in
  // sensor orientation; locking the app to landscape makes the preview and the
  // frame buffer share one coordinate space, so a tap on the rim in the preview
  // means the same thing to the detector. It also happens to be how you would
  // actually prop a phone to film a hoop.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  runApp(const ShotBuddyApp());
}

class ShotBuddyApp extends StatelessWidget {
  const ShotBuddyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ShotBuddy',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.orange,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const SessionScreen(),
    );
  }
}
