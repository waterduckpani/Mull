import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mull/data/store.dart';
import 'package:mull/screens/groups/group_screen.dart';
import 'package:mull/screens/home/home_shell.dart';
import 'package:mull/ui/tokens.dart';

/// The Groups tab: every group as a row you can scan, open money first.
void main() {
  Future<void> openGroupsTab(WidgetTester t, MullStore store) async {
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
                  CupertinoPageRoute(builder: (_) => const HomeShell(initialTab: HomeTab.groups), settings: settings),
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  void groupsTest(String description, Future<void> Function(WidgetTester t) body) => testWidgets(description, (t) async {
    try {
      await body(t);
      await t.pump(const Duration(seconds: 1));
    } finally {
      await t.binding.setSurfaceSize(null);
    }
  });

  Finder onTab(Finder f) => find.descendant(of: find.byKey(const ValueKey('home-tab-groups')), matching: f);

  groupsTest('what you owe comes first, then what you are owed, then settled', (t) async {
    await openGroupsTab(t, MullStore.memory()..loadSample());
    final flat = t.getRect(onTab(find.text('Flat'))).top;
    final goa = t.getRect(onTab(find.text('Goa trip'))).top;
    final football = t.getRect(onTab(find.text('Sunday football'))).top;
    expect(flat, lessThan(goa));
    expect(goa, lessThan(football));
    expect(t.getRect(onTab(find.text('SETTLED'))).top, lessThan(football));
  });

  groupsTest('+ New group starts one', (t) async {
    await openGroupsTab(t, MullStore.memory()..loadSample());
    await t.tap(onTab(find.text('+ New group')));
    await t.pumpAndSettle();
    expect(find.text('Trip to Goa'), findsOneWidget, reason: 'the name field of the create flow');
  });

  groupsTest("Settle up from a group's long-press opens the group on Overview", (t) async {
    await openGroupsTab(t, MullStore.memory()..loadSample());
    await t.longPress(onTab(find.text('Flat')));
    await t.pumpAndSettle();
    await t.tap(find.text('Settle up'));
    await t.pumpAndSettle();
    expect(find.byType(GroupScreen), findsOneWidget);
    expect(find.text('Send summary on WhatsApp'), findsOneWidget);
  });
}
