import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mull/data/models.dart';
import 'package:mull/data/store.dart';
import 'package:mull/screens/groups/group_bar.dart';
import 'package:mull/screens/groups/ledger_screen.dart';
import 'package:mull/screens/groups/overview_tab.dart';
import 'package:mull/ui/icons.dart';
import 'package:mull/ui/tokens.dart';

/// The first tab of a group: where you stand, and only what there is to do
/// about it. A new group asks for one thing at a time.
void main() {
  GroupTab? selected;

  Future<void> pumpOverview(WidgetTester t, MullStore store, Group group) async {
    selected = null;
    await t.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(
      StoreScope(
        store: store,
        child: ListenableBuilder(
          listenable: store,
          builder: (_, _) => MaterialApp(
            theme: buildTheme(MullColors.dark),
            home: OverviewTab(groupId: group.id, onSelectTab: (tab) => selected = tab),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    // Let the store's debounced save run, so no timer outlives the test.
    await t.pump(const Duration(seconds: 1));
  }

  MullStore sample() => MullStore.memory()..loadSample();
  Group named(MullStore store, String name) => store.groups.firstWhere((g) => g.name == name);

  testWidgets('alone: one card and nothing else', (t) async {
    final store = sample();
    await pumpOverview(t, store, store.addGroup('Solo', []));
    expect(find.text('Just you so far'), findsOneWidget);
    expect(find.text('Add people'), findsOneWidget);
    expect(find.text('Nothing spent yet.'), findsNothing);
    expect(find.text('SETTLE UP'), findsNothing);
    expect(find.text('You owe'), findsNothing);
  });

  testWidgets('people but nothing spent: points at the +', (t) async {
    final store = sample();
    await pumpOverview(t, store, store.addGroup('Trip', ['Ananya']));
    expect(find.text('2 people'), findsOneWidget);
    expect(find.text('Nothing spent yet.'), findsOneWidget);
    expect(find.text('Tap + to add the first expense'), findsOneWidget);
    expect(find.text('SETTLE UP'), findsNothing);
    expect(find.text('Add people'), findsNothing);
  });

  testWidgets('in use: hero, then settle up with its summary button', (t) async {
    final store = sample();
    await pumpOverview(t, store, named(store, 'Flat'));
    expect(find.text('You owe'), findsOneWidget);
    expect(find.text('₹6,250'), findsOneWidget);
    expect(find.text('SETTLE UP'), findsOneWidget);
    expect(find.text('Send summary on WhatsApp'), findsOneWidget);
    expect(find.textContaining('Money never moves through Mull.'), findsOneWidget);
  });

  testWidgets('a claim waiting on you is a card at the top', (t) async {
    final store = sample();
    await pumpOverview(t, store, named(store, 'Goa trip'));
    final claim = find.textContaining('says they sent you');
    expect(claim, findsOneWidget);
    expect(t.getRect(claim).top, lessThan(t.getRect(find.text('SETTLE UP')).top));
  });

  testWidgets('square while others are not: one quiet line, no section', (t) async {
    final store = sample();
    final dinner = store.addGroup('Dinner', [], friends: [
      Member(name: 'Asha', userId: 'u-asha'),
      Member(name: 'Ben', userId: 'u-ben'),
    ]);
    final asha = dinner.members.firstWhere((m) => m.name == 'Asha').id;
    final ben = dinner.members.firstWhere((m) => m.name == 'Ben').id;
    store.addExpense(dinner, description: 'Pizza', amount: 1000, payerId: asha, shares: {asha: 500, ben: 500});
    await pumpOverview(t, store, dinner);
    expect(find.textContaining('Other people here still owe each other'), findsOneWidget);
    expect(find.text('SETTLE UP'), findsNothing);
    expect(find.text('Send summary on WhatsApp'), findsNothing);
  });

  testWidgets('Latest shows three and See all opens the ledger', (t) async {
    final store = sample();
    await pumpOverview(t, store, named(store, 'Flat'));
    final seeAll = find.text('See all');
    await t.scrollUntilVisible(seeAll, 300, scrollable: find.byType(Scrollable).first);
    await t.ensureVisible(seeAll);
    await t.pumpAndSettle();
    await t.drag(find.byType(Scrollable).first, const Offset(0, -400));
    await t.pumpAndSettle();
    final rows = find.byWidgetPredicate((w) => w is ExpenseRow || w is SettlementRow);
    expect(rows.evaluate().length, 3);
    await t.ensureVisible(seeAll);
    await t.pumpAndSettle();
    await t.tap(seeAll);
    expect(selected, GroupTab.ledger);
  });

  testWidgets('only an admin can open the edit sheet', (t) async {
    final store = sample();
    final goa = named(store, 'Goa trip');
    await pumpOverview(t, store, goa);
    await t.tap(find.text('Goa trip'));
    await t.pumpAndSettle();
    expect(find.text('Name'), findsOneWidget, reason: 'the admin gets the name field');
  });

  testWidgets('a member taps the title and nothing opens', (t) async {
    final store = sample();
    final goa = named(store, 'Goa trip');
    goa.you!.role = MemberRole.member;
    await pumpOverview(t, store, goa);
    await t.tap(find.text('Goa trip'));
    await t.pumpAndSettle();
    expect(find.text('Name'), findsNothing);
  });

  testWidgets('a one-to-one ledger has no edit sheet', (t) async {
    final store = sample();
    final dev = store.directWith(name: 'Dev Rao');
    await pumpOverview(t, store, dev);
    await t.tap(find.text(dev.title));
    await t.pumpAndSettle();
    expect(find.text('Name'), findsNothing);
  });

  testWidgets('no ⋯ and no destination cards', (t) async {
    final store = sample();
    await pumpOverview(t, store, named(store, 'Flat'));
    expect(find.byWidgetPredicate((w) => w is MullIcon && w.glyph == MullGlyph.more), findsNothing);
    expect(find.text('Change icon'), findsNothing);
    expect(find.text('Recurring'), findsNothing);
    expect(find.text('Add an expense'), findsNothing);
  });
}
