import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../tray/tray.dart';
import 'menu.dart';
import 'page_dots.dart';
import 'profile_row.dart';
import 'settings.dart';
import 'tray_screen.dart';

/// The three things a page of this tutorial points at that had no name before
/// it did.
///
/// Here rather than in `picker_screen.dart` because of which way those two
/// files import. The picker is what opens the tutorial and what builds the
/// screens it draws behind itself, so the tutorial may not reach into the
/// picker for anything at all — it can only be reached *from* there. So the
/// picker tags these three widgets and the pages below name them, and neither
/// file has to import the other. `profile_row.dart` keeps the same rule and
/// pays for it with a duplicated constant; this is the cheaper end of the same
/// bargain.
///
/// The other four spots already had names for other reasons and are imported
/// from where they were: [kNewProfile], [kAppMenu], [kTrayThrow], [kTrayDots].
const Key kCardPanel = ValueKey<String>('card-panel');
const Key kRack = ValueKey<String>('rack');
const Key kRollButton = ValueKey<String>('roll-button');

/// The tutorial's own root, so a test — or anything else that wants to know
/// whether it is up — can ask without matching on a private type.
const Key kTutorial = ValueKey<String>('tutorial');

/// The card of words, which is a much smaller thing than [kTutorial].
///
/// Worth telling apart, because the root now holds whole screens: both of the
/// backdrop pickers have a rack, a row of dots and a page view of their own,
/// so anything looking for the tutorial's *controls* has to say so.
const Key kTutorialCard = ValueKey<String>('tutorial-card');

/// How much air is left round a spot, how round the hole's corners are, and
/// how far off the edge of the hole the card sits.
const double _kSpotPad = 8;
const double _kSpotRadius = 16;
const double _kNear = 10;

/// Everything a card is besides the words: both paddings, the button row and
/// the margin round the outside.
///
/// Only used to work out whether the words will fit in the gap the card has
/// been given, so an approximation is what it is for — it is compared against
/// a gap that is normally two or three times the whole card.
const double _kCardChrome = 118;

/// How dark everything that is *not* the spot goes.
///
/// Two thirds rather than the four fifths a modal barrier would use. The point
/// of the scrim here is to say which part of the screen the card is talking
/// about, not to take the screen away — the page behind is the thing being
/// explained, and an explanation you cannot see the subject of is a worse
/// explanation. What buys the contrast back is that the spot itself is not
/// dimmed at all.
const Color _kScrim = Color(0xA6000000);

/// The smallest the block of words is ever squeezed to.
///
/// Only reached on a screen where the gap beside the spot cannot take the
/// whole card — see [_kCardChrome]. Below this a page is a heading with a line
/// and a half under it, which is not worth showing; better to let the card
/// lean over the spot by a few points than to shrink it into nothing.
const double _kMinWords = 96;

/// The mark beside a heading, and the air under the heading row.
///
/// Named because two things have to agree about them: [_Words] draws with
/// them and [_wordsHeight] measures with them, and a block measured against
/// one set of numbers and drawn with another is a block that clips.
const double _kMarkSize = 38;
const double _kMarkGap = 12;
const double _kTitleGap = 10;

/// The two type styles a page is made of, for the same reason.
const TextStyle _kTitleStyle = TextStyle(
  color: Color(0xFFE8EEF6),
  fontSize: 18,
  fontWeight: FontWeight.w600,
  letterSpacing: -0.3,
);
const TextStyle _kBodyStyle = TextStyle(
  color: Color(0x99BFD0E4),
  fontSize: 14,
  height: 1.45,
);

/// Which screen stands behind a page of the tutorial.
///
/// Not decoration. Each page is about something you can point at, so the
/// screen it is pointed at has to be the one on the glass — and the picker
/// alone cannot serve all seven, because two of the pages are about the tray
/// and one is about the card page you would have to swipe to reach.
enum TutorialStage { dice, cards, tray }

/// How the tutorial gets those screens.
///
/// Handed in rather than built here. See the note on [kRack] above: the picker
/// opens the tutorial, so the tutorial cannot build a picker.
typedef TutorialBackdrop = Widget Function(TutorialStage stage);

