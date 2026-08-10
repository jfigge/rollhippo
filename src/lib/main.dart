import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app/picker_screen.dart';
import 'app/profiles.dart';
import 'app/settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Neither of these is waited for. They are requests to the platform about
  // how the window behaves, not work the first frame depends on — and the
  // orientation lock in particular is already in force before any of this
  // runs, because the Info.plist and the manifest set it. Awaiting them would
  // put two platform round trips in front of the launch to be told something
  // that is already true.
  unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky));
  // Belt and braces with the Info.plist: the tray's walls are fixed to the
  // screen while gravity comes from the accelerometer, so letting the screen
  // re-orient as the phone tips would rotate the tray out from under the dice
  // while down carried on pointing the same way.
  unawaited(
    SystemChrome.setPreferredOrientations(<DeviceOrientation>[
      DeviceOrientation.portraitUp,
    ]),
  );
  // Before the first frame, not after it. The haptic calibration is read on
  // the way into the tray, and a tray that ran its first throw at the default
  // and then jumped to the stored value would be wrong exactly once — on the
  // throw the player was paying attention to.
  await settings.load();
  // The same reasoning. The row of profiles is the first thing on the picker
  // that says what you have saved, and one that arrived a frame or two after
  // the screen did would flicker on every launch.
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
