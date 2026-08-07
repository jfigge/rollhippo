import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app/picker_screen.dart';
import 'app/profiles.dart';
import 'app/settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  // Belt and braces with the Info.plist: the tray's walls are fixed to the
  // screen while gravity comes from the accelerometer, so letting the screen
  // re-orient as the phone tips would rotate the tray out from under the dice
  // while down carried on pointing the same way.
  SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
  ]);
  // Before the first frame, not after it. The haptic calibration is read on
  // the way into the tray, and a tray that ran its first throw at the default
  // and then jumped to the stored value would be wrong exactly once — on the
  // throw the player was paying attention to.
  await settings.load();
  // The same reasoning, harder. The first thing the picker does is decide
  // whether to ask which profile to open, and it can only ask once — a
  // chooser that arrived a moment later would be a dialog thrown over a screen
  // the player had already started using.
  await profiles.load();
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
      home: const PickerScreen(),
    );
  }
}