/// The set-up every backdrop is built from.
///
/// Three sets with something in each, because one of the pages is about there
/// being three and a backdrop with one filled dot would be illustrating the
/// opposite of what the page says. Assorted kinds and colours for the same
/// reason the page about the rack exists: a rack of five identical white D6s
/// does not show you that a die has a kind and a colour to change.
///
/// It is nobody's saved profile and is never written anywhere. The backdrop is
/// a picture of the app, and a picture of the app has to be a picture of the
/// app in use.
const Profile kTutorialProfile = Profile(
  mode: ProfileMode.dice,
  groups: _kTutorialGroups,
  colours: _kTutorialCard,
  decks: 2,
  reshuffleAt: 5,
);

/// The same set-up, on the other page. See [TutorialStage.cards].
const Profile kTutorialCards = Profile(
  mode: ProfileMode.cards,
  groups: _kTutorialGroups,
  colours: _kTutorialCard,
  decks: 2,
  reshuffleAt: 5,
);

const List<List<DieSpec>> _kTutorialGroups = <List<DieSpec>>[
  <DieSpec>[
    DieSpec(kind: DieKind.d6, colour: kDiceWhite),
    DieSpec(kind: DieKind.d6, colour: kDiceWhite),
    DieSpec(kind: DieKind.d20, colour: 0xFF3F6FA8),
    DieSpec(kind: DieKind.d4, colour: 0xFFB3453F),
    DieSpec(kind: DieKind.d12, colour: 0xFF4A8A55),
  ],
  <DieSpec>[
    DieSpec(kind: DieKind.d6, colour: 0xFFD8B23A),
    DieSpec(kind: DieKind.d6, colour: 0xFFD8B23A),
  ],
  <DieSpec>[DieSpec(kind: DieKind.d20, colour: 0xFF7B5AA6)],
];

const List<int> _kTutorialCard = <int>[kDiceWhite, 0xFFB3453F];

/// One page of the tutorial.
///
/// A page is a heading, one paragraph, the screen it is said in front of, and
/// the one thing on that screen it is about. It is deliberately no more than
/// that: this is read once, by somebody who has just opened the app and wants
/// to get to the dice. Anything that needs a second paragraph is a thing the
/// screen itself should be saying — the picker's subtitle and the "press and
/// hold for options" beside the Profiles heading are both there for exactly
/// that reason.
@immutable
class TutorialPage {
  const TutorialPage({
    required this.icon,
    required this.title,
    required this.body,
    required this.stage,
    this.spot,
  });

  final IconData icon;
  final String title;
  final String body;

  /// Which screen is behind the card while this page is up.
  final TutorialStage stage;

  /// The key of the thing on that screen the page is about — the part left
  /// undimmed and ringed. Null for a page about a screen as a whole, which
  /// dims the lot evenly.
  final Key? spot;
}

