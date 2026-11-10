import 'package:flutter/cupertino.dart';

import '../../core/money.dart';
import '../../data/models.dart';
import '../../data/store.dart';
import '../../ui/page.dart';
import '../../ui/sheet.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets.dart';
import '../groups/group_screen.dart';
import '../groups/group_sheets.dart';
import '../groups/icon_picker.dart';

/// The Groups tab: every group as a line you can scan.
///
/// On the old home they were cards, roomy enough that one and a half fitted
/// on a phone under everything waiting on you. Here they are the whole page,
/// in the order that matters: what you owe, then what you are owed, then the
/// ones that are settled, under their own heading.
class GroupsTabPage extends StatelessWidget {
  const GroupsTabPage({super.key, this.bottomInset = 0, required this.onStart});

  /// Room under the content for the bar.
  final double bottomInset;

  /// Starts a group.
  final Future<void> Function({String? name}) onStart;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final store = context.store;
    final groups = store.namedGroups;
    bool settled(Group g) => g.youOweHere == 0 && g.owedToYouHere == 0;
    final open = groups.where((g) => !settled(g)).toList();
    final done = groups.where(settled).toList();

    void openGroup(Group g) => Navigator.of(context).push(
      CupertinoPageRoute(builder: (_) => GroupScreen(groupId: g.id)),
    );

    Widget rows(List<Group> list) => Stacked(
      gap: 8,
      padding: const EdgeInsets.symmetric(horizontal: Gutter.card),
      children: [
        for (final g in list) _LedgerRow(key: ValueKey(g.id), group: g, onTap: () => openGroup(g)),
      ],
    );

    return MullPage(
      bottomInset: bottomInset,
      glow: const GlowSpec(size: 430, top: -160, left: -150, right: null),
      onRefresh: store.pullNow,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Gutter.text, 22, Gutter.card, 0),
          child: Row(
            children: [
              Expanded(
                child: Semantics(header: true, child: Text('Groups', style: MullType.screenTitle(c.ink))),
              ),
              // Here rather than at the end of the list, so it is in the same
              // place however many groups there are.
              InlineButton('+ New group', height: 40, filled: false, onTap: () => onStart()),
            ],
          ),
        ),
        const SizedBox(height: 26),
        if (groups.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gutter.text),
            child: Text(
              'No groups yet. A flat, a trip, a dinner: start one and add who is in it.',
              style: MullType.body(c.ink3),
            ),
          ),
        if (open.isNotEmpty) rows(open),
        if (done.isNotEmpty) ...[
          const Eyebrow(
            'Settled',
            size: 10.5,
            tracking: .18,
            padding: EdgeInsets.fromLTRB(Gutter.text, 34, Gutter.text, 14),
          ),
          rows(done),
        ],
        const SizedBox(height: 12),
      ],
    );
  }
}

/// One entry in the GROUPS or PEOPLE list.
class _LedgerRow extends StatelessWidget {
  const _LedgerRow({
    super.key,
    required this.group,
    required this.onTap,
  });

  final Group group;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final store = context.store;
    // Both directions, never netted: what you owe one person and what another
    // owes you are two debts, and the row used to call them "settled up".
    final owing = group.youOweHere;
    final owed = group.owedToYouHere;
    final settled = owing == 0 && owed == 0;

    final (label, amount) = switch (null) {
      _ when owing > 0 && owed > 0 => ('get back ${inr(owed)} · you owe', owing),
      _ when owing > 0 => ('you owe', owing),
      _ when owed > 0 => ('you get back', owed),
      _ => ('settled up', null),
    };

    // A settled ledger is still worth seeing and not worth reading. It sinks
    // rather than disappearing, so the list stays a record of who you split
    // with instead of emptying out every time everyone pays up.
    final lift = settled ? Lift.flat : Lift.card;

