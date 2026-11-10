import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mull/data/store.dart';
import 'package:mull/screens/groups/group_bar.dart';
import 'package:mull/ui/tokens.dart';

/// The bar under every group tab. What matters is that it holds still: the +
/// is where a thumb goes without looking, so it may not drift when the open
/// tab's name appears, and neither may the icons beside it.
void main() {
  Future<void> pumpBar(
    WidgetTester t, {
    GroupTab current = GroupTab.overview,
    ValueChanged<GroupTab>? onSelect,
    VoidCallback? onAdd,
    bool addEnabled = true,
    double textScale = 1,
  }) async {
    await t.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(
      StoreScope(
        store: MullStore.memory(),
        child: MaterialApp(
          theme: buildTheme(MullColors.dark),
          home: MediaQuery(
            data: MediaQueryData(size: const Size(390, 844), textScaler: TextScaler.linear(textScale)),
            child: Scaffold(
              body: Align(
                alignment: Alignment.bottomCenter,
                child: GroupBar(
                  current: current,
                  onSelect: onSelect ?? (_) {},
                  onAdd: onAdd ?? () {},
                  addEnabled: addEnabled,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  // The bar is found the way a screen reader finds it, which needs semantics
  // on for the length of each test and off again before it ends.
  void barTest(String description, Future<void> Function(WidgetTester t) body) =>
      testWidgets(description, (t) async {
        final semantics = t.ensureSemantics();
        try {
          await body(t);
        } finally {
          semantics.dispose();
        }
      });

  Finder tab(String name) => find.bySemanticsLabel(RegExp('^$name, tab'));
  Finder plus() => find.bySemanticsLabel('Add an expense');

  barTest('only the open tab shows its name', (t) async {
    await pumpBar(t, current: GroupTab.ledger);
    expect(find.text('Ledger'), findsOneWidget);
    expect(find.text('Overview'), findsNothing);
    expect(find.text('Recurring'), findsNothing);
    expect(find.text('People'), findsNothing);
  });

  barTest('the + sits dead centre whichever tab is open', (t) async {
    for (final open in GroupTab.values) {
      await pumpBar(t, current: open);
      expect(t.getCenter(plus()).dx, closeTo(195, .5), reason: '${open.label} open');
    }
  });

  barTest('icons do not move when the tab changes', (t) async {
    Future<List<Offset>> centres(GroupTab open) async {
      await pumpBar(t, current: open);
      return [for (final name in ['Overview', 'Ledger', 'Recurring', 'People']) t.getCenter(tab(name))];
    }

    expect(await centres(GroupTab.people), await centres(GroupTab.overview));
  });

  barTest('tapping a tab selects it', (t) async {
    GroupTab? picked;
    await pumpBar(t, onSelect: (tab) => picked = tab);
    await t.tap(tab('People'));
    expect(picked, GroupTab.people);
  });

  barTest('a disabled + says why and adds nothing', (t) async {
    var added = false;
    await pumpBar(t, addEnabled: false, onAdd: () => added = true);
    await t.tap(plus());
    await t.pump(const Duration(milliseconds: 300));
    expect(added, isFalse);
    expect(find.text('Add someone first'), findsOneWidget);
    await t.pump(const Duration(seconds: 5));
  });

  barTest('large text does not overflow the open tab', (t) async {
    await pumpBar(t, current: GroupTab.recurring, textScale: 1.5);
    expect(t.takeException(), isNull);
    expect(t.getCenter(plus()).dx, closeTo(195, .5));
  });

  barTest('tabs announce themselves', (t) async {
    await pumpBar(t, current: GroupTab.ledger);
    expect(
      t.getSemantics(find.bySemanticsLabel('Ledger, tab 2 of 4')),
      matchesSemantics(label: 'Ledger, tab 2 of 4', isButton: true, isEnabled: true, hasEnabledState: true,
          isSelected: true, hasSelectedState: true, hasTapAction: true),
    );
  });
}
