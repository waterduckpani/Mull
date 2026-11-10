import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mull/data/store.dart';
import 'package:mull/main.dart';
import 'package:mull/screens/groups/group_bar.dart';
import 'package:mull/screens/home/home_shell.dart';
import 'package:mull/ui/icons.dart';
import 'package:mull/ui/sheet.dart';
import 'package:mull/ui/tab_bar.dart';

/// The light-theme captures the App Store reel (films/appstore-reel) is cut
/// from. Same sample data as tour_test, with Appearance set to Light first.
/// The profile sheet is never captured: the sample profile is a real name.
///
/// Run: flutter drive --driver=test_driver/integration_test.dart \
///        --target=integration_test/reel_tour_test.dart
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  Future<void> settle(WidgetTester t, [int ms = 900]) async {
    for (var i = 0; i < ms ~/ 50; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
  }

  Finder glyph(MullGlyph g) =>
      find.byWidgetPredicate((w) => w is MullIcon && w.glyph == g).hitTestable().last;

  Future<void> tapText(WidgetTester t, String text) async {
    if (find.text(text).hitTestable().evaluate().isEmpty &&
        find.text(text).evaluate().isNotEmpty) {
      await t.drag(find.byType(Scrollable).last, const Offset(0, -220));
      await settle(t, 600);
    }
    await t.tap(find.text(text).hitTestable().last);
    await settle(t);
  }

  Future<void> shot(WidgetTester t, String name) async {
    await settle(t, 400);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await t.pump();
    await binding.takeScreenshot('reel/$name');
  }

  Future<void> dismissSheet(WidgetTester t) async {
    for (var i = 0; i < 4 && SheetDepth.value.value > 0; i++) {
      await t.tapAt(const Offset(200, 24));
      await settle(t, 700);
    }
  }

  /// A tab in the group's bar, by its icon: only the open tab shows a name.
  Future<void> tapTab(WidgetTester t, GroupTab tab) async {
    await t.tap(
      find.descendant(
        of: find.byType(GroupBar),
        matching: find.byWidgetPredicate((w) => w is MullIcon && w.glyph == tab.glyph),
      ),
    );
    await settle(t, 700);
  }

  /// The + in the group's bar.
  Future<void> tapAdd(WidgetTester t) async {
    await t.tap(
      find.descendant(
        of: find.byType(GroupBar),
        matching: find.byWidgetPredicate((w) => w is MullIcon && w.glyph == MullGlyph.plus),
      ),
    );
    await settle(t);
  }

  /// A tab in the home bar, by its icon; only the bar on screen is hit-testable.
  Future<void> tapHome(WidgetTester t, HomeTab tab) async {
    await t.tap(
      find
          .descendant(
            of: find.byType(MullTabBar),
            matching: find.byWidgetPredicate((w) => w is MullIcon && w.glyph == tab.glyph),
          )
          .hitTestable()
          .first,
    );
    await settle(t, 700);
  }

  Future<void> back(WidgetTester t) async {
    await t.tap(glyph(MullGlyph.chevronLeft));
    await settle(t, 700);
  }

  testWidgets('reel tour', (t) async {
    final store = MullStore.memory()..loadSample();
    await t.pumpWidget(MullApp(store: store));
    await settle(t, 2500);
    if (find.text('Continue on this phone').evaluate().isNotEmpty) {
      await tapText(t, 'Continue on this phone');
      await settle(t, 1500);
    }

    // Light first. Nothing on the You tab is captured.
    await tapHome(t, HomeTab.you);
    await tapText(t, 'Light');
    await settle(t);
    await tapHome(t, HomeTab.home);
    await settle(t, 1200);

    await shot(t, 'home');

    await tapText(t, 'Check');
    await shot(t, 'claim-check');
    await dismissSheet(t);

    final more = find.textContaining(RegExp(r'^\d+ more$'));
    if (more.evaluate().isNotEmpty) {
      await t.tap(more.first);
      await settle(t);
    }
    await t.tap(find.text('Open it').hitTestable().first);
    await settle(t);
    await shot(t, 'recurring-due');
    await dismissSheet(t);

    await tapHome(t, HomeTab.groups);
    await tapText(t, 'Goa trip');
    await shot(t, 'group-detail');

    await t.scrollUntilVisible(find.text('SETTLE UP'), 220, scrollable: find.byType(Scrollable).hitTestable().last);
    await settle(t, 600);
    await shot(t, 'settle-up');

    await tapTab(t, GroupTab.ledger);
    await shot(t, 'ledger-expenses');
    await tapTab(t, GroupTab.overview);

    await tapAdd(t);
    await t.enterText(find.byType(TextField).at(0), 'Kayaking');
    await t.enterText(find.byType(TextField).at(1), '2600');
    FocusManager.instance.primaryFocus?.unfocus();
    await settle(t);
    await shot(t, 'add-expense');
    await tapText(t, 'Next');
    await shot(t, 'add-expense-split');
    await tapText(t, 'Add it');
    await settle(t, 900);
    await shot(t, 'group-after-expense');
    await back(t);

    await tapHome(t, HomeTab.home);
    await t.drag(find.byType(Scrollable).hitTestable().first, const Offset(0, 900));
    await settle(t, 800);
    await t.tap(find.textContaining('owed to you').hitTestable().last);
    await settle(t, 900);
    expect(find.text('YOU OWE').hitTestable(), findsOneWidget);
    await shot(t, 'who-owes-who');

    await t.tap(find.text('Sahil').hitTestable().first);
    await settle(t, 900);
    expect(find.text('ACROSS'), findsOneWidget);
    await shot(t, 'one-person');
    await dismissSheet(t);
    await tapHome(t, HomeTab.home);

    // The claim, confirmed: the card leaves the home screen.
    await tapText(t, 'Check');
    await tapText(t, 'It arrived');
    await settle(t, 1200);
    await shot(t, 'home-after-arrived');
  });
}
