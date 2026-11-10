import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mull/data/store.dart';
import 'package:mull/screens/home/home_shell.dart';
import 'package:mull/ui/tokens.dart';

/// The You tab: what the profile sheet held, as a page.
void main() {
  Future<MullStore> openYouTab(WidgetTester t) async {
    final store = MullStore.memory()..completeOnboarding(name: 'Bharat');
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
                  CupertinoPageRoute(builder: (_) => const HomeShell(initialTab: HomeTab.you), settings: settings),
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    return store;
  }

  void youTest(String description, Future<void> Function(WidgetTester t) body) => testWidgets(description, (t) async {
    final semantics = t.ensureSemantics();
    try {
      await body(t);
      await t.pump(const Duration(seconds: 1));
    } finally {
      semantics.dispose();
      await t.binding.setSurfaceSize(null);
    }
  });

  Finder onTab(Finder f) => find.descendant(of: find.byKey(const ValueKey('home-tab-you')), matching: f);

  youTest('your name, UPI ID, payment app and how it works', (t) async {
    await openYouTab(t);
    expect(onTab(find.text('Bharat')), findsOneWidget);
    for (final label in ['Your UPI ID', 'Pay with', 'How it works']) {
      expect(onTab(find.text(label)), findsOneWidget, reason: label);
    }
    expect(onTab(find.text('Friends')), findsNothing, reason: 'Friends lives on People now');
  });

  youTest('appearance is picked here', (t) async {
    final store = await openYouTab(t);
    await t.scrollUntilVisible(onTab(find.text('Light')), 200, scrollable: onTab(find.byType(Scrollable)).first);
    await t.tap(onTab(find.text('Light')));
    await t.pumpAndSettle();
    expect(store.profile.theme, ThemeMode.light);
  });

  youTest('the top bar no longer carries a profile button', (t) async {
    await openYouTab(t);
    expect(find.bySemanticsLabel('Profile and settings'), findsNothing);
    expect(find.bySemanticsLabel('Friends'), findsNothing);
  });
}
