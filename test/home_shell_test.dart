import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mull/data/store.dart';
import 'package:mull/screens/groups/group_bar.dart';
import 'package:mull/screens/groups/group_screen.dart';
import 'package:mull/screens/home/home_shell.dart';
import 'package:mull/ui/sheet.dart';
import 'package:mull/ui/tab_bar.dart';
import 'package:mull/ui/tokens.dart';

/// Home, Groups, People and You under one bar, inside the same nested
/// navigator and back handler the app shell gives it.
void main() {
  final pages = GlobalKey<NavigatorState>();

  Future<MullStore> pumpShell(WidgetTester t, {MullStore? store}) async {
    final s = store ?? (MullStore.memory()..loadSample());
    await t.binding.setSurfaceSize(const Size(390, 844));
    await t.pumpWidget(
      StoreScope(
        store: s,
        child: ListenableBuilder(
          listenable: s,
          builder: (_, _) => MaterialApp(
            theme: buildTheme(MullColors.dark),
            home: NavigatorPopHandler<Object?>(
              onPopWithResult: (_) => pages.currentState?.maybePop(),
              child: Navigator(
                key: pages,
                onGenerateRoute: (settings) =>
                    CupertinoPageRoute(builder: (_) => const HomeShell(), settings: settings),
              ),
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    return s;
  }

  void shellTest(String description, Future<void> Function(WidgetTester t) body) => testWidgets(description, (t) async {
    final semantics = t.ensureSemantics();
    try {
      await body(t);
      await t.pump(const Duration(seconds: 1));
    } finally {
      semantics.dispose();
      await t.binding.setSurfaceSize(null);
    }
  });

  Future<void> tapTab(WidgetTester t, String name) async {
    await t.tap(find.bySemanticsLabel(RegExp('^$name, tab')));
    await t.pumpAndSettle();
  }

  Finder page(HomeTab tab) => find.byKey(ValueKey('home-tab-${tab.name}')).hitTestable();

  shellTest('opens on Home', (t) async {
    await pumpShell(t);
    expect(page(HomeTab.home), findsOneWidget);
  });

  shellTest('each tab shows its own page', (t) async {
    await pumpShell(t);
    for (final tab in [HomeTab.groups, HomeTab.people, HomeTab.you, HomeTab.home]) {
      await tapTab(t, tab.label);
      expect(page(tab), findsOneWidget, reason: tab.label);
    }
  });

  shellTest('Back from another tab goes Home, not out of the app', (t) async {
    await pumpShell(t);
    await tapTab(t, 'People');
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(page(HomeTab.home), findsOneWidget);
  });

  shellTest('closing a group leaves notices above the home bar', (t) async {
    final store = await pumpShell(t);
    expect(Toast.raise, greaterThanOrEqualTo(MullTabBar.height));
    pages.currentState!.push(
      CupertinoPageRoute(builder: (_) => GroupScreen(groupId: store.namedGroups.first.id)),
    );
    await t.pumpAndSettle();
    pages.currentState!.pop();
    await t.pumpAndSettle();
    expect(Toast.raise, greaterThanOrEqualTo(MullTabBar.height));
  });

  shellTest('with no groups yet, the + starts one', (t) async {
    await pumpShell(t, store: MullStore.memory()..completeOnboarding(name: 'Bharat'));
    await t.tap(find.descendant(of: find.byType(MullTabBar), matching: find.bySemanticsLabel('Add an expense')));
    await t.pumpAndSettle();
    expect(find.text('Trip to Goa'), findsOneWidget, reason: 'the create flow');
  });

  shellTest('with groups, the + asks which one', (t) async {
    await pumpShell(t);
    await t.tap(find.descendant(of: find.byType(MullTabBar), matching: find.bySemanticsLabel('Add an expense')));
    await t.pumpAndSettle();
    expect(find.text('Add it to'), findsOneWidget);
  });

  shellTest('a group covers the home bar: one bar on screen', (t) async {
    await pumpShell(t);
    await tapTab(t, 'Groups');
    await t.tap(find.descendant(of: find.byKey(const ValueKey('home-tab-groups')), matching: find.text('Flat')));
    await t.pumpAndSettle();
    expect(find.byType(MullTabBar).hitTestable(), findsOneWidget);
    expect(find.descendant(of: find.byType(GroupBar), matching: find.byType(MullTabBar)).hitTestable(), findsOneWidget);
  });
}
