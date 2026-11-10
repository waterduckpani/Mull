import 'package:flutter/cupertino.dart';

import '../../core/money.dart';
import '../../data/models.dart';
import '../../data/store.dart';
import '../../ui/group_icons.dart';
import '../../ui/icons.dart';
import '../../ui/page.dart';
import '../../ui/sheet.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets.dart';
import '../groups/expense_sheet.dart';
import '../groups/group_screen.dart';
import '../groups/group_sheets.dart';
import '../groups/icon_picker.dart';

/// How much of the screen a ledger row is allowed to take.
enum _Density {
  /// One ledger. The number goes big and the card carries the detail.
  roomy,

  /// Two or three. The icon and the people stay, the number comes back down.
  medium,

  /// Four or more. A line you scan, which is all a list this long can be.
  compact,
}

/// One entry in the GROUPS or PEOPLE list.
class _LedgerRow extends StatelessWidget {
  const _LedgerRow({
    super.key,
    required this.group,
    required this.onTap,
    this.density = _Density.compact,
  });

  final Group group;
  final VoidCallback onTap;
  final _Density density;

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

    if (density == _Density.compact) {
      return wrap(
        radius: 26,
        padding: const EdgeInsets.fromLTRB(24, 21, 24, 21),
        Row(
          children: [
            if (group.isDirect) ...[
              MullIcon(MullGlyph.person, size: 15, color: c.ink3, strokeWidth: 1.6),
              const SizedBox(width: 10),
            ] else if (group.icon != null) ...[
              Icon(groupGlyph(group.icon), size: 16, color: c.ink3),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Text(
                group.title,
                style: MullType.cardTitle(settled ? c.ink2 : c.ink, size: 18),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 12),
            Text(label, style: MullType.caption(c.ink3)),
            if (amount != null) ...[
              const SizedBox(width: 10),
              AnimatedAmount(amount, style: MullType.cardAmount(c.ink)),
            ],
          ],
        ),
      );
    }

    final roomy = density == _Density.roomy;
    final others = group.seated.where((m) => !m.isYou).toList();
    final roster = others.isEmpty
        ? 'Nobody else in here yet'
        : others.length <= 3
        ? others.map(store.shortName).join(', ')
        : '${others.take(2).map(store.shortName).join(', ')} and ${others.length - 2} more';

    return wrap(
      radius: roomy ? 32 : 28,
      padding: EdgeInsets.fromLTRB(24, roomy ? 24 : 20, 24, roomy ? 26 : 22),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GroupBadge(group: group, size: roomy ? 44 : 38, glyphSize: roomy ? 21 : 18, quiet: true),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      group.title,
                      style: MullType.cardTitle(settled ? c.ink2 : c.ink, size: roomy ? 21 : 19),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      roster,
                      style: MullType.caption(c.ink3, size: 11.5),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: roomy ? 24 : 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(child: Text(label, style: MullType.caption(c.ink3))),
              if (amount != null)
                AnimatedAmount(
                  amount,
                  style: roomy
                      ? excon(38, tracking: -.04, height: .95, color: c.ink)
                      : MullType.cardAmount(c.ink, size: 24),
                ),
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
