import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mull/data/models.dart';
import 'package:mull/data/store.dart';
import 'package:mull/screens/groups/group_sheets.dart';
import 'package:mull/ui/tokens.dart';
import 'package:mull/ui/widgets.dart';

/// The add-an-expense sheet in its two steps, and the ledger's order.
void main() {
  Future<BuildContext> pumpHost(WidgetTester t, MullStore store) async {
    await t.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => t.binding.setSurfaceSize(null));
    late BuildContext host;
    await t.pumpWidget(
      StoreScope(
        store: store,
        child: MaterialApp(
          theme: buildTheme(MullColors.dark),
          home: Builder(
            builder: (context) {
              host = context;
              return const Scaffold();
            },
          ),
        ),
      ),
    );
    return host;
  }

  MullStore flat() {
    final store = MullStore.memory()..completeOnboarding(name: 'Bharat');
    store.addGroup('Flat', ['Dev', 'Kabir']);
    return store;
  }

  Future<void> fillWhat(WidgetTester t, String what, String amount) async {
    await t.enterText(find.byType(TextField).at(0), what);
    await t.enterText(find.byType(TextField).at(1), amount);
    await t.pump();
  }

  testWidgets('two steps: what it was, then who paid', (t) async {
    final store = flat();
    final group = store.groups.single;
    final host = await pumpHost(t, store);
    showAddExpense(host, group);
    await t.pumpAndSettle();

    await fillWhat(t, 'Groceries', '600');
    // One button, and it is Next until the end.
    expect(find.text('Add it'), findsNothing);
    // The extras are on the first step, out of the way.
    for (final extra in ['Add a bill', 'Today', 'Add a note', 'Repeats']) {
      expect(find.text(extra), findsOneWidget, reason: extra);
    }
    await t.tap(find.text('Next'));
    await t.pumpAndSettle();
    expect(find.text('Who paid the ₹600?'), findsOneWidget);
    expect(find.text('Who was it for?'), findsOneWidget);
    expect(find.text('Dev and Kabir owe you ₹200 each.'), findsOneWidget);
    expect(find.text('Next'), findsNothing);
    await t.tap(find.text('Add it'));
    await t.pumpAndSettle();
    final shop = group.expenses.single;
    expect(shop.amount, 600);
    expect(shop.method, SplitMethod.equal);
    expect(shop.shares.values, [200, 200, 200]);
  });

  testWidgets('a note goes in from the first step', (t) async {
    final store = flat();
    final group = store.groups.single;
    final host = await pumpHost(t, store);
    showAddExpense(host, group);
    await t.pumpAndSettle();

    await fillWhat(t, 'Groceries', '600');
    await t.tap(find.text('Add a note'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).last, 'Big shop');
    await t.pump();
    await t.tap(find.text('Next'));
    await t.pumpAndSettle();
    await t.tap(find.text('Add it'));
    await t.pumpAndSettle();
    expect(group.expenses.single.note, 'Big shop');
  });

  testWidgets('"I paid, he owes all of it" is one tap', (t) async {
    final store = MullStore.memory()..completeOnboarding(name: 'Bharat');
    final group = store.addGroup('Neel', ['Neel']);
    final neel = group.members.firstWhere((m) => !m.isYou);
    final host = await pumpHost(t, store);
    showAddExpense(host, group);
    await t.pumpAndSettle();

    await fillWhat(t, 'Bomb', '200');
    await t.tap(find.text('Next'));
    await t.pumpAndSettle();
    await t.tap(find.text('Neel owes all of it'));
    await t.pumpAndSettle();
    expect(find.text('Neel owes you ₹200.'), findsOneWidget);
    await t.tap(find.text('Add it'));
    await t.pumpAndSettle();
    expect(group.expenses.single.shares, {neel.id: 200});
  });

  testWidgets('the whole bill on whoever paid is caught, with the fix', (t) async {
    final store = MullStore.memory()..completeOnboarding(name: 'Bharat');
    final group = store.addGroup('Neel', ['Neel']);
    final host = await pumpHost(t, store);
    showAddExpense(host, group);
    await t.pumpAndSettle();

    await fillWhat(t, 'Bomb', '200');
    await t.tap(find.text('Next'));
    await t.pumpAndSettle();
    // Neel's row, not the chip for who paid.
    await t.tap(find.text('Neel').last);
    await t.pumpAndSettle();
    expect(find.text("It's all yours, so nobody owes anything."), findsOneWidget);
    final fix = find.descendant(of: find.byType(InlineButton), matching: find.text('Neel owes all of it'));
    await t.ensureVisible(fix);
    await t.pumpAndSettle();
    await t.tap(fix);
    await t.pumpAndSettle();
    expect(find.text('Neel owes you ₹200.'), findsOneWidget);
  });

  testWidgets('it repeats from the first step too', (t) async {
    final store = flat();
    final group = store.groups.single;
    final host = await pumpHost(t, store);
    showAddExpense(host, group);
    await t.pumpAndSettle();

    await fillWhat(t, 'Rent', '30000');
    await t.tap(find.text('Repeats'));
    await t.pumpAndSettle();
    expect(find.text('Every month'), findsWidgets);
    await t.tap(find.text('Next'));
    await t.pumpAndSettle();
    await t.tap(find.text('Add it'));
    await t.pumpAndSettle();
    expect(group.recurring.single.description, 'Rent');
  });

  test('a day of expenses reads newest first, even with no time on the date', () {
    final store = flat();
    final group = store.groups.single;
    final me = group.you!.id;
    final day = DateTime(2026, 9, 27);
    // As a pull leaves them: the date is only a day; the moment they were
    // written down is what tells them apart.
    for (final (name, hour) in [('Breakfast', 9), ('Lunch', 13), ('Dinner', 20)]) {
      group.expenses.add(
        Expense(
          description: name,
          amount: 100,
          payerId: me,
          shares: {me: 100},
          date: day,
          createdAt: day.add(Duration(hours: hour)),
        ),
      );
    }
    final sorted = [...group.expenses]..sort((a, b) => newestFirst(ledgerMoment(a), ledgerMoment(b)));
    expect(sorted.map((e) => e.description), ['Dinner', 'Lunch', 'Breakfast']);
    expect((store.activity(group).first as Expense).description, 'Dinner');
  });
}
