import 'package:flutter/cupertino.dart';

import '../../core/dates.dart';
import '../../core/money.dart';
import '../../data/models.dart';
import '../../data/remote/friends_service.dart';
import '../../data/remote/live_channel.dart';
import '../../data/store.dart';
import '../../ui/icons.dart';
import '../../ui/page.dart';
import '../../ui/sheet.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets.dart';
import '../groups/expense_sheet.dart';
import '../groups/group_screen.dart';
import '../groups/group_sheets.dart';
import '../groups/icon_picker.dart';
import '../groups/recurring_sheets.dart';
import '../people_sheet.dart';
import 'home_shell.dart';
import 'empty_home.dart';
import 'needs_you.dart';
import 'people_tab.dart' show PersonLine;

/// The Home tab: where you stand, what needs you, and what just happened.
///
/// It used to be everything at once — every card waiting on you, then every
/// group as a big card, then everyone you split with — so with a few things
/// pending the groups fell off the screen. Groups and people have tabs of
/// their own now. This one keeps the number, folds what is waiting into one
/// stack, and shows the last few things that happened anywhere.
class HomeTabPage extends StatelessWidget {
  const HomeTabPage({super.key, this.bottomInset = 0, required this.onStart});

  /// Room under the content for the bar.
  final double bottomInset;

  /// Starts a group, from the empty screen's chips.
  final Future<void> Function({String? name}) onStart;

