import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mull/data/models.dart';
import 'package:mull/data/store.dart';
import 'package:mull/screens/groups/group_bar.dart';
import 'package:mull/screens/groups/group_screen.dart';
import 'package:mull/screens/groups/recurring_screen.dart';
import 'package:mull/ui/sheet.dart';
import 'package:mull/ui/tokens.dart';

/// One group, four tabs, one bar that never moves.
void main() {
  final navigator = GlobalKey<NavigatorState>();

  Future<void> open(WidgetTester t, MullStore store, Group group, {MullColors colors = MullColors.dark}) async {
    await t.binding.setSurfaceSize(const Size(390, 844));
    await t.pumpWidget(
      StoreScope(
        store: store,
        child: ListenableBuilder(
          listenable: store,
          builder: (_, _) => MaterialApp(
            navigatorKey: navigator,
            theme: buildTheme(colors),
            home: const Placeholder(key: Key('home')),
          ),
        ),
      ),
    );
    navigator.currentState!.push(CupertinoPageRoute(builder: (_) => GroupScreen(groupId: group.id)));
    await t.pumpAndSettle();
  }

  // Tabs are found the way a screen reader finds them, which needs semantics
  // on for the length of each test and off again before it ends.
  void screenTest(String description, Future<void> Function(WidgetTester t) body) =>
      testWidgets(description, (t) async {
        final semantics = t.ensureSemantics();
        try {
          await body(t);
        } finally {
          semantics.dispose();
          await t.binding.setSurfaceSize(null);
        }
      });

  Future<void> tapTab(WidgetTester t, String name) async {
    await t.tap(find.bySemanticsLabel(RegExp('^$name, tab')));
    await t.pumpAndSettle();
  }

  MullStore sample() => MullStore.memory()..loadSample();
  Group named(MullStore store, String name) => store.groups.firstWhere((g) => g.name == name);

  screenTest('opens on Overview', (t) async {
    final store = sample();
    await open(t, store, named(store, 'Flat'));
    expect(find.text('₹6,250').hitTestable(), findsOneWidget);
  });

  screenTest('tapping Ledger shows the ledger and keeps the bar', (t) async {
    final store = sample();
    await open(t, store, named(store, 'Flat'));
    await tapTab(t, 'Ledger');
    expect(find.text('Expenses').hitTestable(), findsOneWidget);
    expect(find.byType(GroupBar), findsOneWidget);
  });

  screenTest('back from another tab goes to Overview, then out', (t) async {
    final store = sample();
    await open(t, store, named(store, 'Flat'));
    await tapTab(t, 'Ledger');

    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(find.text('₹6,250').hitTestable(), findsOneWidget);

    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(find.byType(GroupScreen), findsNothing);
    expect(find.byKey(const Key('home')), findsOneWidget);
  });

  screenTest('a group deleted while open leaves nothing to crash on', (t) async {
    final store = sample();
    final flat = named(store, 'Flat');
    await open(t, store, flat);
    store.deleteGroup(flat);
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    await t.pump(const Duration(seconds: 1));
  });

  screenTest('light mode renders', (t) async {
    final store = sample();
    await open(t, store, named(store, 'Flat'), colors: MullColors.light);
    for (final name in ['Ledger', 'Recurring', 'People', 'Overview']) {
      await tapTab(t, name);
    }
    expect(t.takeException(), isNull);
  });

  screenTest('the + is greyed while you are alone', (t) async {
    final store = sample();
    final goa = store.addGroup('Goa again', []);
    await open(t, store, goa);
    await t.tap(find.descendant(of: find.byType(GroupBar), matching: find.bySemanticsLabel('Add an expense')));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('Add someone first'), findsOneWidget);
    await t.pump(const Duration(seconds: 5));
  });

  screenTest('Recurring keeps its add button inline', (t) async {
    final store = sample();
    await open(t, store, named(store, 'Flat'));
    await tapTab(t, 'Recurring');
    final button = find.text('Add a recurring cost');
    await t.scrollUntilVisible(
      button,
      200,
      scrollable: find.descendant(of: find.byType(RecurringScreen), matching: find.byType(Scrollable)).first,
    );
    await t.pumpAndSettle();
    expect(t.getRect(button).bottom, lessThanOrEqualTo(t.getRect(find.byType(GroupBar)).top));
  });

  screenTest('and the empty state offers it once', (t) async {
    final store = sample();
    final trip = store.addGroup('Trip', ['Ritu']);
    await open(t, store, trip);
    await tapTab(t, 'Recurring');
    expect(find.text('Add a recurring cost'), findsOneWidget);
    expect(find.text('Set one up'), findsNothing);
  });

  screenTest('an admin can add, leave and delete from People', (t) async {
    final store = sample();
    await open(t, store, named(store, 'Goa trip'));
    await tapTab(t, 'People');
    for (final label in ['Add people', 'Add someone not on Mull', 'Leave group', 'Delete group']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
  });

  screenTest('a member sees Leave but not Delete', (t) async {
    final store = sample();
    final goa = named(store, 'Goa trip');
    goa.you!.role = MemberRole.member;
    await open(t, store, goa);
    await tapTab(t, 'People');
    expect(find.text('Leave group'), findsOneWidget);
    expect(find.text('Delete group'), findsNothing);
  });

  screenTest('deleting from People closes the group', (t) async {
    final store = sample();
    await open(t, store, named(store, 'Goa trip'));
    await tapTab(t, 'People');
    final delete = find.text('Delete group');
    await t.ensureVisible(delete);
    await t.pumpAndSettle();
    await t.tap(delete);
    await t.pumpAndSettle();
    await t.tap(find.text('Delete it'));
    await t.pumpAndSettle();
    expect(find.byType(GroupScreen), findsNothing);
    await t.pump(const Duration(seconds: 6));
  });

  screenTest('a one-to-one ledger offers Delete this ledger', (t) async {
    final store = sample();
    final dev = store.directWith(name: 'Dev Rao');
    await open(t, store, dev);
    await tapTab(t, 'People');
    expect(find.text('Delete this ledger'), findsOneWidget);
    expect(find.text('Add people'), findsNothing);
  });

  screenTest('a notice sits above the bar, not on the +', (t) async {
    final store = sample();
    await open(t, store, named(store, 'Flat'));
    Toast.show(t.element(find.byType(GroupBar)), 'Saved');
    await t.pumpAndSettle();
    expect(t.getRect(find.text('Saved')).bottom, lessThan(t.getRect(find.byType(GroupBar)).top));
    Toast.hide();
  });
}
