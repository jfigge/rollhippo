import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:rollhippo/app/scan_screen.dart';
import 'package:rollhippo/tray/tray.dart';

/// The scanner screen itself, driven through the callback the camera would
/// call. `menu_test.dart` drives the seam this pops *back* through, which is
/// where the picker's own limits are applied; what is exercised here is the
/// screen in between — which of the codes the camera finds it acts on, and how
/// many times it is willing to leave.
///
/// It needs no camera. The preview renders as a placeholder under a test
/// binding and the chrome around it is ordinary widgets, so the only thing
/// standing in for hardware is [detect].
void main() {
  const DieSpec white = DieSpec(kind: DieKind.d6, colour: kDiceWhite);
  const Profile oneDie = Profile(
    mode: ProfileMode.dice,
    groups: <List<DieSpec>>[
      <DieSpec>[white],
    ],
    cards: <CardSet>[
      CardSet(colours: <int>[kDiceWhite], decks: 1, reshuffleAt: 0),
      kEmptyShoe,
      kEmptyShoe,
    ],
  );

  /// Puts a scanner over a screen that says HOME, and collects whatever it
  /// pops back with. If it ever pops twice, HOME goes with it — which is the
  /// whole of what the last test here is about.
  Future<List<ScannedProfile?>> open(WidgetTester tester) async {
    final List<ScannedProfile?> popped = <ScannedProfile?>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder:
              (BuildContext context) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () async {
                      popped.add(
                        await Navigator.of(context).push(
                          MaterialPageRoute<ScannedProfile>(
                            builder: (_) => const ScanScreen(),
                          ),
                        ),
                      );
                    },
                    child: const Text('HOME'),
                  ),
                ),
              ),
        ),
      ),
    );
    await tester.tap(find.text('HOME'));
    await tester.pumpAndSettle();
    expect(find.text('Close'), findsOneWidget, reason: 'the scanner is up');
    return popped;
  }

  /// One frame of camera, carrying one code.
  void detect(WidgetTester tester, String raw) {
    tester.widget<MobileScanner>(find.byType(MobileScanner)).onDetect!(
      BarcodeCapture(barcodes: <Barcode>[Barcode(rawValue: raw)]),
    );
  }

  testWidgets('a Roll Hippo code is what it comes back with', (
    WidgetTester tester,
  ) async {
    final List<ScannedProfile?> popped = await open(tester);

    detect(tester, encodeProfile(oneDie, name: 'Yahtzee'));
    await tester.pumpAndSettle();

    expect(popped.single?.name, 'Yahtzee');
    expect(popped.single?.profile, oneDie);
    expect(find.text('HOME'), findsOneWidget);
  });

  testWidgets('anything else earns a line, and the camera keeps running', (
    WidgetTester tester,
  ) async {
    final List<ScannedProfile?> popped = await open(tester);

    detect(tester, 'https://example.com/a-poster-on-the-wall');
    await tester.pump();
    expect(find.textContaining('not a Roll Hippo one'), findsOneWidget);
    expect(popped, isEmpty, reason: 'a wrong code must not close the scanner');

    // And again, which is what a camera held on the same poster does several
    // times a second. Still one line, still open.
    detect(tester, 'https://example.com/a-poster-on-the-wall');
    await tester.pump();
    expect(find.textContaining('not a Roll Hippo one'), findsOneWidget);
    expect(popped, isEmpty);
  });

  testWidgets('closed first, a code arriving on the way out takes nothing', (
    WidgetTester tester,
  ) async {
    final List<ScannedProfile?> popped = await open(tester);

    await tester.tap(find.text('Close'));
    // Part way through the exit transition. The route is still mounted and the
    // camera has not stopped, so a code really can arrive here — and the pop
    // it used to send came off HOME.
    await tester.pump(const Duration(milliseconds: 40));
    detect(tester, encodeProfile(oneDie, name: 'Yahtzee'));
    await tester.pumpAndSettle();

    expect(popped.single, isNull, reason: 'Close comes back with nothing');
    expect(
      find.text('HOME'),
      findsOneWidget,
      reason: 'the second pop came off the screen underneath',
    );
  });
}