  @override
  Widget build(BuildContext context) {
    final store = context.store;
    // Everyone you split with, netted across every ledger: the number at the
    // top is theirs added up.
    final people = store.standings;
    final claims = store.confirmationsForYou;
    final waiting = store.claimsAwaitingOthers;
    final due = store.dueRecurring;
    final netted = store.unseenNetOffs;
    final billsAsked = store.receiptRequestsForYou;
    final empty = store.groups.isEmpty;

    void open(Group g) => Navigator.of(context).push(
      CupertinoPageRoute(builder: (_) => GroupScreen(groupId: g.id)),
    );

    // Exactly one focal object per screen: the card on top of the stack.
    var focalTaken = false;
    Lift claim() {
      if (focalTaken) return Lift.card;
      focalTaken = true;
      return Lift.focal;
    }

    final cards = <Widget>[
      for (final news in netted) _NettedCard(key: ValueKey('netted-${news.ids.first}'), news: news),
      for (final (group, settlement) in claims)
        _ClaimCard(key: ValueKey(settlement.id), group: group, settlement: settlement, lift: claim()),
      for (final (group, settlement) in waiting)
        _WaitingClaimCard(
          key: ValueKey('waiting-${settlement.id}'),
          group: group,
          settlement: settlement,
          lift: claim(),
        ),
      for (final (group, expense) in billsAsked)
        _BillAskedCard(key: ValueKey('bill-${expense.id}'), group: group, expense: expense, lift: claim()),
      for (final (group, schedule) in due)
        _DueCard(key: ValueKey(schedule.id), group: group, schedule: schedule, lift: claim()),
    ];

    // The last few things that happened anywhere, newest first.
    final recent = [
      for (final g in store.groups)
        for (final item in <Object>[...g.expenses, ...g.settlements]) (g, item),
    ]..sort((a, b) => newestFirst(ledgerMoment(a.$2), ledgerMoment(b.$2)));

    const requests = FriendRequestsCard();

    return MullPage(
      // Its own scroll position either side of empty: the last group going
      // left the empty screen opened part-way down, under the header.
      key: ValueKey(empty),
      bottomInset: bottomInset,
      glow: const GlowSpec(size: 450, top: -170, right: -150),
      onRefresh: store.pullNow,
      children: empty
          ? [
              // A new user's first screen is this one, and the request is how
              // they get into the group they were added to.
              EmptyHome(onStart: onStart, requests: requests),
            ]
          : [
              _Headline(people: people),
              _WhoOwes(
                people: people,
                onOpenLedger: (id) {
                  final g = store.groupById(id);
                  if (g != null) open(g);
                },
              ),
              requests,
              if (cards.isNotEmpty) ...[
                Eyebrow(
                  'Needs you · ${cards.length}',
                  size: 10.5,
                  tracking: .18,
                  padding: const EdgeInsets.fromLTRB(Gutter.text, 34, Gutter.text, 14),
                ),
                NeedsYouStack(cards: cards),
              ],
              if (recent.isNotEmpty) ...[
                const Eyebrow(
                  'Recent',
                  size: 10.5,
                  tracking: .18,
                  padding: EdgeInsets.fromLTRB(Gutter.text, 36, Gutter.text, 14),
                ),
                Surface(
                  lift: Lift.card,
                  radius: 26,
                  margin: const EdgeInsets.symmetric(horizontal: Gutter.card),
                  padding: const EdgeInsets.fromLTRB(18, 4, 18, 4),
                  child: CardRows(
                    children: [
                      for (final (group, item) in recent.take(5))
                        _RecentRow(
                          key: ValueKey('recent-${switch (item) { Expense e => e.id, Settlement s => s.id, _ => '' }}'),
                          group: group,
                          item: item,
                          onOpen: () => open(group),
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
            ],
    );
  }
}

/// One thing that happened, in whichever group it happened in.
class _RecentRow extends StatelessWidget {
  const _RecentRow({super.key, required this.group, required this.item, required this.onOpen});

  final Group group;
  final Object item;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final store = context.store;
    // "You paid Ananya", "Sahil paid you": you are only capitalised first.
    String name(String id, {bool first = false}) => switch (group.memberById(id)) {
      final m? when m.isYou => first ? 'You' : 'you',
      final m? => store.shortName(m),
      null => 'Someone',
    };

    final (String title, String detail, int amount, String? under, VoidCallback onTap) = switch (item) {
      Expense e => (
        e.description,
        '${group.title} · ${e.payerId == group.you?.id ? 'you paid' : '${name(e.payerId)} paid'}',
        e.amount,
        switch (e.shares[group.you?.id] ?? 0) {
          0 => 'not yours',
          final share => 'your share ${inr(share)}',
        },
        () => showExpenseDetail(context, group, e),
      ),
      Settlement s => (
        s.offset
            ? '${name(s.fromId, first: true)} and ${name(s.toId)} netted off'
            : '${name(s.fromId, first: true)} paid ${name(s.toId)}',
        group.title,
        s.amount,
        null,
        onOpen,
      ),
      _ => ('', '', 0, null, onOpen),
    };

    return Pressable(
      onTap: onTap,
      scale: .99,
      semanticLabel: [title, detail, inr(amount), ?under].join(', '),
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 13),
          child: Row(
            children: [
              GroupBadge(group: group, size: 36, glyphSize: 17, quiet: true),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: ranade(15.5, color: c.ink), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(detail, style: MullType.caption(c.ink3, size: 11.5), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(inr(amount), style: MullType.listAmount(c.ink)),
                  if (under != null) ...[
                    const SizedBox(height: 3),
                    Text(under, style: MullType.caption(c.ink3, size: 11)),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "You owe, all in / ₹3,850", and then both halves of it.
///
/// The net on its own was half an answer. ₹3,850 reads as a small tidy debt
/// and can just as easily be ₹12,000 coming to you against ₹15,850 going out —
/// two facts you would act on completely differently. So when both directions
/// exist, both are said, and the line is tappable through to the names.
class _Headline extends StatelessWidget {
  const _Headline({required this.people});

  /// [MullStore.standings], worked out once by the home screen.
  final List<Standing> people;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final store = context.store;
    // What you owe and what you are owed are two numbers, never one. Netting
    // them said "It all cancels out" when one friend owed you ₹226 and you
    // owed a different friend ₹226 — neither of them is going to pay the other.
    // Netting within one person, across ledgers, is still right, and
    // [MullStore.standings] has already done it.
    final owed = MullStore.owedToYouIn(people);
    final owing = MullStore.youOweIn(people);
    final bothWays = owed > 0 && owing > 0;

    final caption = switch (null) {
      _ when owing > 0 => 'You owe, all in',
      _ when owed > 0 => "You're owed, all in",
      _ => 'All square',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HeroAmount(
          caption: caption,
          amount: owing > 0 ? owing : (owed > 0 ? owed : null),
          placeholder: 'Nobody owes\nanybody.',
        ),
        if (bothWays)
          Pressable(
            onTap: () => HomeShellScope.of(context).select(HomeTab.people),
            scale: .99,
            semanticLabel: 'Owed to you ${inr(owed)}, you owe ${inr(owing)}. Open who owes who.',
            child: ExcludeSemantics(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(Gutter.text, 14, Gutter.text, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'And ${inr(owed)} is owed to you · see who',
                        style: MullType.caption(c.ink3, size: 12.5),
                      ),
                    ),
                    MullIcon(MullGlyph.chevronRight, size: 13, color: c.ink3, strokeWidth: 1.8),
                  ],
                ),
              ),
            ),
          ),
        // Said quietly, and only once a push has actually failed. A change that
        // exists only on this phone looks exactly like one everybody can see,
        // and the first anyone knew of the difference was "my group vanished".
        if (store.syncTrouble && store.hasPendingChanges)
          Padding(
            padding: const EdgeInsets.fromLTRB(Gutter.text, 10, Gutter.text, 0),
            child: Text(
              LiveChannel.instance.connected.value
                  ? "Some changes haven't synced yet. Mull keeps trying."
                  : "Some changes haven't synced yet. They'll go up when you're back online.",
              style: MullType.caption(c.ink3, size: 12),
            ),
          ),
      ],
    );
  }
}

/// Who the number at the top is, person by person, with Pay or Nudge on each.
///
/// The headline said "You're owed ₹500" and the only way to find out by whom
/// was Groups, then the group, then its Overview. The number and who it is are
/// one answer, so they sit together.
class _WhoOwes extends StatelessWidget {
  const _WhoOwes({required this.people, required this.onOpenLedger});

  /// [MullStore.standings], worked out once by the home screen.
  final List<Standing> people;
  final void Function(String groupId) onOpenLedger;

  /// Past this many, the rest are on People.
  static const _shown = 4;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    // What you owe first, since that one is yours to do; the biggest first
    // within each.
    final open = [
      for (final s in people)
        if (!s.isSquare) s,
    ]..sort((a, b) => a.youOwe != b.youOwe ? (a.youOwe ? -1 : 1) : b.magnitude.compareTo(a.magnitude));
    if (open.isEmpty) return const SizedBox.shrink();
    final more = open.length - _shown;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Eyebrow(
          'Who owes who',
          size: 10.5,
          tracking: .18,
          padding: EdgeInsets.fromLTRB(Gutter.text, 34, Gutter.text, 14),
        ),
        Surface(
          lift: Lift.card,
          radius: 26,
          margin: const EdgeInsets.symmetric(horizontal: Gutter.card),
          padding: const EdgeInsets.fromLTRB(18, 4, 14, 4),
          child: CardRows(
            children: [
              for (final s in open.take(_shown))
                PersonLine(
                  key: ValueKey('owes-${s.member.id}'),
                  standing: s,
                  sayDirection: true,
                  action: s.youOwe ? 'Pay' : 'Nudge',
                  onAction: () => s.youOwe ? settleWithPerson(context, s) : nudgePerson(context, s),
                  onOpenLedger: onOpenLedger,
                ),
            ],
          ),
        ),
        if (more > 0)
          Pressable(
            onTap: () => HomeShellScope.of(context).select(HomeTab.people),
            scale: .99,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Gutter.text, 14, Gutter.text, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '$more more on People',
                      style: MullType.caption(c.ink3, size: 12.5),
                    ),
                  ),
                  MullIcon(MullGlyph.chevronRight, size: 13, color: c.ink3, strokeWidth: 1.8),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Opens the both-directions list, and follows it into a ledger if one was
/// tapped down there.
/// Mull netted off debts with someone across ledgers. Said once, until read.
///
/// Netting happens without asking, because it changes nobody's money: you
/// owed ₹500 on one side and were owed ₹500 on the other, and that is nothing
/// owed. But the groups' numbers move, so it is announced rather than silent.
class _NettedCard extends StatelessWidget {
  const _NettedCard({super.key, required this.news});

  final NetOffNews news;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final store = context.store;
    final who = store.shortName(news.member);
    final where = switch (news.groups.length) {
      0 || 1 => 'across your ledgers',
      2 => 'between ${news.groups[0].title} and ${news.groups[1].title}',
      final n => 'across $n ledgers',
    };

    return Surface(
      lift: Lift.card,
      radius: 28,
      margin: const EdgeInsets.symmetric(horizontal: Gutter.card),
      padding: const EdgeInsets.fromLTRB(22, 18, 16, 18),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${inr(news.amount)} netted off with $who',
                  style: ranade(16, height: 1.35, color: c.ink),
                  maxLines: 2,
                ),
                const SizedBox(height: 4),
                Text(
                  'You owed each other $where, so it cancelled. Nobody pays it.',
                  style: MullType.caption(c.ink3, size: 11.5),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          InlineButton(
            'OK',
            height: 48,
            onTap: () => store.acknowledgeNetOff(news),
          ),
        ],
      ),
    );
  }
}

/// Somebody wants to see the bill for an expense you paid.
class _BillAskedCard extends StatelessWidget {
  const _BillAskedCard({
    super.key,
    required this.group,
    required this.expense,
    required this.lift,
  });

