import 'package:flutter/material.dart';

import '../../ui/icons.dart';
import '../../ui/tab_bar.dart';

/// The four places inside a group, in the order the bar shows them.
enum GroupTab {
  overview('Overview', MullGlyph.overview),
  ledger('Ledger', MullGlyph.ledger),
  recurring('Recurring', MullGlyph.repeat),
  people('People', MullGlyph.groups);

  const GroupTab(this.label, this.glyph);

  final String label;
  final MullGlyph glyph;
}

/// The bar under every tab of a group: [MullTabBar] with the group's tabs.
class GroupBar extends StatelessWidget {
  const GroupBar({
    super.key,
    required this.current,
    required this.onSelect,
    required this.onAdd,
    this.addEnabled = true,
  });

  final GroupTab current;
  final ValueChanged<GroupTab> onSelect;
  final VoidCallback onAdd;

  /// False while you are alone in the group: an expense split with nobody
  /// moves no money, so the + says so instead of opening the form.
  final bool addEnabled;

  static const double height = MullTabBar.height;

  @override
  Widget build(BuildContext context) => MullTabBar(
    items: [for (final tab in GroupTab.values) TabItem(tab.label, tab.glyph)],
    current: current.index,
    onSelect: (i) => onSelect(GroupTab.values[i]),
    onAdd: onAdd,
    addEnabled: addEnabled,
  );
}
