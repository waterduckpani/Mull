import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mull/data/models.dart';
import 'package:mull/data/store.dart';
import 'package:mull/screens/groups/ledger_screen.dart';
import 'package:mull/ui/tokens.dart';

/// A ₹10,000 dinner you paid, split 90/10, used to read "₹10,000 · You paid",
/// which says the whole ₹10,000 was yours. The row now carries the total and
/// your part of it.
void main() {
  late MullStore store;
  late Group flat;

  setUp(() {
    store = MullStore.memory()..completeOnboarding(name: 'Bharat');
    flat = store.addGroup('Flat', ['Sahil']);
    final me = flat.you!.id;
    final sahil = flat.members.firstWhere((m) => !m.isYou).id;
    store
      ..addExpense(flat,
          description: 'Dinner', amount: 10000, payerId: me, shares: {me: 9000, sahil: 1000}, method: SplitMethod.percent)
      ..addExpense(flat,
          description: 'Groceries', amount: 6700, payerId: sahil, shares: {me: 2345, sahil: 4355}, method: SplitMethod.percent)
      ..addExpense(flat, description: "Sahil's cab", amount: 600, payerId: me, shares: {sahil: 600}, method: SplitMethod.exact);
  });

  Future<void> pumpLedger(WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(
      StoreScope(
        store: store,
        child: MaterialApp(theme: buildTheme(MullColors.dark), home: LedgerScreen(groupId: flat.id)),
      ),
    );
    await t.pumpAndSettle();
  }

  testWidgets('a row shows the total and your share', (t) async {
    await pumpLedger(t);
    expect(find.text('₹10,000'), findsOneWidget);
    expect(find.textContaining('your share ₹9,000', findRichText: true), findsOneWidget);
    expect(find.text('₹6,700'), findsOneWidget);
    expect(find.textContaining('your share ₹2,345', findRichText: true), findsOneWidget);
  });

  testWidgets('a row with no share of yours says so, even if you paid', (t) async {
    await pumpLedger(t);
    expect(find.textContaining('not yours', findRichText: true), findsOneWidget);
  });

  testWidgets('the ledger has no add button of its own', (t) async {
    await pumpLedger(t);
    expect(find.text('Add an expense'), findsNothing);
  });

  testWidgets('the group name sits above the title', (t) async {
    await pumpLedger(t);
    expect(t.getRect(find.text('Flat')).bottom, lessThanOrEqualTo(t.getRect(find.text('Ledger')).top));
  });

  testWidgets('each row still fits on one line at phone width', (t) async {
    await pumpLedger(t);
    expect(t.takeException(), isNull);
  });
}
