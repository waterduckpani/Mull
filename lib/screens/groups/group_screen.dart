import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../data/store.dart';
import '../../ui/page.dart';
import '../../ui/tokens.dart';
import 'group_bar.dart';
import 'group_sheets.dart';
import 'ledger_screen.dart';
import 'members_screen.dart';
import 'overview_tab.dart';
import 'recurring_screen.dart';

/// A group: four tabs under one bar.
///
/// Each tab is a page of its own, with its own scroll position, and all four
/// stay built while you are in the group, so going to the ledger and back
/// does not lose your place. The bar sits over them and never moves: it is
/// not part of any tab, so switching does not redraw it in a new spot.
class GroupScreen extends StatefulWidget {
  const GroupScreen({super.key, required this.groupId, this.initialTab = GroupTab.overview});

  final String groupId;
  final GroupTab initialTab;

  @override
  State<GroupScreen> createState() => _GroupScreenState();
}

class _GroupScreenState extends State<GroupScreen> {
  late GroupTab _tab = widget.initialTab;

  void _select(GroupTab tab) => setState(() => _tab = tab);

  @override
  Widget build(BuildContext context) {
    final store = context.store;
    final c = context.c;
    final group = store.groupById(widget.groupId);
    if (group == null) return const SizedBox.shrink();

    final barBottom = ShellMetrics.ctaBottom(context);
    // Android's Back goes to Overview before it leaves, the way a tabbed app
    // does there. iOS has no Back, only the swipe, and blocking the swipe on
    // three tabs out of four would make it feel broken.
    // The device's own platform, not the theme's: the theme is iOS everywhere.
    final android = defaultTargetPlatform == TargetPlatform.android;

    return PopScope(
      canPop: _tab == GroupTab.overview || !android,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _select(GroupTab.overview);
      },
      child: Stack(
        children: [
          IndexedStack(
            index: _tab.index,
            sizing: StackFit.expand,
            children: [
              OverviewTab(groupId: group.id, onSelectTab: _select, bottomInset: GroupBar.height),
              LedgerScreen(groupId: group.id, bottomInset: GroupBar.height),
              RecurringScreen(groupId: group.id, bottomInset: GroupBar.height),
              GroupMembersScreen(groupId: group.id, bottomInset: GroupBar.height),
            ],
          ),
          // What scrolls under the bar fades into the page rather than
          // running into its edge.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: barBottom + GroupBar.height / 2 + 44,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [c.screen.withValues(alpha: 0), c.screen, c.screen],
                    stops: const [0, .55, 1],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: barBottom,
            child: GroupBar(
              current: _tab,
              onSelect: _select,
              addEnabled: group.seated.length >= 2,
              onAdd: () => showAddExpense(context, group),
            ),
          ),
        ],
      ),
    );
  }
}
