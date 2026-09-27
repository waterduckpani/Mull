import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mull/core/split.dart';
import 'package:mull/data/store.dart';
import 'package:mull/main.dart';
import 'package:mull/ui/icons.dart';
import 'package:mull/ui/sheet.dart';

/// Screenshots of the 2026-09-27 changes: the net-off card, quick add, the
/// group header, a greyed Settle up, and the expense view with its note and
/// bill. Run like the tour:
///
///   flutter drive --driver=test_driver/integration_test.dart \
///     --target=integration_test/changes_test.dart
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  Future<void> settle(WidgetTester t, [int ms = 900]) async {
    for (var i = 0; i < ms ~/ 50; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> tapText(WidgetTester t, String text) async {
    await t.tap(find.text(text).hitTestable().last);
    await settle(t);
  }

  Future<void> shot(WidgetTester t, String name) async {
    await settle(t, 400);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await t.pump();
    await binding.takeScreenshot(name);
  }

  Future<void> dismissSheet(WidgetTester t) async {
    for (var i = 0; i < 4 && SheetDepth.value.value > 0; i++) {
      await t.tapAt(const Offset(200, 24));
      await settle(t, 700);
    }
  }

  Future<void> back(WidgetTester t) async {
    await t.tap(find.byWidgetPredicate((w) => w is MullIcon && w.glyph == MullGlyph.chevronLeft).hitTestable().last);
    await settle(t, 700);
  }

  testWidgets('changes', (t) async {
    final store = MullStore.memory();
    store.completeOnboarding(name: 'Bharat');

    // Owe Ananya ₹500 on Goa, she owes you ₹500 on the flat: nets to nothing.
    final goa = store.addGroup('Goa trip', ['Ananya']);
    final flat = store.addGroup('Flat', ['Ananya', 'Kabir']);
    for (final g in [goa, flat]) {
      g.members.firstWhere((m) => m.name == 'Ananya').email = 'ananya@example.com';
    }
    final a1 = goa.members.firstWhere((m) => m.name == 'Ananya').id;
    store.addExpense(goa, description: 'Villa', amount: 1000, payerId: a1,
        shares: splitEqually(1000, [goa.you!.id, a1]));
    final a2 = flat.members.firstWhere((m) => m.name == 'Ananya').id;
    final k2 = flat.members.firstWhere((m) => m.name == 'Kabir').id;
    store.addExpense(flat, description: 'Groceries', amount: 1000, payerId: flat.you!.id,
        shares: splitEqually(1000, [flat.you!.id, a2]));
    store.addExpense(flat, description: 'Dinner at Bombay Canteen', amount: 2400, payerId: k2,
        shares: splitEqually(2400, [flat.you!.id, a2, k2]),
        note: 'Includes the tip and the dessert Ananya insisted on. Kabir paid on his card, '
            'so settle with him directly.');

    await t.pumpWidget(MullApp(store: store));
    await settle(t, 2500);
    if (find.text('Continue on this phone').evaluate().isNotEmpty) {
      await tapText(t, 'Continue on this phone');
      await settle(t, 1500);
    }

    await shot(t, 'c01-home-netted');

    await tapText(t, 'Add expense');
    await shot(t, 'c02-quick-add-picker');
    await dismissSheet(t);

    await tapText(t, 'Goa trip');
    await shot(t, 'c03-group-square');
    await back(t);

    await tapText(t, 'Flat');
    await shot(t, 'c04-group-owing');
    await tapText(t, '3 people');
    await shot(t, 'c05-people-from-count');
    await back(t);

    await tapText(t, 'Ledger');
    await shot(t, 'c06-ledger-note');
    await tapText(t, 'Dinner at Bombay Canteen');
    await shot(t, 'c07-expense-detail');
    await tapText(t, 'Ask for the bill');
    await shot(t, 'c08-bill-asked');
    await dismissSheet(t);
  });
}
