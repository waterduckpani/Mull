import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mull/data/models.dart';
import 'package:mull/data/store.dart';
import 'package:mull/screens/groups/group_sheets.dart';
import 'package:mull/ui/tokens.dart';

/// The add-an-expense sheet in its three steps, and the ledger's order.
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

  testWidgets('the first step is enough: Add it saves with the defaults', (t) async {
    final store = flat();
    final group = store.groups.single;
    final host = await pumpHost(t, store);
    showAddExpense(host, group);
    await t.pumpAndSettle();

    // Nothing to divide yet, so neither button nor the later steps go anywhere.
    expect(find.text('Who paid'), findsOneWidget);
    await t.enterText(find.byType(TextField).at(0), 'Milk');
    await t.enterText(find.byType(TextField).at(1), '90');
    await t.pumpAndSettle();
    expect(find.text('You paid · split equally · today'), findsOneWidget);

    await t.tap(find.text('Add it'));
    await t.pumpAndSettle();
    final milk = group.expenses.single;
    expect(milk.description, 'Milk');
    expect(milk.amount, 90);
    expect(milk.shares.values.fold(0, (a, b) => a + b), 90);
    expect(milk.shares.length, 3);
  });

  testWidgets('Next walks to the split and then the bill and note', (t) async {
    final store = flat();
    final group = store.groups.single;
    final host = await pumpHost(t, store);
    showAddExpense(host, group);
    await t.pumpAndSettle();

    await t.enterText(find.byType(TextField).at(0), 'Groceries');
    await t.enterText(find.byType(TextField).at(1), '600');
    await t.pump();
    await t.tap(find.text('Next'));
    await t.pumpAndSettle();
    expect(find.text('When'), findsOneWidget);
    expect(find.text('This happens again'), findsOneWidget);

    await t.tap(find.text('Next'));
    await t.pumpAndSettle();
    expect(find.text('Take a photo'), findsOneWidget);
    expect(find.text('Next'), findsNothing);
    await t.enterText(find.byType(TextField).last, 'Big shop');
    await t.pump();
    await t.tap(find.text('Add it'));
    await t.pumpAndSettle();
    expect(group.expenses.single.note, 'Big shop');
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
