import 'package:flutter/material.dart';

import '../../core/money.dart';
import '../../data/store.dart';
import '../../ui/page.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets.dart';
import 'group_sheets.dart';
import 'settle_up_section.dart';

/// What you owe, and what you are owed, in one group — and nothing else.
///
/// It used to show the fewest transfers that clear the whole group. That put
/// other people's payments on your screen with a "Mark as settled" button, and
/// it netted you out of the middle: owed ₹226 by one person and owing ₹226 to
/// another, you were "square" and they were told to pay each other.
class SettleUpScreen extends StatelessWidget {
  const SettleUpScreen({super.key, required this.groupId});

  final String groupId;

  @override
  Widget build(BuildContext context) {
    final store = context.store;
    final group = store.groupById(groupId);
    if (group == null) return const SizedBox.shrink();

    final transfers = group.yourTransfers;
    final books = group.placeholderTransfers;
    final owing = group.youOweHere;
    final owed = group.owedToYouHere;
    // Balances between other people are theirs. Said once, so an empty screen
    // in a group that is plainly not settled does not read as a bug.
    final othersOpen = transfers.isEmpty && books.isEmpty && !group.isSettled;

    return MullPage(
      glow: const GlowSpec(size: 440, top: -160, right: -150),
      header: const DetailBar(),
      footnote: transfers.isEmpty
          ? null
          : 'Money never moves through Mull.\nPay over UPI, then say it went through.',
      bottom: group.isSettled
          ? null
          : SecondaryButton(
              'Send summary on WhatsApp',
              onTap: () => shareGroupSummary(context, group),
            ),
      children: [
        PageStatement(
          switch (null) {
            _ when group.expenses.isEmpty => 'Nothing added to this group yet',
            _ when transfers.isEmpty => "You're square here",
            _ when owing > 0 && owed > 0 => 'You owe ${inr(owing)} and are owed ${inr(owed)}',
            _ when owing > 0 => 'You owe ${inr(owing)}',
            _ => "You're owed ${inr(owed)}",
          },
          body: switch (null) {
            _ when group.expenses.isEmpty => 'Add an expense and Mull starts working out who owes whom.',
            _ when othersOpen =>
              'Other people here still owe each other. That is between them, '
                  'and only they can settle it.',
            _ when owing > 0 && owed > 0 =>
              'These are separate people, so they do not cancel out. Each one '
                  'is settled on its own.',
            _ => '${group.title} · ${inr(group.total)} spent between '
                '${group.seated.length} people',
          },
          padding: const EdgeInsets.fromLTRB(Gutter.text, 30, Gutter.text, 0),
        ),

        if (transfers.isNotEmpty) ...[
          const SizedBox(height: 40),
          Stacked(
            gap: 8,
            padding: const EdgeInsets.symmetric(horizontal: Gutter.card),
            children: [
              for (final t in transfers)
                TransferCard(
                  key: ValueKey('${t.from}-${t.to}'),
                  group: group,
                  transfer: t,
                  lift: t == transfers.first ? Lift.focal : Lift.card,
                ),
            ],
          ),
        ],

        // Two people with no account between them have nobody else to write
        // their payment down. Anybody else's is theirs alone.
        if (books.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(Gutter.text, 40, Gutter.text, 14),
            child: Text(
              'Neither of these people is on Mull, so you keep the record for them.',
              style: MullType.caption(context.c.ink3),
            ),
          ),
          Stacked(
            gap: 8,
            padding: const EdgeInsets.symmetric(horizontal: Gutter.card),
            children: [
              for (final t in books)
                TransferCard(
                  key: ValueKey('${t.from}-${t.to}'),
                  group: group,
                  transfer: t,
                  lift: Lift.flat,
                ),
            ],
          ),
        ],
      ],
    );
  }
}
