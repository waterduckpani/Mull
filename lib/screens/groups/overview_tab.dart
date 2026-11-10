import 'package:flutter/cupertino.dart';

import '../../core/dates.dart';
import '../../core/money.dart';
import '../../data/models.dart';
import '../../data/store.dart';
import '../../ui/icons.dart';
import '../../ui/page.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets.dart';
import 'group_bar.dart';
import 'group_sheets.dart';
import 'icon_picker.dart';
import 'ledger_screen.dart';
import 'members_screen.dart';
import 'recurring_sheets.dart';
import 'settle_up_section.dart';

/// A group's first tab: where you stand, and what there is to do about it.
///
/// It only ever shows what has something in it. A new group asks for one
/// thing at a time: the people first, then the first expense, and nothing
/// else until those are done. Once it is in use, the number comes first, then
/// anything waiting on an answer, then who to pay, then the last few things
/// that happened. Settling up used to be a screen of its own behind a card
/// that, more often than not, said there was nothing to settle.
class OverviewTab extends StatelessWidget {
  const OverviewTab({super.key, required this.groupId, required this.onSelectTab, this.bottomInset = 0});

  final String groupId;

  /// Switches the group screen to another tab: "See all" goes to the ledger.
  final ValueChanged<GroupTab> onSelectTab;

  /// Room under the content for the group screen's bar.
  final double bottomInset;

