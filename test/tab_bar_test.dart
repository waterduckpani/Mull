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

  barTest('no tab shows its name, but each still says it', (t) async {
    await pump(t, current: 2);
    for (final item in home) {
      expect(find.text(item.label), findsNothing);
    }
    expect(find.bySemanticsLabel('People, tab 3 of 4'), findsOneWidget);
  });

  barTest('the open tab is the one filled in', (t) async {
    await pump(t, current: 1);
    final filled = t.widgetList<MullIcon>(find.byType(MullIcon)).where((i) => i.filled).map((i) => i.glyph);
    expect(filled, [MullGlyph.grid]);
  });

  barTest('sliding along the bar opens the tab you let go on', (t) async {
    int? picked;
    await pump(t, onSelect: (i) => picked = i);
    final from = t.getCenter(find.bySemanticsLabel('Home, tab 1 of 4'));
    final to = t.getCenter(find.bySemanticsLabel('You, tab 4 of 4'));
    final finger = await t.startGesture(from);
    // Nothing opens while the finger is still down, even across the +.
    for (var step = 1; step <= 12; step++) {
      await finger.moveTo(Offset.lerp(from, to, step / 12)!);
      await t.pump(const Duration(milliseconds: 16));
    }
    expect(picked, isNull);
    // The icon under the finger fills in before it lifts.
    final lit = t.widgetList<MullIcon>(find.byType(MullIcon)).where((i) => i.filled).map((i) => i.glyph);
    expect(lit, [MullGlyph.person]);
    await finger.up();
    await t.pumpAndSettle();
    expect(picked, 3);
  });

  barTest('the highlight travels under a sliding finger, every frame of the way', (t) async {
    await pump(t);
    Offset pill() => t.getCenter(
      find.byWidgetPredicate(
        (w) =>
            w is DecoratedBox &&
            w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).borderRadius == BorderRadius.circular(24),
      ),
    );
    final from = t.getCenter(find.bySemanticsLabel('Home, tab 1 of 4'));
    final to = t.getCenter(find.bySemanticsLabel('You, tab 4 of 4'));
    final finger = await t.startGesture(from);
    // A touch update every frame, as a real finger sends them. The first bar
    // restarted its spring on each one and the highlight never left Home.
    for (var frame = 1; frame <= 40; frame++) {
      final at = Offset.lerp(from, to, frame / 40)!;
      await finger.moveTo(at);
      await t.pump(const Duration(milliseconds: 16));
      if (frame > 6) {
        expect((pill().dx - at.dx).abs(), lessThan(24), reason: 'frame $frame: the highlight fell behind the finger');
      }
    }
    await finger.up();
    await t.pumpAndSettle();
    expect(pill().dx, closeTo(to.dx, .5), reason: 'it lands on the tab let go over');
  });

  barTest('letting go over the + lands on the nearer tab', (t) async {
    int? picked;
    await pump(t, onSelect: (i) => picked = i);
    final from = t.getCenter(find.bySemanticsLabel('Home, tab 1 of 4'));
    final plus = t.getCenter(find.bySemanticsLabel('Add an expense'));
    await t.dragFrom(from, Offset(plus.dx - from.dx - 4, 0));
    await t.pumpAndSettle();
    expect(picked, 1);
    await t.dragFrom(from, Offset(plus.dx - from.dx + 4, 0));
    await t.pumpAndSettle();
    expect(picked, 2);
  });

  barTest('pressing the + never moves the highlight', (t) async {
    int? picked;
    await pump(t, onSelect: (i) => picked = i);
    await t.tap(find.bySemanticsLabel('Add an expense'));
    await t.pumpAndSettle();
    expect(picked, isNull);
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
