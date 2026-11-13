import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mull/data/store.dart';
import 'package:mull/screens/groups/create_group_flow.dart';
import 'package:mull/screens/home/empty_home.dart';
import 'package:mull/screens/home/home_shell.dart';
import 'package:mull/ui/group_icons.dart';
import 'package:mull/ui/tokens.dart';

/// Home before your first group: your people across the top, then "What are
/// we splitting first?" with an answer a tap away.
void main() {
  Future<void> pumpShell(WidgetTester t, {String name = 'Bharat'}) async {
    await t.binding.setSurfaceSize(const Size(390, 844));
    final store = MullStore.memory()..completeOnboarding(name: name);
    await t.pumpWidget(
      StoreScope(
        store: store,
        child: ListenableBuilder(
          listenable: store,
          builder: (_, _) => MaterialApp(
            theme: buildTheme(MullColors.dark),
            home: Navigator(
              onGenerateRoute: (settings) => CupertinoPageRoute(builder: (_) => const HomeShell(), settings: settings),
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  void emptyTest(String description, Future<void> Function(WidgetTester t) body) => testWidgets(description, (t) async {
    final semantics = t.ensureSemantics();
    try {
      await body(t);
      await t.pump(const Duration(seconds: 1));
    } finally {
      semantics.dispose();
      await t.binding.setSurfaceSize(null);
    }
  });

  emptyTest('asks what you are splitting, by name', (t) async {
    await pumpShell(t);
    expect(find.text('Hi Bharat'), findsOneWidget);
    expect(find.text('What are we\nsplitting first?'), findsOneWidget);
    expect(find.textContaining('Who paid.'), findsNothing, reason: 'the old welcome is gone');
  });

  emptyTest('every answer is a tile, and one is your own', (t) async {
    await pumpShell(t);
    for (final starter in EmptyHome.starters) {
      expect(find.bySemanticsLabel('Start a group: $starter'), findsOneWidget, reason: starter);
    }
    expect(find.bySemanticsLabel('Start a group of your own'), findsOneWidget);
  });

  emptyTest('each tile shows the icon its group will get', (t) async {
    await pumpShell(t);
    for (final starter in EmptyHome.starters) {
      final glyph = groupGlyph(suggestGroupIcon(starter));
      expect(glyph, isNotNull, reason: '$starter has an icon');
      expect(
        find.descendant(of: find.bySemanticsLabel('Start a group: $starter'), matching: find.byIcon(glyph!)),
        findsOneWidget,
        reason: starter,
      );
    }
  });

  emptyTest('a tile starts a group with its name filled in', (t) async {
    await pumpShell(t);
    await t.tap(find.bySemanticsLabel('Start a group: Trip'));
    await t.pumpAndSettle();
    final flow = t.widget<CreateGroupFlow>(find.byType(CreateGroupFlow));
    expect(flow.initialName, 'Trip');
  });

  emptyTest('"Your own" starts a blank one', (t) async {
    await pumpShell(t);
    await t.ensureVisible(find.bySemanticsLabel('Start a group of your own'));
    await t.pumpAndSettle();
    await t.tap(find.bySemanticsLabel('Start a group of your own'));
    await t.pumpAndSettle();
    final flow = t.widget<CreateGroupFlow>(find.byType(CreateGroupFlow));
    expect(flow.initialName, isNull);
  });

  emptyTest('Invite and Add friend come first, then seats to fill', (t) async {
    await pumpShell(t);
    expect(find.bySemanticsLabel('Invite someone to Mull'), findsOneWidget);
    final row = find.byType(PeopleRow);
    final adds = find.descendant(of: row, matching: find.bySemanticsLabel('Add a friend'));
    // The button, and an empty seat for everyone who is not here yet.
    expect(adds, findsNWidgets(PeopleRow.seats - 1));
    expect(
      t.getCenter(find.bySemanticsLabel('Invite someone to Mull')).dx,
      lessThan(t.getCenter(adds.first).dx),
      reason: 'Invite is the first circle',
    );
  });

  emptyTest('no name yet still reads well', (t) async {
    await pumpShell(t, name: '');
    expect(find.text('Welcome to Mull'), findsOneWidget);
  });

  emptyTest('large text does not break the tiles', (t) async {
    await t.binding.setSurfaceSize(const Size(390, 844));
    final store = MullStore.memory()..completeOnboarding(name: 'Bharat');
    await t.pumpWidget(
      StoreScope(
        store: store,
        child: MaterialApp(
          theme: buildTheme(MullColors.dark),
          home: MediaQuery(
            data: const MediaQueryData(size: Size(390, 844), textScaler: TextScaler.linear(1.6)),
            child: const HomeShell(),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });
}