/// What the tutorial says, in the order the app is used.
///
/// Set up a roll, keep it, take it to the tray, throw it, and only then the
/// two things that are true of the whole app — the second and third sets of
/// dice, and the menu in the corner. A first-time reader who stops halfway
/// through has still been told everything needed to roll some dice, which is
/// the order to write this in and not the order the code is in.
///
/// The first page is said over the *card* page and the second over the dice
/// page, which means the backdrop performs the swipe the first page describes
/// at the moment you leave it. That is the one piece of staging here doing
/// more than illustrating.
///
/// Public because it is the content rather than the machinery: a test asserts
/// that every gesture the app has no room to advertise is named here, and that
/// is the assertion worth having about a tutorial.
const List<TutorialPage> kTutorialPages = <TutorialPage>[
  TutorialPage(
    icon: Icons.style_outlined,
    title: 'Dice, or cards',
    stage: TutorialStage.cards,
    spot: kCardPanel,
    body:
        'Roll Hippo is a tray of dice and a shoe of cards, and it is equally '
        'both — a card stands for one roll of the dice it replaces. Swipe the '
        'panel under the rack left or right to change page, and the dots '
        'below it say which one you are on.',
  ),
  TutorialPage(
    icon: Icons.casino_outlined,
    title: 'Fill the rack',
    stage: TutorialStage.dice,
    spot: kRack,
    body:
        'Tap a die to select it, then give it a kind and a colour with the '
        'chips and swatches underneath. The + in the last slot adds another — '
        'ten of them on the dice page, three on a card.',
  ),
  TutorialPage(
    icon: Icons.bookmark_border,
    title: 'Keep it as a profile',
    stage: TutorialStage.dice,
    spot: kNewProfile,
    body:
        'Tap + New to save what is on screen under a name, and tap a profile '
        'to open it again. Press and hold one — or hold + New itself — for '
        'its menu: Save, Rename, Share and Delete, and on + New, Reset.',
  ),
  TutorialPage(
    icon: Icons.play_circle_outline,
    title: 'Roll, or Deal',
    stage: TutorialStage.dice,
    spot: kRollButton,
    body:
        'The button along the bottom is named for the page you are on. Roll '
        'opens the tray with your dice lying in it; Deal shuffles the shoe '
        'and puts it on the table.',
  ),
  TutorialPage(
    icon: Icons.vibration,
    title: 'Throw, or Draw',
    stage: TutorialStage.tray,
    spot: kTrayThrow,
    body:
        'Shake the phone to throw the dice, or to turn the next card over. '
        'Throw — Draw, on the cards — at the top of the screen does the same '
        'thing without moving the phone. The dice behind this card are real: '
        'shake it now and they will go.',
  ),
  TutorialPage(
    icon: Icons.swipe_outlined,
    title: 'Three sets at once',
    stage: TutorialStage.tray,
    spot: kTrayDots,
    body:
        'In the tray, swipe sideways for another set of dice. They are three '
        'separate rolls rather than three views of one, so each keeps the '
        'numbers it landed on until you shake it again.',
  ),
  TutorialPage(
    icon: Icons.tune,
    title: 'Settings, and this again',
    stage: TutorialStage.dice,
    spot: kAppMenu,
    body:
        'The menu in the top left corner holds Settings, where motion control '
        'can be turned off — the tray is then handed a phone lying perfectly '
        'still, and Throw and Draw are the whole interface. How to use, at '
        'the bottom of that menu, brings this back.',
  ),
];

/// Puts the tutorial up, and remembers that it has been up.
///
/// The flag is written here rather than at either call site because both of
/// them mean the same thing by it: the app has now shown somebody the
/// tutorial, so it must not put it in front of the picker again on its own.
/// Reaching it from the menu afterwards is a request rather than an offer, and
/// setting a flag that is already set costs nothing — see [Settings].
///
/// Written on the way out rather than on the way in, and that is the whole of
/// the difference: an app killed while the tutorial is open has not shown it
/// to anybody, and offering it again on the next launch is the right thing for
/// that to mean.
///
/// A route rather than a sheet, because the tutorial owns the whole screen
/// now: it brings its own backdrop, where a sheet would have been a hole cut
/// in somebody else's. It is still see-through, so what it opens over and
/// closes back onto is the real picker.
Future<void> showTutorial(
  BuildContext context, {
  required TutorialBackdrop backdrop,
}) async {
  await Navigator.of(context).push(
    PageRouteBuilder<void>(
      // The backdrop is opaque and covers everything, but the route is not:
      // that is what makes opening and closing a cross-fade with the screen it
      // was asked for from, rather than a cut.
      opaque: false,
      // The barrier is transparent and does not dismiss. A modal route builds
      // one either way, which is what stops a tap landing on the picker
      // underneath; getting out is Skip, Done, or the system back gesture.
      barrierDismissible: false,
      transitionDuration: const Duration(milliseconds: 320),
      reverseTransitionDuration: const Duration(milliseconds: 220),
      pageBuilder:
          (
            BuildContext context,
            Animation<double> animation,
            Animation<double> secondary,
          ) => _TutorialScreen(backdrop: backdrop),
      transitionsBuilder:
          (
            BuildContext context,
            Animation<double> animation,
            Animation<double> secondary,
            Widget child,
          ) => FadeTransition(opacity: animation, child: child),
    ),
  );
  settings.tutorialSeen = true;
}

/// The tutorial: seven pages you swipe through, each said in front of the
/// screen it is about, with the part it is about left undimmed.
///
/// Pages, and swiped, on purpose. The first thing this app asks of a finger is
/// a sideways swipe — between the two modes, and between the three sets of
/// dice — and it is the one gesture on the picker that nothing on screen can
/// advertise. So the tutorial is built out of the gesture it is explaining,
/// under the same [PageDots] the picker and the tray put under theirs: by the
/// time it says "swipe the panel", the reader has already done it six times.
/// Next is there for the same reason a tapped dot is on the picker — a swipe
/// you have not been taught yet is a swipe you cannot use to be taught it.
class _TutorialScreen extends StatefulWidget {
  const _TutorialScreen({required this.backdrop});