  final Group group;
  final Expense expense;
  final Lift lift;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final store = context.store;
    final asker = group.memberById(expense.receiptRequestedBy!);

    return Surface(
      lift: lift,
      radius: 28,
      margin: const EdgeInsets.symmetric(horizontal: Gutter.card),
      padding: const EdgeInsets.fromLTRB(22, 18, 16, 18),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${asker == null ? 'Someone' : store.shortName(asker)} wants the bill for ${expense.description}',
                  style: ranade(16, height: 1.35, color: c.ink),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  '${inr(expense.amount)} · ${group.title}',
                  style: MullType.caption(c.ink3, size: 11.5),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          InlineButton(
            'Add it',
            height: 48,
            onTap: () => showExpenseDetail(context, group, expense),
          ),
        ],
      ),
    );
  }
}

/// A claim *you* made that the other person has not answered.
///
/// The other half of the confirm loop, and it used to be invisible: you said
/// you had paid, and if they never confirmed, nothing anywhere told you so.
/// The money had left your account and the debt was still on your balance,
/// with no way to find out why short of opening the group and reading the
/// settlements tab.
class _WaitingClaimCard extends StatelessWidget {
  const _WaitingClaimCard({
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
    final to = group.memberById(settlement.toId);
    if (to == null) return const SizedBox.shrink();
    final disputed = settlement.status == SettlementStatus.disputed;

    return Surface(
      lift: lift,
      radius: 28,
      margin: const EdgeInsets.symmetric(horizontal: Gutter.card),
      padding: const EdgeInsets.fromLTRB(22, 18, 16, 18),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  disputed
                      ? '${store.shortName(to)} has not seen your ${inr(settlement.amount)}'
                      : '${store.shortName(to)} has not confirmed your ${inr(settlement.amount)}',
                  style: ranade(16, height: 1.35, color: c.ink),
                  maxLines: 2,
                ),
                const SizedBox(height: 4),
                Text(
                  '${group.title} · claimed ${daysAgo(settlement.date, store.now())}',
                  style: MullType.caption(c.ink3, size: 11.5),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          InlineButton(
            'Open it',
            height: 48,
            onTap: () => showOwnClaim(context, group, settlement),
          ),
        ],
      ),
    );
  }
}

