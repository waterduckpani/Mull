import 'package:flutter/material.dart';

import '../../core/money.dart';
import '../../core/split.dart';
import '../../data/models.dart';
import '../../data/store.dart';
import '../../ui/page.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets.dart';
import 'group_sheets.dart';

/// Who you pay and who pays you, on the group's Overview.
///
/// This was a screen of its own behind a card that said "Nothing to settle
/// yet" more often than not. Now it is a section that is only there when there
/// is money to move, and says so in one line when the only debts left in the
/// group are between other people.
class SettleUpSection extends StatelessWidget {
  const SettleUpSection({super.key, required this.group, this.lead = true});

  final Group group;

  /// Whether the first payment is the one focal object on the page. Not when
  /// a claim or a due schedule above it already is.
  final bool lead;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final transfers = group.yourTransfers;
    // Two people with no account between them have nobody else to write
    // their payment down. Anybody else's is theirs alone.
    final books = group.placeholderTransfers;

    if (transfers.isEmpty && books.isEmpty) {
      // Balances between other people are theirs. Said once, so a group that
      // is plainly not settled does not read as a bug.
      if (group.isSettled || group.expenses.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.fromLTRB(Gutter.text, 30, Gutter.text, 0),
        child: Text(
          'Other people here still owe each other. That is between them, and only they can settle it.',
          style: MullType.caption(c.ink3),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Eyebrow(
          'Settle up',
          size: 10.5,
          tracking: .18,
          padding: EdgeInsets.fromLTRB(Gutter.text, 34, Gutter.text, 14),
        ),
        if (transfers.isNotEmpty)
          Stacked(
            gap: 8,
            padding: const EdgeInsets.symmetric(horizontal: Gutter.card),
            children: [
              for (final t in transfers)
                TransferCard(
                  key: ValueKey('${t.from}-${t.to}'),
                  group: group,
                  transfer: t,
                  lift: lead && t == transfers.first ? Lift.focal : Lift.card,
                ),
            ],
          ),
        if (books.isNotEmpty) ...[
          Padding(
            padding: EdgeInsets.fromLTRB(Gutter.text, transfers.isEmpty ? 0 : 26, Gutter.text, 14),
            child: Text(
              'Neither of these people is on Mull, so you keep the record for them.',
              style: MullType.caption(c.ink3),
            ),
          ),
          Stacked(
            gap: 8,
            padding: const EdgeInsets.symmetric(horizontal: Gutter.card),
            children: [
              for (final t in books)
                TransferCard(key: ValueKey('${t.from}-${t.to}'), group: group, transfer: t, lift: Lift.flat),
            ],
          ),
        ],
        const SizedBox(height: 18),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Gutter.card),
          child: SecondaryButton('Send summary on WhatsApp', onTap: () => shareGroupSummary(context, group)),
        ),
        const Footnote(
          'Money never moves through Mull.\nPay over UPI, then say it went through.',
          padding: EdgeInsets.fromLTRB(Gutter.text, 14, Gutter.text, 0),
        ),
      ],
    );
  }
}

/// One payment with you in it, or between two people only you can record it
/// for. Tapping it opens what can be done about it: pay, nudge, confirm.
class TransferCard extends StatelessWidget {
  const TransferCard({
    super.key,
    required this.group,
    required this.transfer,
    required this.lift,
  });

  final Group group;
  final Transfer transfer;
  final Lift lift;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final store = context.store;
    final from = group.memberById(transfer.from);
    final to = group.memberById(transfer.to);
    if (from == null || to == null) return const SizedBox.shrink();

    final youPay = from.isYou;
    final forThem = !youPay && !to.isYou;
    final other = youPay ? to : from;
    final name = store.shortName(other);

    // What has already been said to have gone, and what that leaves. A claim
    // does not move the balance until it is confirmed, so without this the
    // card kept offering the whole amount again — pay twice, and send them a
    // second "says they sent you" for the same money.
    final claimed = group.claimedBetween(transfer.from, transfer.to);
    final left = (transfer.amount - claimed).clamp(0, transfer.amount);
    final claim = group.settlements
        .where(
          (s) =>
              s.status == SettlementStatus.pending &&
              s.fromId == transfer.from &&
              s.toId == transfer.to,
        )
        .firstOrNull;

    final title = forThem
        ? '${store.shortName(from)} pays ${store.shortName(to)}'
        : youPay
        ? 'You pay $name'
        : '$name pays you';
    final shown = claimed > 0 && left > 0 ? left : transfer.amount;

    final detail = switch (null) {
      _ when forThem => 'Neither is on Mull · mark it once they have settled',
      _ when claim != null && !youPay && left == 0 => 'They said they sent it · check and confirm',
      _ when claim != null && !youPay =>
        'They said they sent ${inr(claimed)} · check and confirm',
      _ when claim != null && left == 0 => 'Sent · waiting on $name to confirm',
      _ when claim != null => '${inr(claimed)} sent, waiting on $name · ${inr(left)} still to pay',
      _ when youPay && to.upiId != null => 'Pay over UPI, then say it went through',
      _ when youPay => 'No UPI ID on their seat yet · settle in person, then mark it',
      _ when !from.isLinked => 'Not on Mull · settle in person, then mark it',
      _ => 'Nudge them, or mark it once it lands',
    };

    void open() {
      switch (claim) {
        case _ when forThem:
          showSettleUp(context, group, transfer);
        case final pending? when !youPay:
          showClaimCheck(context, group, pending);
        case final pending? when left == 0:
          showOwnClaim(context, group, pending);
        default:
          showSettleUp(
            context,
            group,
            Transfer(from: transfer.from, to: transfer.to, amount: youPay ? left : transfer.amount),
          );
      }
    }

    return Pressable(
      onTap: open,
      scale: .985,
      semanticLabel: '$title ${inr(shown)}. $detail',
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 22),
          decoration: surfaceOf(c, lift, radius: BorderRadius.circular(28)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: MullType.cardTitle(c.ink, size: 18),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(inr(shown), style: MullType.cardAmount(c.ink, size: 22)),
                ],
              ),
              const SizedBox(height: 8),
              Text(detail, style: MullType.body(c.ink3)),
            ],
          ),
        ),
      ),
    );
  }
}
