import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mull/data/store.dart';
import 'package:mull/main.dart';
import 'package:mull/screens/groups/group_bar.dart';
import 'package:mull/screens/home/home_shell.dart';
import 'package:mull/screens/groups/icon_picker.dart';
import 'package:mull/ui/icons.dart';
import 'package:mull/ui/sheet.dart';
import 'package:mull/ui/tab_bar.dart';

/// Walks every screen with the mockup data, screenshotting each one.
///
/// Run: flutter drive --driver=test_driver/integration_test.dart \
///        --target=integration_test/tour_test.dart
///
/// Note for anyone changing this file: a target that fails to compile makes
/// `flutter drive` silently run the *previous* build, so a green run after an
/// edit proves nothing until `flutter analyze` is clean too.
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

  /// Taps a label, scrolling it into view first if it is below the fold.
  ///
  /// A plain `hitTestable()` finder is not enough on a screen whose length
  /// depends on the data — a group with a claim card on it pushes the last
  /// destination off a 6.3" phone, and the failure reads as "that widget does
  /// not exist" rather than "you cannot see it yet".
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
    await binding.takeScreenshot(name);
  }

  /// Backs out of every open sheet by tapping the scrim above them.
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

  /// A tab in the home bar, by its icon. Only the bar on screen is hit-testable,
  /// so a group open over the home tabs does not confuse it.
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

  Future<void> back(WidgetTester t) async {
    await t.tap(glyph(MullGlyph.chevronLeft));
    await settle(t, 700);
  }

  testWidgets('tour', (t) async {
    final store = MullStore.memory()..loadSample();
    await t.pumpWidget(MullApp(store: store));
    await settle(t, 2500);

    // A build with no Supabase keys stops at the local-build notice first.
    // The tour runs through `flutter drive`, which passes no dart-defines.
    if (find.text('Continue on this phone').evaluate().isNotEmpty) {
      await tapText(t, 'Continue on this phone');
      await settle(t, 1500);
    }

    // ---- 4A, the groups home
    await shot(t, '01-home');

    // ---- the claim waiting on you
    await tapText(t, 'Check');
    await shot(t, '02-claim-check');
    await dismissSheet(t);

    // ---- a schedule whose turn has come: behind the claim in the stack
    final more = find.textContaining(RegExp(r'^\d+ more$'));
    if (more.evaluate().isNotEmpty) {
      await t.tap(more.first);
      await settle(t);
    }
    await t.tap(find.text('Open it').hitTestable().first);
    await settle(t);
    await shot(t, '03-recurring-due');
    await dismissSheet(t);

    // ---- 4D, a group, from the Groups tab
    await tapHome(t, HomeTab.groups);
    await tapText(t, 'Goa trip');
    await shot(t, '04-group-detail');

    // ---- who is in it, and who runs it
    await tapTab(t, GroupTab.people);
    await shot(t, '04b-members');
    await tapTab(t, GroupTab.overview);

    // ---- the mark the group carries, and finding one by name: the badge
    // opens the name-and-icon sheet, and its icon opens the picker
    await t.tap(find.byType(GroupBadge).hitTestable().first);
    await settle(t, 700);
    await t.tap(find.byType(IconWell).hitTestable().last);
    await settle(t, 700);
    await shot(t, '04c-icon-picker');
    // The picker's search, on top: the first field is the group's name, in
    // the sheet underneath.
    await t.enterText(find.byType(TextField).last, 'beach');
    FocusManager.instance.primaryFocus?.unfocus();
    await settle(t);
    await shot(t, '04d-icon-search');
    await dismissSheet(t);

    // ---- 4E, settling up on the Overview, and the sheet a row opens
    await t.scrollUntilVisible(find.text('SETTLE UP'), 220, scrollable: find.byType(Scrollable).hitTestable().last);
    await settle(t, 600);
    await shot(t, '05-settle-up');
    await tapText(t, 'Kabir pays you');
    await shot(t, '05b-settle-sheet');
    await dismissSheet(t);

    // ---- 4F, the ledger, both tabs
    await tapTab(t, GroupTab.ledger);
    await shot(t, '06-ledger-expenses');
    await tapText(t, 'Settlements');
    await shot(t, '07-ledger-settlements');
    await tapText(t, 'Expenses');
    await tapTab(t, GroupTab.overview);

    // ---- adding an expense, from the + in the bar
    await tapAdd(t);
    await t.enterText(find.byType(TextField).at(0), 'Kayaking');
    await t.enterText(find.byType(TextField).at(1), '2600');
    FocusManager.instance.primaryFocus?.unfocus();
    await settle(t);
    await shot(t, '08-add-expense');
    await t.pump(const Duration(milliseconds: 100));
    await tapText(t, 'Next');
    await shot(t, '08b-add-expense-split');
    await tapText(t, 'Next');
    await shot(t, '08c-add-expense-bill');
    await tapText(t, 'Add it');
    await settle(t, 900);
    expect(
      store.groups.firstWhere((g) => g.name == 'Goa trip').expenses.map((e) => e.description),
      contains('Kayaking'),
    );
    await shot(t, '09-group-after-expense');
    await back(t);

    // ---- 4G, the flat, where the schedules live
    await tapText(t, 'Flat');
    await tapTab(t, GroupTab.recurring);
    await shot(t, '10-recurring');

    // ---- 4H, editing a standing cost
    await tapText(t, 'Flat maintenance');
    await shot(t, '11-recurring-editor');
    await dismissSheet(t);
    await back(t);

    // ---- where you stand with everyone, both directions: "see who" on Home
    // goes to the People tab
    await tapHome(t, HomeTab.home);
    await t.drag(find.byType(Scrollable).hitTestable().first, const Offset(0, 900));
    await settle(t, 800);
    await t.tap(find.textContaining('owed to you').hitTestable().last);
    await settle(t, 900);
    // Asserted, not assumed: a tap that lands on nothing still passes.
    expect(find.text('YOU OWE').hitTestable(), findsOneWidget);
    await shot(t, '12-who-owes-who');

    // ---- one person, netted across every ledger they are in
    await t.tap(find.text('Sahil').hitTestable().first);
    await settle(t, 900);
    expect(find.text('ACROSS'), findsOneWidget);
    await shot(t, '12b-one-person');
    await dismissSheet(t);

    // ---- 4B and 4C, starting something new, from the Groups tab
    await tapHome(t, HomeTab.groups);
    await tapText(t, '+ New group');
    await settle(t, 800);
    await shot(t, '13-name-the-group');
    await t.enterText(find.byType(TextField).first, 'Ski trip');
    FocusManager.instance.primaryFocus?.unfocus();
    await settle(t);
    await tapText(t, 'Next');
    await settle(t, 800);
    await shot(t, '14-whos-in');
    await back(t);
    await settle(t, 600);
    await t.tap(glyph(MullGlyph.close));
    await settle(t, 900);

    // ---- the group's name and icon, from its title
    await tapText(t, 'Goa trip');
    await t.tap(find.text('Goa trip').hitTestable().first);
    await settle(t);
    await shot(t, '14b-edit-group');
    await dismissSheet(t);
    await back(t);

    // ---- the You tab
    await tapHome(t, HomeTab.you);
    await shot(t, '15-profile');
    await tapText(t, 'How it works');
    await shot(t, '15b-how-it-works');
    await dismissSheet(t);
    await tapText(t, 'Light');
    await shot(t, '16-profile-light');
    await tapText(t, 'Dark');
    await settle(t);
    await tapHome(t, HomeTab.home);

    // ---- and the screen an app with nothing in it shows
    store
      ..groups.clear()
      ..refresh();
    await settle(t, 1600);
    await shot(t, '17-empty-home');
  });
}
