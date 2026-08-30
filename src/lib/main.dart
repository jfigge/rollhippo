import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app/picker_screen.dart';
import 'app/profiles.dart';
import 'app/settings.dart';
import 'motion/motion.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // First, because it is the only thing here that wants wall-clock time rather
  // than a platform answer: a second of accelerometer, stirred into the pool a
  // shuffle takes its seed from and then let go of again. Started before
  // everything below so it gathers while the two loads are waiting, and it
  // returns at once — a shoe built before it has finished simply seeds from
  // what is in the pool by then, which is one of the reasons the clock is in
  // there as well. See [tapMotionForEntropy].
  tapMotionForEntropy();
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
  // And this is the one place that knows a launch is a launch. The picker is
  // also built by the tools that render the store screenshots and by every
  // widget test in the suite, and none of those is a first run — so the
  // question is answered here and handed down, rather than asked by the screen
  // that would have to answer it the same way every time.
  runApp(RollHippoApp(tutorial: !settings.tutorialSeen));
}

class RollHippoApp extends StatelessWidget {
  const RollHippoApp({super.key, this.tutorial = false});

  /// Whether the picker opens with the tutorial over it. See
  /// [Settings.tutorialSeen], which is the only thing that ever says yes.
  final bool tutorial;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Roll Hippo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: PickerScreen(tutorial: tutorial),
    );
  }
}
