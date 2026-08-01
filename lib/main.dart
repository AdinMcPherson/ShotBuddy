import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ui/session_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Portrait and landscape both work. The camera delivers frames in sensor
  // orientation, which is landscape on every phone we care about, so portrait
  // needs the frame rotated before the detector sees it — FrameConverter does
  // that, driven by the orientation SessionScreen reports. Getting this wrong
  // is not subtle: the rim tap and the ball boxes stop agreeing.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  // Edge-to-edge rather than immersive: portrait puts real buttons near the
  // bottom of the screen, and hiding the nav bar under them is how you get
  // accidental back-swipes mid-session. SafeArea does the rest.
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

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
