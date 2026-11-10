import 'package:flutter/cupertino.dart';

import '../../core/money.dart';
import '../../data/store.dart';
import '../../ui/icons.dart';
import '../../ui/page.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets.dart';
import '../friends_sheet.dart';
import '../groups/group_screen.dart';
import '../people_sheet.dart';
import 'home_tab.dart' show FriendRequestsCard;

/// The People tab: who you pay, and who pays you.
///
/// Netted per person across every ledger you share — the trip and the flat
/// are one row for Sahil, in one direction — with Pay or Nudge right on the
/// row, because that is the decision this list exists for. Friends lives
/// here too: the requests, and a way in to add, invite or block.
class PeopleTabPage extends StatefulWidget {
  const PeopleTabPage({super.key, this.bottomInset = 0});

  /// Room under the content for the bar.
  final double bottomInset;

  @override
  State<PeopleTabPage> createState() => _PeopleTabPageState();
}

class _PeopleTabPageState extends State<PeopleTabPage> {
  bool _showSquare = false;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final store = context.store;
    final people = store.standings;
    final youOwe = people.where((s) => !s.isSquare && !s.theyOweYou).toList();
    final owesYou = people.where((s) => !s.isSquare && s.theyOweYou).toList();
    final square = people.where((s) => s.isSquare).toList();

    void open(String groupId) {
      if (store.groupById(groupId) == null) return;
      Navigator.of(context).push(CupertinoPageRoute(builder: (_) => GroupScreen(groupId: groupId)));
    }

    Widget section(String title, List<Standing> list, {required String action}) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Eyebrow(title, size: 10.5, tracking: .18, padding: const EdgeInsets.fromLTRB(Gutter.text, 30, Gutter.text, 12)),
        Surface(
          lift: Lift.card,
          radius: 26,
          margin: const EdgeInsets.symmetric(horizontal: Gutter.card),
          padding: const EdgeInsets.fromLTRB(18, 4, 14, 4),
          child: CardRows(
            children: [
              for (final s in list)
                PersonLine(
                  key: ValueKey(s.member.id),
                  standing: s,
                  action: action,
                  onAction: () => action == 'Pay' ? settleWithPerson(context, s) : nudgePerson(context, s),
                  onOpenLedger: open,
                ),
            ],
          ),
        ),
      ],
    );

    return MullPage(
      bottomInset: widget.bottomInset,
      glow: const GlowSpec(size: 430, top: -160, right: -150),
      onRefresh: store.pullNow,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Gutter.text, 22, Gutter.card, 0),
          child: Row(
            children: [
              Expanded(
                child: Semantics(header: true, child: Text('People', style: MullType.screenTitle(c.ink))),
              ),
              InlineButton('+ Add a friend', height: 40, filled: false, onTap: () => showAddFriendSheet(context)),
            ],
          ),
        ),
        const SizedBox(height: 8),
        FriendRequestsCard(onOpenLedger: open),
        if (people.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(Gutter.text, 24, Gutter.text, 0),
            child: Text(
              'Everyone you split with shows up here, with what is owed between you across every group.',
              style: MullType.body(c.ink3),
            ),
          ),
        if (youOwe.isNotEmpty) section('You owe', youOwe, action: 'Pay'),
        if (owesYou.isNotEmpty) section('Owes you', owesYou, action: 'Nudge'),
        if (square.isNotEmpty) ...[
          Pressable(
            onTap: () => setState(() => _showSquare = !_showSquare),
            scale: .99,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Gutter.text, 30, Gutter.text, 12),
              child: Row(
                children: [
                  Eyebrow('Square · ${square.length}', size: 10.5, tracking: .18),
                  const Spacer(),
                  Text(_showSquare ? 'Hide' : 'Show', style: MullType.caption(c.ink2, size: 12.5)),
                ],
              ),
            ),
          ),
          if (_showSquare)
            Surface(
              lift: Lift.flat,
              radius: 26,
              margin: const EdgeInsets.symmetric(horizontal: Gutter.card),
              padding: const EdgeInsets.fromLTRB(22, 4, 18, 4),
              child: CardRows(
                children: [
                  for (final s in square) PersonRow(key: ValueKey(s.member.id), standing: s, onOpenLedger: open),
                ],
              ),
            ),
        ],
        const SizedBox(height: 26),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Gutter.card),
          child: FieldRow(
            label: 'Friends',
            value: 'Add, invite, block',
            onTap: () => showFriendsSheet(context, onOpenLedger: open),
            trailing: MullIcon(MullGlyph.chevronRight, size: 14, color: c.ink2, strokeWidth: 1.8),
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}

/// One person you owe, or who owes you, with the one thing to do about it.
class PersonLine extends StatelessWidget {
  const PersonLine({
    super.key,
    required this.standing,
    required this.action,
    required this.onAction,
    required this.onOpenLedger,
    this.sayDirection = false,
  });

  final Standing standing;
  final String action;
  final VoidCallback onAction;
  final void Function(String groupId) onOpenLedger;

  /// Whether the line says which way the money goes. Here the section above
  /// says it; on Home both directions share one card.
  final bool sayDirection;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final store = context.store;
    final member = standing.member;
    final name = store.shortName(member);
    final initials = member.name.trim().split(RegExp(r'\s+')).take(2).map((w) => w.isEmpty ? '' : w[0]).join().toUpperCase();
    final where = [
      if (sayDirection) standing.theyOweYou ? 'Owes you' : 'You owe',
      if (standing.groups.length == 1)
        standing.groups.first.isDirect ? 'just the two of you' : standing.groups.first.title
      else
        standing.groups.map((g) => g.title).join(', '),
      if (!member.isLinked) 'not on Mull',
    ].join(' · ');

    return Pressable(
      onTap: () async {
        final groupId = await showPersonSheet(context, standing);
        if (groupId != null) onOpenLedger(groupId);
      },
      scale: .99,
      semanticLabel: '$name, ${standing.theyOweYou ? 'owes you' : 'you owe'} ${inr(standing.magnitude)}',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            ExcludeSemantics(
              child: Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(shape: BoxShape.circle, color: c.quiet),
                child: Text(initials, style: MullType.caption(c.ink2, size: 12.5)),
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: ExcludeSemantics(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: ranade(15.5, color: c.ink), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(where, style: MullType.caption(c.ink3, size: 11.5), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            ExcludeSemantics(child: Text(inr(standing.magnitude), style: MullType.listAmount(c.ink))),
            const SizedBox(width: 10),
            InlineButton(action, height: 36, filled: false, onTap: onAction),
          ],
        ),
      ),
    );
  }
}