  @override
  Widget build(BuildContext context) {
    final store = context.store;
    final c = context.c;
    final group = store.groupById(groupId);
    if (group == null) return const SizedBox.shrink();

    // Your two directions, never netted into one: owed ₹226 by one person and
    // owing ₹226 to another is not "all settled up".
    final owing = group.youOweHere;
    final owed = group.owedToYouHere;
    final claims = group.awaitingYourConfirmation;
    final due = group.recurring.where((r) => r.isDue(store.now())).toList();

    // A group of one cannot do anything: every split is a split with
    // yourself. It is easy to end up in by tapping straight through the
    // create flow, so the screen asks for the people and nothing else.
    final alone = group.seated.length < 2;
    final nothingYet = group.expenses.isEmpty && group.settlements.isEmpty;

    // Only an admin renames, and a one-to-one ledger is named after the
    // other person, so there is nothing to edit.
    final canEdit = group.youAreAdmin && !group.isDirect;

    final waiting = [
      for (final settlement in claims)
        _ClaimCard(
          key: ValueKey(settlement.id),
          group: group,
          settlement: settlement,
          lift: settlement == claims.first ? Lift.focal : Lift.card,
        ),
      for (final schedule in due)
        _DueCard(
          key: ValueKey(schedule.id),
          group: group,
          schedule: schedule,
          lift: claims.isEmpty && schedule == due.first ? Lift.focal : Lift.card,
        ),
    ];

    final latest = store.activity(group).take(3).toList();
    final settled = store.settledExpenses(group);

    final page = MullPage(
      bottomInset: bottomInset,
      glow: const GlowSpec(size: 440, top: -160, left: -150, right: null),
      onRefresh: store.pullNow,
      header: const DetailBar(),
      children: [
        // The icon sits beside the title, not above it: above cost 66 points
        // this screen does not have, and a 44px badge next to a 32pt title
        // reads as part of the name rather than as a control.
        Pressable(
          onTap: canEdit ? () => showEditGroup(context, group) : null,
          scale: .985,
          semanticLabel: canEdit ? '${group.title}, edit name and icon' : group.title,
          child: ExcludeSemantics(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Gutter.text, 22, Gutter.text, 0),
              child: Row(
                children: [
                  if (!group.isDirect) ...[
                    GroupBadge(group: group, size: 44, glyphSize: 21),
                    const SizedBox(width: 16),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          group.title,
                          style: MullType.screenTitle(c.ink),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          switch (null) {
                            _ when group.isDirect => 'Just you two',
                            _ when alone => 'Just you so far',
                            _ => '${group.seated.length} people',
                          },
                          style: MullType.caption(c.ink3, size: 12.5),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        if (alone)
          Surface(
            lift: Lift.focal,
            radius: 28,
            margin: const EdgeInsets.fromLTRB(Gutter.card, 34, Gutter.card, 0),
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Eyebrow("Who's in?", size: 10.5, tracking: .18),
                const SizedBox(height: 14),
                Text(
                  "Add the people you're splitting with, and Mull starts working out who owes whom.",
                  style: MullType.body(c.ink3),
                ),
                const SizedBox(height: 20),
                InlineButton(
                  'Add people',
                  height: 48,
                  expand: true,
                  onTap: () => addPeopleFromFriends(context, group),
                ),
              ],
            ),
          )
        else if (nothingYet) ...[
          const PageStatement(
            'Nothing spent yet.',
            body: 'Who paid for what goes here, and Mull works out who owes whom.',
            padding: EdgeInsets.fromLTRB(Gutter.text, 40, Gutter.text, 0),
          ),
          // A schedule set up before anything was spent can still come due.
          if (waiting.isNotEmpty)
            Stacked(
              gap: 8,
              padding: const EdgeInsets.fromLTRB(Gutter.card, 30, Gutter.card, 0),
              children: waiting,
            ),
        ] else ...[
          HeroAmount(
            caption: switch (null) {
              _ when owing > 0 => 'You owe',
              _ when owed > 0 => 'You get back',
              _ => "You're square",
            },
            amount: owing > 0 ? owing : (owed > 0 ? owed : null),
            size: 68,
            placeholder: 'You owe\nnobody here.',
            padding: const EdgeInsets.fromLTRB(Gutter.text, 34, Gutter.text, 0),
          ),
          if (owing > 0 && owed > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(Gutter.text, 12, Gutter.text, 0),
              child: Text(
                'And you get back ${inr(owed)} from someone else. Separate people, '
                'so neither cancels the other.',
                style: MullType.caption(c.ink3, size: 12.5),
              ),
            ),

          // Anything with a deadline on it, before the money.
          if (waiting.isNotEmpty)
            Stacked(
              gap: 8,
              padding: const EdgeInsets.fromLTRB(Gutter.card, 34, Gutter.card, 0),
              children: waiting,
            ),

          SettleUpSection(group: group, lead: waiting.isEmpty),

          if (latest.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(Gutter.text, 36, Gutter.text, 6),
              child: Row(
                children: [
                  const Expanded(child: Eyebrow('Latest', size: 10.5, tracking: .18)),
                  Pressable(
                    onTap: () => onSelectTab(GroupTab.ledger),
                    scale: .95,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text('See all', style: MullType.caption(c.ink2, size: 12.5)),
                    ),
                  ),
                ],
              ),
            ),
            for (final item in latest)
              switch (item) {
                Expense e => ExpenseRow(
                  key: ValueKey(e.id),
                  group: group,
                  expense: e,
                  settled: settled.contains(e.id),
                ),
                Settlement s => SettlementRow(key: ValueKey(s.id), group: group, settlement: s),
                _ => const SizedBox.shrink(),
              },
          ],

          if (group.expenses.isNotEmpty)
            Footnote(
              '${inr(group.total)} spent between ${group.members.length} people',
              padding: const EdgeInsets.fromLTRB(Gutter.text, 22, Gutter.text, 0),
            ),
        ],
      ],
    );

    if (alone || !nothingYet) return page;

    // The one thing left to do is the +, so the screen points at it.
    return Stack(
      children: [
        page,
        Positioned(
          left: 0,
          right: 0,
          bottom: ShellMetrics.ctaBottom(context) + GroupBar.height + 14,
          child: IgnorePointer(
            child: Column(
              children: [
                Text('Tap + to add the first expense', style: MullType.caption(c.ink3, size: 12.5)),
                const SizedBox(height: 6),
                MullIcon(MullGlyph.chevronDown, size: 16, color: c.ink3, strokeWidth: 1.6),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Someone says they have paid you, inside the group it happened in.
class _ClaimCard extends StatelessWidget {
  const _ClaimCard({
    super.key,
    required this.group,
    required this.settlement,
    required this.lift,
  });

  final Group group;
  final Settlement settlement;
  final Lift lift;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final store = context.store;
    final from = group.memberById(settlement.fromId);
    if (from == null) return const SizedBox.shrink();

    return Surface(
      lift: lift,
      radius: 28,
      padding: const EdgeInsets.fromLTRB(22, 18, 16, 18),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${store.shortName(from)} says they sent you',
                  style: ranade(16, height: 1.35, color: c.ink),
                ),
                const SizedBox(height: 2),
                Text(inr(settlement.amount), style: ranade(16, height: 1.35, color: c.ink)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          InlineButton(
            'Check',
            height: 48,
            onTap: () => showClaimCheck(context, group, settlement),
          ),
        ],
      ),
    );
  }
}

/// A schedule whose turn has come.
class _DueCard extends StatelessWidget {
  const _DueCard({
    super.key,
    required this.group,
    required this.schedule,
    required this.lift,
  });

  final Group group;
  final Recurring schedule;
  final Lift lift;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final store = context.store;

    return Surface(
      lift: lift,
      radius: 28,
      padding: const EdgeInsets.fromLTRB(22, 18, 16, 18),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${schedule.description} is due ${relativeDay(schedule.nextDue, store.now())}',
                  style: ranade(16, height: 1.35, color: c.ink),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  '${inr(schedule.amount)} · ${schedule.frequency.shortLabel}',
                  style: MullType.caption(c.ink3, size: 11.5),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          InlineButton(
            'Open it',
            height: 48,
            onTap: () => showDueRecurring(context, group, schedule),
          ),
        ],
      ),
    );
  }
}