    // One label for the whole row. Read out piece by piece it becomes "Goa
    // trip, you owe, two thousand four hundred" spread over four stops.
    Widget wrap(Widget child, {required double radius, required EdgeInsets padding}) => Semantics(
      button: true,
      label: amount == null ? '${group.title}, settled up' : '${group.title}, $label ${inr(amount)}',
      child: ExcludeSemantics(
        child: Pressable(
          onTap: onTap,
          onLongPress: () => showLedgerActions(context, group),
          scale: .985,
          // A settled ledger recedes by sitting flatter and saying "settled
          // up", not by being faded out. Wrapping the row in Opacity took
          // every caption on it to 2.6:1 against the screen, well under the
          // 4.5:1 this design went to some trouble to clear everywhere else —
          // and the rule here has always been that hierarchy is how high a
          // surface floats.
          child: Container(
            padding: padding,
            decoration: surfaceOf(c, lift, radius: BorderRadius.circular(radius)),
            child: child,
          ),
        ),
      ),
    );

    final others = group.seated.where((m) => !m.isYou).toList();
    final roster = others.isEmpty
        ? 'Nobody else in here yet'
        : others.length <= 3
        ? others.map(store.shortName).join(', ')
        : '${others.take(2).map(store.shortName).join(', ')} and ${others.length - 2} more';

    // Two lines, as the Groups tab was drawn: who is in it under the name,
    // and which way the money points over the amount. One line ran the
    // label into the name on a narrow phone.
    return wrap(
      radius: 24,
      padding: const EdgeInsets.fromLTRB(18, 14, 20, 14),
      Row(
        children: [
          GroupBadge(group: group, size: 38, glyphSize: 18, quiet: true),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  group.title,
                  style: MullType.cardTitle(settled ? c.ink2 : c.ink, size: 17),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  roster,
                  style: MullType.caption(c.ink3, size: 11.5),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(label, style: MullType.caption(c.ink3, size: 11)),
              if (amount != null) AnimatedAmount(amount, style: MullType.cardAmount(c.ink, size: 18)),
            ],
          ),
        ],
      ),
    );
  }
}

/// Long-press on a ledger row.
Future<void> showLedgerActions(BuildContext context, Group group) {
  return showMullSheet(
    context,
    fitContent: true,
    builder: (sheet) {
      void run(VoidCallback action) {
        Navigator.of(sheet).pop();
        Future.delayed(const Duration(milliseconds: 160), action);
      }

      return Padding(
        padding: const EdgeInsets.fromLTRB(Gutter.text, 26, Gutter.text, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(group.title, style: MullType.screenTitle(sheet.c.ink), maxLines: 2),
            const SizedBox(height: 16),
            CardRows(
              children: [
                SheetAction('Add an expense', onTap: () => run(() => showAddExpense(context, group))),
                // The thing people most often came here to do, and the one
                // action this menu did not offer. Settling was four screens
                // deep with no shortcut to it anywhere.
                if (!group.youAreSquare)
                  SheetAction(
                    'Settle up',
                    detail: switch ((group.youOweHere, group.owedToYouHere)) {
                      (> 0 && final owe, > 0 && final back) => 'you owe ${inr(owe)} · get back ${inr(back)}',
                      (> 0 && final owe, _) => 'you owe ${inr(owe)}',
                      (_, final back) => 'you get back ${inr(back)}',
                    },
                    onTap: () => run(
                      () => Navigator.of(context).push(
                        // Settling up is on the group's Overview now.
                        CupertinoPageRoute(builder: (_) => GroupScreen(groupId: group.id)),
                      ),
                    ),
                  ),
                SheetAction(
                  'Send summary on WhatsApp',
                  onTap: () => run(() => shareGroupSummary(context, group)),
                ),
                // Only an admin can delete a group; the server refuses anyone
                // else, and the group used to vanish here and come back.
                if (group.youAreAdmin)
                  SheetAction(
                    group.isDirect ? 'Delete this ledger' : 'Delete group',
                    destructive: true,
                    onTap: () => run(() => confirmDeleteGroup(context, group)),
                  ),
              ],
            ),
          ],
        ),
      );
    },
  );
}
