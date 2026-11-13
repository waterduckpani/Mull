import 'package:flutter/cupertino.dart';

import '../../core/money.dart';
import '../../data/remote/friends_service.dart';
import '../../data/store.dart';
import '../../ui/icons.dart';
import '../../ui/page.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets.dart';
import '../friends_sheet.dart';
import '../groups/group_screen.dart';
import '../people_sheet.dart';

/// The People tab: who you pay, who pays you, and your friends.
///
/// Netted per person across every ledger you share — the trip and the flat
/// are one row for Sahil, in one direction — with Pay or Nudge right on the
/// row, because that is the decision this list exists for. Your friends are
/// listed under that. They used to be behind a row called Friends that opened
/// a sheet, so seeing who your friends were took a tap on something that
/// looked like a setting.
class PeopleTabPage extends StatefulWidget {
  const PeopleTabPage({super.key, this.bottomInset = 0});

  /// Room under the content for the bar.
  final double bottomInset;

  @override
  State<PeopleTabPage> createState() => _PeopleTabPageState();
}

class _PeopleTabPageState extends State<PeopleTabPage> with FriendActions {
  bool _showSquare = false;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final store = context.store;
    final people = store.standings;
    final youOwe = people.where((s) => !s.isSquare && !s.theyOweYou).toList();
    final owesYou = people.where((s) => !s.isSquare && s.theyOweYou).toList();
    final square = people.where((s) => s.isSquare).toList();

    final everyone = friends;
    final requests = [...?everyone?.where((f) => f.state == FriendState.incoming)];
    final yours = [...?everyone?.where((f) => f.state != FriendState.incoming)];
    final accepted = yours.where((f) => f.state == FriendState.friends).length;

    void open(String groupId) {
      if (store.groupById(groupId) == null) return;
      Navigator.of(context).push(CupertinoPageRoute(builder: (_) => GroupScreen(groupId: groupId)));
    }

    // Where the two of you split, so a friend is more than a name.
    String together(Friend f) {
      final shared = [
        for (final g in store.groups)
          if (f.userId != null && g.seated.any((m) => m.userId == f.userId))
            g.isDirect ? 'just the two of you' : g.title,
      ];
      if (shared.isEmpty) return 'No groups together yet';
      return shared.length <= 2 ? shared.join(', ') : '${shared.take(2).join(', ')} and ${shared.length - 2} more';
    }

    // A friend you share a ledger with opens where you stand, like the rows
    // above; anyone else opens what you can do about the friendship.
    Future<void> tapFriend(Friend f) async {
      final standing = people.where((s) => f.userId != null && s.member.userId == f.userId).firstOrNull;
      if (standing == null) return moreForFriend(f);
      final groupId = await showPersonSheet(context, standing);
      if (groupId != null) open(groupId);
    }

    Widget eyebrow(String text) =>
        Eyebrow(text, size: 10.5, tracking: .18, padding: const EdgeInsets.fromLTRB(Gutter.text, 30, Gutter.text, 12));

    Widget card(List<Widget> rows, {Lift lift = Lift.card}) => Surface(
      lift: lift,
      radius: 26,
      margin: const EdgeInsets.symmetric(horizontal: Gutter.card),
      padding: const EdgeInsets.fromLTRB(18, 4, 14, 4),
      child: CardRows(children: rows),
    );

    FriendRow friendRow(Friend f) => FriendRow(
      key: ValueKey(f.friendshipId),
      friend: f,
      busy: friendsBusy,
      note: f.state == FriendState.friends ? together(f) : null,
      onTap: f.state == FriendState.friends ? () => tapFriend(f) : null,
      onAccept: () => actOnFriend(() => FriendsService.accept(f.friendshipId)),
      onMore: () => moreForFriend(f),
    );

    Widget section(String title, List<Standing> list, {required String action}) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        eyebrow(title),
        card([
          for (final s in list)
            PersonLine(
              key: ValueKey(s.member.id),
              standing: s,
              action: action,
              onAction: () => action == 'Pay' ? settleWithPerson(context, s) : nudgePerson(context, s),
              onOpenLedger: open,
            ),
        ]),
      ],
    );

    return MullPage(
      bottomInset: widget.bottomInset,
      glow: const GlowSpec(size: 430, top: -160, right: -150),
      onRefresh: () => Future.wait([store.pullNow(), loadFriends()]),
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
        // Waiting on you, so first.
        if (requests.isNotEmpty) ...[
          eyebrow('Wants to split with you · ${requests.length}'),
          card([for (final f in requests) friendRow(f)], lift: Lift.focal),
        ],
        if (youOwe.isNotEmpty) section('You owe', youOwe, action: 'Pay'),
        if (owesYou.isNotEmpty) section('Owes you', owesYou, action: 'Nudge'),
        if (everyone != null) ...[
          eyebrow(accepted == 0 ? 'Friends' : 'Friends · $accepted'),
          card([
            if (yours.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 14, 4, 12),
                child: Text(
                  'Nobody yet. Add the people you split with: their name and UPI ID '
                  'come from their own account, so nobody types anyone else\'s.',
                  style: MullType.body(c.ink3),
                ),
              ),
            for (final f in yours) friendRow(f),
            _InviteLine(onTap: () => inviteToMull(context)),
          ]),
        ],
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
        if (blocked.isNotEmpty) ...[
          eyebrow('Blocked'),
          card(lift: Lift.flat, [
            for (final b in blocked)
              Padding(
                key: ValueKey('blocked-${b.userId}'),
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  children: [
                    Expanded(child: Text(b.name, style: ranade(15, color: c.ink2))),
                    InlineButton(
                      'Unblock',
                      height: 34,
                      filled: false,
                      onTap: friendsBusy ? null : () => actOnFriend(() => FriendsService.unblock(b.userId)),
                    ),
                  ],
                ),
              ),
          ]),
        ],
        const SizedBox(height: 12),
      ],
    );
  }
}

/// The last line of Friends: for the people who are not on Mull yet.
class _InviteLine extends StatelessWidget {
  const _InviteLine({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Pressable(
      onTap: onTap,
      scale: .99,
      semanticLabel: 'Invite someone to Mull',
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(shape: BoxShape.circle, color: c.pill),
                child: MullIcon(MullGlyph.invite, size: 18, color: c.pillInk, strokeWidth: 1.7),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Invite someone to Mull', style: ranade(15.5, color: c.ink)),
                    const SizedBox(height: 2),
                    Text('Send them the app, wherever you chat', style: MullType.caption(c.ink3, size: 11.5)),
                  ],
                ),
              ),
              MullIcon(MullGlyph.chevronRight, size: 14, color: c.ink3, strokeWidth: 1.8),
              const SizedBox(width: 4),
            ],
          ),
        ),
      ),
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
