import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mull/data/remote/friends_service.dart';
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
      FriendsService.debugFriends = null;
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

  peopleTest('your friends are on the tab, with where you split', (t) async {
    final store = twoPeople();
    store.groups.firstWhere((g) => g.name == 'Dinner').members[1].userId = 'dev';
    FriendsService.debugFriends = const [
      Friend(friendshipId: 'f1', state: FriendState.friends, userId: 'dev', name: 'Dev Rao'),
      Friend(friendshipId: 'f2', state: FriendState.friends, userId: 'riya', name: 'Riya Shah'),
    ];
    await openPeopleTab(t, store);
    await t.scrollUntilVisible(onTab(find.text('Riya Shah')), 200, scrollable: onTab(find.byType(Scrollable)).first);
    expect(onTab(find.text('FRIENDS · 2')), findsOneWidget);
    expect(onTab(find.text('Dev Rao')), findsOneWidget);
    expect(onTab(find.text('Dinner')), findsWidgets, reason: 'the group Dev and you share');
    expect(onTab(find.text('No groups together yet')), findsOneWidget, reason: 'Riya');
    expect(onTab(find.text('Friends')), findsNothing, reason: 'no row to tap through to them');
  });

  peopleTest('a request is at the top, with Accept on the row', (t) async {
    FriendsService.debugFriends = const [
      Friend(friendshipId: 'f3', state: FriendState.incoming, userId: 'kabir', name: 'Kabir'),
    ];
    await openPeopleTab(t, twoPeople());
    final request = onTab(find.text('WANTS TO SPLIT WITH YOU · 1'));
    expect(request, findsOneWidget);
    expect(t.getRect(request).top, lessThan(t.getRect(onTab(find.text('YOU OWE'))).top));
    expect(onTab(find.text('Accept')), findsOneWidget);
  });

  peopleTest('with no friends yet, it says so and offers an invite', (t) async {
    FriendsService.debugFriends = const [];
    await openPeopleTab(t, twoPeople());
    await t.scrollUntilVisible(
      onTab(find.text('Invite someone to Mull')),
      200,
      scrollable: onTab(find.byType(Scrollable)).first,
    );
    expect(onTab(find.textContaining('Nobody yet.')), findsOneWidget);
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
