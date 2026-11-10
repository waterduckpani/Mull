import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mull/data/store.dart';
import 'package:mull/ui/icons.dart';
import 'package:mull/ui/tab_bar.dart';
import 'package:mull/ui/tokens.dart';

/// The bar the home screen and every group share.
void main() {
  const home = [
    TabItem('Home', MullGlyph.home),
    TabItem('Groups', MullGlyph.grid),
    TabItem('People', MullGlyph.groups),
    TabItem('You', MullGlyph.person),
  ];

  Future<void> pump(WidgetTester t, {int current = 0, ValueChanged<int>? onSelect}) async {
    await t.binding.setSurfaceSize(const Size(390, 844));
    await t.pumpWidget(
      StoreScope(
        store: MullStore.memory(),
        child: MaterialApp(
          theme: buildTheme(MullColors.dark),
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: MullTabBar(items: home, current: current, onSelect: onSelect ?? (_) {}, onAdd: () {}),
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  void barTest(String description, Future<void> Function(WidgetTester t) body) => testWidgets(description, (t) async {
    final semantics = t.ensureSemantics();
    try {
      await body(t);
    } finally {
      semantics.dispose();
      await t.binding.setSurfaceSize(null);
    }
  });

  barTest('only the open tab is named', (t) async {
    await pump(t, current: 2);
    expect(find.text('People'), findsOneWidget);
    expect(find.text('Home'), findsNothing);
  });

  barTest('the + is dead centre', (t) async {
    for (var i = 0; i < home.length; i++) {
      await pump(t, current: i);
      expect(t.getCenter(find.bySemanticsLabel('Add an expense')).dx, closeTo(195, .5));
    }
  });

  barTest('tapping a tab selects its index', (t) async {
    int? picked;
    await pump(t, onSelect: (i) => picked = i);
    await t.tap(find.bySemanticsLabel('People, tab 3 of 4'));
    expect(picked, 2);
  });
}