/// Somebody wants to split with you.
///
/// Being added to a group by email only puts it on your phone once you have
/// accepted the person who added you — that acceptance is the consent, and
/// without it anyone who knew your address could hand you a debt. Which makes
/// the request the first thing a new user needs to see, and it used to be a
/// count inside the profile sheet. "See" goes to People, where requests sit
/// at the top with Accept on the row.
class FriendRequestsCard extends StatefulWidget {
  const FriendRequestsCard({super.key});

  @override
  State<FriendRequestsCard> createState() => _FriendRequestsCardState();
}

class _FriendRequestsCardState extends State<FriendRequestsCard> with WidgetsBindingObserver {
  List<Friend> _waiting = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    FriendsService.changes.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    FriendsService.changes.removeListener(_load);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    final friends = await FriendsService.list();
    if (!mounted) return;
    setState(() => _waiting = [for (final f in friends) if (f.state == FriendState.incoming) f]);
  }

  @override
  Widget build(BuildContext context) {
    if (_waiting.isEmpty) return const SizedBox.shrink();
    final c = context.c;
    final who = _waiting.length == 1 ? _waiting.single.label.split(' ').first : '${_waiting.length} people';

    return Surface(
      lift: Lift.card,
      radius: 28,
      margin: const EdgeInsets.fromLTRB(Gutter.card, 10, Gutter.card, 0),
      padding: const EdgeInsets.fromLTRB(22, 18, 16, 18),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$who ${_waiting.length == 1 ? 'wants' : 'want'} to split with you',
                  style: ranade(16, height: 1.35, color: c.ink),
                  maxLines: 2,
                ),
                const SizedBox(height: 4),
                Text(
                  'Accept to see the groups you share',
                  style: MullType.caption(c.ink3, size: 11.5),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          InlineButton(
            'See',
            height: 48,
            onTap: () => HomeShellScope.maybeOf(context)?.select(HomeTab.people),
          ),
        ],
      ),
    );
  }
}