  final TutorialBackdrop backdrop;

  @override
  State<_TutorialScreen> createState() => _TutorialScreenState();
}

class _TutorialScreenState extends State<_TutorialScreen> {
  final PageController _pages = PageController();

  /// One key per stage, made once and kept.
  ///
  /// A [GlobalKey] may never be on two elements at the same time, and these
  /// never can be: a stage is built at most once for the whole life of the
  /// tutorial and then stays built, so there is never a second instance of one
  /// to carry the same key. That is what makes them safe for the single thing
  /// they are for, which is scoping the search for a spot to the screen the
  /// page is actually about — both pickers have a rack and a Roll button, and
  /// a search across the whole tree would be a coin toss between them.
  final Map<TutorialStage, GlobalKey> _stages = <TutorialStage, GlobalKey>{
    for (final TutorialStage stage in TutorialStage.values)
      stage: GlobalKey(debugLabel: 'tutorial-${stage.name}'),
  };

  int _at = 0;

  /// Where the hole is, in this screen's own coordinates, or null for a page
  /// with nothing to point at. Measured off the real render tree rather than
  /// written down, because a rectangle written down is a rectangle that is
  /// wrong on the next phone.
  Rect? _spot;

  /// False until the first measurement has been taken. The scrim is not drawn
  /// before then: a hole that opened a frame after the dark arrived would be a
  /// flash of the whole screen going black, on the one frame somebody is
  /// certain to be looking at.
  bool _measured = false;

  /// Whether the tray has been reached yet.
  ///
  /// The two pickers cost nothing to keep built and are up from the start. The
  /// tray is not: it is a live simulation with an accelerometer behind it and
  /// a haptic in front, and one running under a page about something else
  /// would tap the phone about dice nobody can see. So it is built the moment
  /// a page needs it — which also means the throw it opens with happens in
  /// front of you, on the page that is telling you how to throw.
  bool _trayShown = false;

  TutorialPage get _page => kTutorialPages[_at];

  bool get _last => _at == kTutorialPages.length - 1;

