import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app/config_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  // Belt and braces with the Info.plist: the tray's walls are fixed to the
  // screen while gravity comes from the accelerometer, so letting the screen
  // re-orient as the phone tips would rotate the tray out from under the dice
  // while down carried on pointing the same way.
  SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
  ]);
  runApp(const RollHippoApp());
}

class RollHippoApp extends StatelessWidget {
  const RollHippoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Roll Hippo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: const ConfigScreen(),
    );
  }
}
