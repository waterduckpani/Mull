import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mull/data/store.dart';
import 'package:mull/screens/home/home_shell.dart';
import 'package:mull/ui/tokens.dart';

/// The People tab: who you pay and who pays you, netted across every ledger.
void main() {
  Future<void> openPeopleTab(WidgetTester t, MullStore store) async {
    await t.binding.setSurfaceSize(const Size(390, 844));
    await t.pumpWidget(
      StoreScope(
        store: store,
        child: ListenableBuilder(
          listenable: store,
          builder: (_, _) => MaterialApp(
            theme: buildTheme(MullColors.dark),
            home: Navigator(
              onGenerateRoute: (settings) =>
                  CupertinoPageRoute(builder: (_) => const HomeShell(initialTab: HomeTab.people), settings: settings),
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  void peopleTest(String description, Future<void> Function(WidgetTester t) body) => testWidgets(description, (t) async {
    try {
      await body(t);
      await t.pump(const Duration(seconds: 6));
    } finally {
      await t.binding.setSurfaceSize(null);
    }
  });

  Finder onTab(Finder f) => find.descendant(of: find.byKey(const ValueKey('home-tab-people')), matching: f);

  /// Someone you owe on one ledger, and someone square across two that cancel.
  MullStore twoPeople() {
    final store = MullStore.memory()..completeOnboarding(name: 'Bharat');
    final dinner = store.addGroup('Dinner', ['Dev']);
    store.addExpense(dinner,
        description: 'Dinner', amount: 900, payerId: dinner.members[1].id,
        shares: {dinner.you!.id: 450, dinner.members[1].id: 450});
    final goa = store.addGroup('Goa', ['Ananya']);
    store.addExpense(goa,
        description: 'Villa', amount: 1000, payerId: goa.members[1].id,
        shares: {goa.you!.id: 500, goa.members[1].id: 500});
    final flat = store.addGroup('Flat', ['Ananya']);
    store.addExpense(flat,
        description: 'Rent', amount: 1000, payerId: flat.you!.id,
        shares: {flat.you!.id: 500, flat.members[1].id: 500});
    return store;
  }

  peopleTest('the sample splits into who you pay and who pays you', (t) async {
    await openPeopleTab(t, MullStore.memory()..loadSample());
    expect(onTab(find.text('YOU OWE')), findsOneWidget);
    expect(onTab(find.text('Pay')), findsWidgets);
    await t.scrollUntilVisible(onTab(find.text('OWES YOU')), 200, scrollable: onTab(find.byType(Scrollable)).first);
    expect(onTab(find.text('Nudge')), findsWidgets);
  });

  peopleTest('somebody you owe is there, with the amount', (t) async {
    await openPeopleTab(t, twoPeople());
    expect(onTab(find.text('Dev')), findsOneWidget);
    expect(onTab(find.text('₹450')), findsOneWidget);
  });

  peopleTest('people you are square with fold into one line until opened', (t) async {
    await openPeopleTab(t, twoPeople());
    expect(onTab(find.text('Ananya')), findsNothing);
    await t.tap(onTab(find.text('SQUARE · 1')));
    await t.pumpAndSettle();
    expect(onTab(find.text('Ananya')), findsOneWidget);
  });

  peopleTest('Friends opens the friends sheet', (t) async {
    await openPeopleTab(t, twoPeople());
    await t.scrollUntilVisible(onTab(find.text('Friends')), 200, scrollable: onTab(find.byType(Scrollable)).first);
    await t.tap(onTab(find.text('Friends')));
    await t.pumpAndSettle();
    expect(find.text('Nobody yet.'), findsOneWidget);
  });

  peopleTest('+ Add a friend asks for their email', (t) async {
    await openPeopleTab(t, twoPeople());
    await t.tap(onTab(find.text('+ Add a friend')));
    await t.pumpAndSettle();
    expect(find.text('their@email.com'), findsOneWidget);
  });

  peopleTest('tapping a person opens where you stand with them', (t) async {
    await openPeopleTab(t, twoPeople());
    await t.tap(onTab(find.text('Dev')));
    await t.pumpAndSettle();
    expect(find.text('ACROSS'), findsOneWidget);
  });
}