  @override
  void initState() {
    super.initState();
    _measureSoon();
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  /// After the frame, because a spot cannot be measured until the thing it is
  /// on has been laid out — and on the page that first needs the tray, that
  /// thing does not exist until this build has finished.
  void _measureSoon() =>
      WidgetsBinding.instance.addPostFrameCallback((Duration _) {
        if (mounted) _measure();
      });

  void _measure() {
    final Rect? spot = _spotOf(_page);
    if (_measured && spot == _spot) return;
    setState(() {
      _spot = spot;
      _measured = true;
    });
  }

  Rect? _spotOf(TutorialPage page) {
    final Key? spot = page.spot;
    final BuildContext? stage = _stages[page.stage]?.currentContext;
    final RenderObject? self = context.findRenderObject();
    if (spot == null || stage == null || self is! RenderBox) return null;
    final RenderBox? box = _findByKey(stage, spot);
    if (box == null) return null;
    return self.globalToLocal(box.localToGlobal(Offset.zero)) & box.size;
  }

  /// The first laid-out box under [root] carrying [key].
  ///
  /// A walk rather than a lookup because there is no lookup: only a
  /// [GlobalKey] can be asked where it is, and a global key on something the
  /// picker draws would collide the instant the tutorial built a second picker
  /// to stand behind itself. A [ValueKey] cannot collide and cannot be asked,
  /// so this asks the tree instead — once per page, over one screen's worth of
  /// elements.
  RenderBox? _findByKey(BuildContext root, Key key) {
    RenderBox? found;
    void visit(Element element) {
      if (found != null) return;
      if (element.widget.key == key) {
        final RenderObject? object = element.findRenderObject();
        if (object is RenderBox && object.hasSize) {
          found = object;
          return;
        }
      }
      element.visitChildren(visit);
    }

    root.visitChildElements(visit);
    return found;
  }

  void _onPage(int page) {
    setState(() {
      _at = page;
      if (kTutorialPages[page].stage == TutorialStage.tray) _trayShown = true;
    });
    _measureSoon();
  }

  void _goTo(int page) => _pages.animateToPage(
    page,
    duration: const Duration(milliseconds: 280),
    curve: Curves.easeOutCubic,
  );

  /// Next, or Done on the last page — which is the only button here with two
  /// jobs, because on the last page there is nowhere left to go.
  void _next() {
    if (_last) {
      Navigator.of(context).pop();
      return;
    }
    _goTo(_at + 1);
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      key: kTutorial,
      type: MaterialType.transparency,
      // Sized off the room there actually is rather than off what [MediaQuery]
      // says the window is. They are the same on a phone held normally and
      // they are not in split screen, on a foldable being opened, or in the
      // harness — and this is the number the card is placed and sized by, so
      // it has to be the one the card is being laid into. `render_test.dart`
      // holds the same line for the tray's camera.
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final Size screen = constraints.biggest;
          final EdgeInsets safe = MediaQuery.paddingOf(context);
          final Rect? spot = _spot;
          // Which side of the spot the card goes: the roomier one. Not the
          // opposite half of the screen — a spot lying across the middle, and
          // the card panel the first page points at is one, leaves that rule
          // with nowhere that works. A page with nothing to point at has all
          // the room there is and takes the bottom, which is where a hand is.
          final bool above =
              spot == null || spot.top > screen.height - spot.bottom;
          final double room =
              spot == null
                  ? screen.height
                  : above
                  ? spot.top
                  : screen.height - spot.bottom;
          // The gap, as an inset. A page with no spot has the whole screen and
          // takes the bottom of it, which is the same padding either way — the
          // alignment is what decides. The safe area is added on the far side
          // only: the near side is measured off a widget that is already
          // inside it.
          final EdgeInsets place =
              spot == null
                  ? EdgeInsets.only(top: safe.top, bottom: safe.bottom)
                  : above
                  ? EdgeInsets.only(
                    top: safe.top,
                    bottom: screen.height - spot.top + _kNear,
                  )
                  : EdgeInsets.only(
                    top: spot.bottom + _kNear,
                    bottom: safe.bottom,
                  );
          return Stack(
            fit: StackFit.expand,
            children: <Widget>[
              for (final TutorialStage stage in TutorialStage.values)
                _stage(stage),
              if (_measured)
                Positioned.fill(
                  // The scrim is drawn, not touched. Every tap on this screen
                  // belongs to the card.
                  child: IgnorePointer(
                    child: TweenAnimationBuilder<Rect?>(
                      // The first build takes the spot as it is; only a
                      // *change* of end animates, which is what carries the
                      // hole from one page to the next instead of cutting to
                      // it.
                      tween: RectTween(end: spot),
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOutCubic,
                      builder:
                          (BuildContext context, Rect? at, Widget? child) =>
                              CustomPaint(painter: TutorialSpotlight(spot: at)),
                    ),
                  ),
                ),
              // The card is hung off the edge of the hole rather than dropped
              // to the bottom of the screen, and that is not a matter of
              // taste. The tray is the backdrop for two of these pages, and
              // dice settle along the *floor* of it — so a card docked to the
              // bottom would cover the one thing those two pages are asking
              // you to look at, on the page whose whole claim is that the dice
              // behind it are real. Tucked against the spot instead, it points
              // at what it is naming and leaves the rest of the screen alone.
              //
              // The padding is what confines it to the gap and the alignment
              // is what pushes it up against the spot; both are animated,
              // because between two pages the card has to travel rather than
              // reappear.
              AnimatedPadding(
                padding: place,
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeOutCubic,
                child: AnimatedAlign(
                  alignment:
                      above ? Alignment.bottomCenter : Alignment.topCenter,
                  duration: const Duration(milliseconds: 320),
                  curve: Curves.easeOutCubic,
                  child: _card(room),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// One backdrop, laid out whether or not it is the one being shown.
  ///
  /// Laid out always and painted sometimes, which is exactly what [Opacity] at
  /// zero does — and it is that difference the spotlight is built on: a screen
  /// taken out of the tree would have no rectangle to measure when the page
  /// about it arrives, and the hole would open a frame late every time.
  Widget _stage(TutorialStage stage) {
    if (stage == TutorialStage.tray && !_trayShown) {
      return const SizedBox.shrink();
    }
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: stage == _page.stage ? 1 : 0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
        child: KeyedSubtree(key: _stages[stage], child: widget.backdrop(stage)),
      ),
    );
  }

  Widget _card(double room) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: kSheetWidth),
      child: Container(
        key: kTutorialCard,
        margin: const EdgeInsets.all(14),
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
        decoration: BoxDecoration(
          // Opaque, and the same card the Settings and Share sheets are drawn
          // on. It was translucent for a while, on the theory that a sliver of
          // the screen behind would say the card was sitting on top of it —
          // and what that actually looked like was a paragraph with somebody
          // else's text smeared under it, because what is behind this card is
          // a whole screen rather than a wash. The shadow and the hairline say
          // the same thing without printing through.
          color: const Color(0xFF141A23),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0x1FFFFFFF)),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Color(0x73000000),
              blurRadius: 28,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints inner) {
            // The tallest page there is, held to what the gap can take.
            final double words = math.min(
              _wordsHeight(
                inner.maxWidth,
                MediaQuery.textScalerOf(context),
                DefaultTextStyle.of(context).style,
              ),
              math.max(_kMinWords, room - _kCardChrome),
            );
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                SizedBox(
                  height: words,
                  child: PageView(
                    controller: _pages,
                    onPageChanged: _onPage,
                    children: <Widget>[
                      for (final TutorialPage page in kTutorialPages)
                        _Words(page: page),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: <Widget>[
                    // The dots are what gives way when the row runs out of
                    // width, and they are the right thing to: seven of them,
                    // two buttons and a wide text scale do not fit a narrow
                    // phone, and of the three the dots are the one you can
                    // still read at four fifths the size. The buttons keep
                    // their tap targets, which is the reason for choosing.
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: PageDots(
                          current: _at,
                          // Every page has something on it. The hollow ring
                          // the picker uses for a set with no dice in it has
                          // nothing to say here, and the dots are still worth
                          // having: they are how you know how much is left.
                          filled: List<bool>.filled(
                            kTutorialPages.length,
                            true,
                          ),
                          onTap: _goTo,
                        ),
                      ),
                    ),
                    const Spacer(),
                    // Skip goes when there is nothing left to skip. Leaving it
                    // beside a Done would be two buttons that do the same
                    // thing, one of them phrased as a regret.
                    if (!_last)
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xAABFD0E4),
                        ),
                        child: const Text(
                          'Skip',
                          style: TextStyle(fontSize: 15),
                        ),
                      ),
                    const SizedBox(width: 6),
                    FilledButton(
                      onPressed: _next,
                      style: FilledButton.styleFrom(
                        // The Roll button's blue: this is the one thing on the
                        // card you are being asked to press.
                        backgroundColor: const Color(0xFF3F6FA8),
                        foregroundColor: const Color(0xFFF2F7FF),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 22,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text(
                        _last ? 'Done' : 'Next',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// How tall the block of words has to be, at [width].
///
/// Measured rather than chosen, and measured across *every* page rather than
/// the one on screen. The block is one fixed height for all seven because the
/// dots and the buttons under it must not move as you swipe — a Next that
/// shifted under the thumb pressing it would be a control you have to chase —
/// and the only honest fixed height is the tallest page's. A number picked to
/// look about right is a number that is wrong on some phone: too big and every
/// short page carries a hand's width of nothing, too small and the longest one
/// scrolls, and which of the two you get depends on the width of the screen
/// and on a text scale the reader chose.
///
/// [scaler] is the reader's text size, and it is why this cannot be worked out
/// once: at twice the type the paragraph that needed four lines needs nine,
/// and the card simply has to be taller.
///
/// [base] is the style a [Text] would have started from, and passing it is not
/// optional. Neither [_kTitleStyle] nor [_kBodyStyle] names a font family —
/// nothing in this app does, because the family belongs to the theme — so a
/// [TextPainter] handed one of them bare is measuring in whatever face the
/// engine falls back to. That is the substitute face under `flutter test`,
/// which sets every glyph on a square body and is close to twice as wide as
/// the real one: the block came out half as tall again as the words in it,
/// with the difference sitting under the last line as a hand's width of
/// nothing. Merging the inherited style in is what makes the measurement and
/// the painting the same layout.
double _wordsHeight(double width, TextScaler scaler, TextStyle base) {
  final TextStyle title = base.merge(_kTitleStyle);
  final TextStyle body = base.merge(_kBodyStyle);
  double tallest = 0;
  for (final TutorialPage page in kTutorialPages) {
    // The heading sits beside the mark and can take two lines before it is cut
    // off, so the row is whichever of the two is deeper.
    final double heading = math.max(
      _kMarkSize,
      _measure(
        page.title,
        title,
        width - _kMarkSize - _kMarkGap,
        scaler,
        maxLines: 2,
      ),
    );
    tallest = math.max(
      tallest,
      heading + _kTitleGap + _measure(page.body, body, width, scaler),
    );
  }
  return tallest;
}

/// How tall [text] comes out, laid out the way [_Words] will lay it out.
double _measure(
  String text,
  TextStyle style,
  double width,
  TextScaler scaler, {
  int? maxLines,
}) {
  final TextPainter painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    textScaler: scaler,
    maxLines: maxLines,
  )..layout(maxWidth: math.max(0, width));
  final double height = painter.height;
  painter.dispose();
  return height;
}

/// What one page says.
///
/// Left-aligned, with the mark beside the heading rather than over it. This is
/// a label on the screen behind it rather than a slide, and a centred block of
/// text with a picture on top of it reads as the second thing.
///
/// Every measurement it draws with is a constant it shares with
/// [_wordsHeight], which works out how tall the block has to be by laying the
/// same strings out in the same styles. Inline a size here and the block is
/// measured against one page and drawn as another.
class _Words extends StatelessWidget {
  const _Words({required this.page});

  final TutorialPage page;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: _kMarkSize,
                height: _kMarkSize,
                decoration: BoxDecoration(
                  // The wash the selected slot in the rack is filled with, so
                  // the mark reads as the same material as the ring round the
                  // die you last tapped — and as the ring round the spot.
                  color: const Color(0x223F6FA8),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  page.icon,
                  size: 20,
                  color: const Color(0xFF6E9AD0),
                ),
              ),
              const SizedBox(width: _kMarkGap),
              Expanded(
                child: Text(
                  page.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: _kTitleStyle,
                ),
              ),
            ],
          ),
          const SizedBox(height: _kTitleGap),
          Text(page.body, style: _kBodyStyle),
        ],
      ),
    );
  }
}

