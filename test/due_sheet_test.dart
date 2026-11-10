import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mull/data/models.dart';
import 'package:mull/data/store.dart';
import 'package:mull/screens/groups/recurring_sheets.dart';
import 'package:mull/ui/tokens.dart';

/// A repeating cost coming round again.
void main() {
  testWidgets('an uneven bill at a new amount says why it cannot be added yet', (t) async {
    await t.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final store = MullStore.memory()..completeOnboarding(name: 'Bharat');
    final flat = store.addGroup('Flat', ['Dev']);
    final me = flat.you!.id;
    final dev = flat.members.firstWhere((m) => !m.isYou).id;
    final rent = store.addRecurring(
      flat,
      description: 'Electricity',
      amount: 3000,
      payerId: me,
      shares: {me: 2000, dev: 1000},
      method: SplitMethod.exact,
      startsOn: store.now(),
    );

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
    showDueRecurring(host, flat, rent);
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).first, '3300');
    await t.pump();

    expect(find.textContaining('₹300 still to share out'), findsOneWidget);
  });
}