/// Three beats: what Mull records, who confirms it, and where the money goes.
///
/// Reachable from the You tab. The claim
/// and confirm loop is the one thing about Mull that is not obvious from
/// looking at it, and an app that never explains it gets used as a calculator.
Future<void> showHowItWorks(BuildContext context) => showMullSheet(
  context,
  height: 720,
  builder: (sheet) {
    final c = sheet.c;
    Widget beat(String number, String title, String body) => Padding(
      padding: const EdgeInsets.only(bottom: 26),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 34,
            child: Text(number, style: excon(20, color: c.ink3)),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: MullType.cardTitle(c.ink)),
                const SizedBox(height: 6),
                Text(body, style: MullType.body(c.ink3)),
              ],
            ),
          ),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SheetHeader('How it works'),
        Expanded(
          child: ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(Gutter.text, 14, Gutter.text, 24),
            children: [
              Text('Three things, and that is all of it.', style: MullType.statement(c.ink, size: 30)),
              const SizedBox(height: 28),
              beat(
                '01',
                'Add what people pay',
                'Whoever paid, and what it was for. Split it evenly or set exact '
                    'amounts. The balance updates as you go.',
              ),
              beat(
                '02',
                'Mull nets it off, person by person',
                'You see one number for each person, across every group you '
                    'share. Owing Ananya on the trip while she owes you on the '
                    'flat cancels out on its own.',
              ),
              beat(
                '03',
                'Pay, then say it went through',
                'Money moves over UPI between you, never through Mull. The payer '
                    'says they sent it and the person owed confirms it arrived, '
                    'so a balance only changes when both sides agree.',
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Gutter.card, 6, Gutter.card, 26),
          child: PillButton('Got it', onTap: () => Navigator.of(sheet).pop()),
        ),
      ],
    );
  },
);

// ---------------------------------------------------------------------- cards

/// Someone says they have paid you. Only you can say whether it landed, so it
/// sits above everything else until you answer.
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
      margin: const EdgeInsets.symmetric(horizontal: Gutter.card),
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

/// A standing expense whose turn has come round.
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
    final yourShare = schedule.shares[group.you?.id] ?? 0;

    return Surface(
      lift: lift,
      radius: 28,
      margin: const EdgeInsets.symmetric(horizontal: Gutter.card),
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
                  [
                    group.title,
                    inr(schedule.amount),
                    if (yourShare > 0) 'your share ${inr(yourShare)}',
                  ].join(' · '),
                  style: MullType.caption(c.ink3, size: 11.5),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
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