/// The dark, with a hole in it.
///
/// The hole is not drawn — it is the part of the scrim that is not. So what
/// shows through is the backdrop at its own brightness, untinted and
/// unblurred, which is the whole point: the page names a thing, and the thing
/// is the only lit part of the screen.
///
/// Public for the reason [ShareCodeView] is: what it was handed is the whole
/// of what it does, and nothing outside this file could otherwise ask where
/// the tutorial thinks the thing it is talking about actually is.
class TutorialSpotlight extends CustomPainter {
  const TutorialSpotlight({required this.spot});

  /// In the tutorial screen's own coordinates. Null dims everything evenly,
  /// which is what a page with nothing to point at wants.
  final Rect? spot;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect screen = Offset.zero & size;
    final Paint dim = Paint()..color = _kScrim;
    final Rect? spot = this.spot;
    if (spot == null || spot.isEmpty) {
      canvas.drawRect(screen, dim);
      return;
    }

    final RRect hole = RRect.fromRectAndRadius(
      spot.inflate(_kSpotPad),
      const Radius.circular(_kSpotRadius),
    );
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(screen),
        Path()..addRRect(hole),
      ),
      dim,
    );

    // A blurred stroke and then a crisp one, in that order: the soft one is
    // light spilling onto the dark, and the hard one is the edge of the hole
    // itself. Both straddle the border, which is why the glow is the weaker
    // colour — half of it lands inside, on the thing being pointed at.
    canvas.drawRRect(
      hole,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..color = const Color(0x553F6FA8)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
    );
    canvas.drawRRect(
      hole,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = const Color(0xCC6E9AD0),
    );
  }

  @override
  bool shouldRepaint(TutorialSpotlight oldDelegate) => oldDelegate.spot != spot;
}
