import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mull/data/store.dart';
import 'package:mull/screens/home/home_shell.dart';
import 'package:mull/screens/home/needs_you.dart';
import 'package:mull/ui/tokens.dart';

/// The Home tab: the number, what needs you, and what just happened.
void main() {
  final pages = GlobalKey<NavigatorState>();

  Future<void> pumpShell(WidgetTester t, MullStore store) async {
    await t.binding.setSurfaceSize(const Size(390, 844));
    await t.pumpWidget(
      StoreScope(
        store: store,
        child: ListenableBuilder(
          listenable: store,
          builder: (_, _) => MaterialApp(
            theme: buildTheme(MullColors.dark),
            home: Navigator(
              key: pages,
              onGenerateRoute: (settings) => CupertinoPageRoute(builder: (_) => const HomeShell(), settings: settings),
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  void homeTest(String description, Future<void> Function(WidgetTester t) body) => testWidgets(description, (t) async {
    try {
      await body(t);
      await t.pump(const Duration(seconds: 1));
    } finally {
      await t.binding.setSurfaceSize(null);
    }
  });

  homeTest('the number comes first', (t) async {
    await pumpShell(t, MullStore.memory()..loadSample());
    expect(find.text('You owe, all in').hitTestable(), findsOneWidget);
    expect(find.text('₹6,050').hitTestable(), findsOneWidget);
  });

  homeTest('everything waiting on you is one stack', (t) async {
    await pumpShell(t, MullStore.memory()..loadSample());
    expect(find.textContaining('NEEDS YOU · ').hitTestable(), findsOneWidget);
    expect(find.byType(NeedsYouStack), findsOneWidget);
  });

  testWidgets('a long stack shows one card until it is opened', (t) async {
    await t.pumpWidget(
      MaterialApp(
        theme: buildTheme(MullColors.dark),
        home: Scaffold(
          body: SingleChildScrollView(
            child: StoreScope(
              store: MullStore.memory(),
              child: NeedsYouStack(cards: [for (var i = 0; i < 10; i++) SizedBox(height: 80, child: Text('card $i'))]),
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('card 0').hitTestable(), findsOneWidget);
    expect(find.text('card 1').hitTestable(), findsNothing);
    await t.tap(find.byType(NeedsYouStack));
    await t.pumpAndSettle();
    for (var i = 0; i < 6; i++) {
      expect(find.text('card $i').hitTestable(), findsOneWidget, reason: 'card $i, once opened');
    }
  });

  homeTest('recent shows the last five things across every group', (t) async {
    final store = MullStore.memory()..loadSample();
    await pumpShell(t, store);
    await t.drag(find.byType(Scrollable).first, const Offset(0, -500));
    await t.pumpAndSettle();
    expect(find.text('RECENT'), findsOneWidget);
    expect(
      find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('recent-')),
      findsNWidgets(5),
    );
  });

  homeTest('"see who" goes to People', (t) async {
    await pumpShell(t, MullStore.memory()..loadSample());
    await t.tap(find.textContaining('owed to you · see who'));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('home-tab-people')).hitTestable(), findsOneWidget);
  });

  homeTest('with nothing yet, home says what Mull is for', (t) async {
    await pumpShell(t, MullStore.memory()..completeOnboarding(name: 'Bharat'));
    expect(find.textContaining('Who paid.'), findsOneWidget);
    expect(find.text('Start a group'), findsNothing, reason: 'the + starts one now');
  });
}
