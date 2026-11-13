import 'package:flutter/cupertino.dart';

import '../../core/dates.dart';
import '../../core/money.dart';
import '../../data/models.dart';
import '../../data/store.dart';
import '../../ui/icons.dart';
import '../../ui/page.dart';
import '../../ui/sheet.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets.dart';
import '../groups/group_bar.dart';
import '../groups/group_screen.dart';
import '../groups/group_sheets.dart';
import '../groups/icon_picker.dart';

/// The Groups tab: every group, sized to how many there are.
///
/// From three groups up, each is a line you can scan, in the order that
/// matters: what you owe, then what you are owed, then the settled ones under
/// their own heading. With one or two, lines left most of the page empty, so
/// each group gets a card instead with who is in it, where you stand, the
/// last thing added and the two things you came to do. With none, the page
/// shows what a group looks like rather than a sentence about one.
class GroupsTabPage extends StatelessWidget {
  const GroupsTabPage({super.key, this.bottomInset = 0, required this.onStart});

  /// Room under the content for the bar.
  final double bottomInset;

  /// Starts a group.
  final Future<void> Function({String? name}) onStart;

  /// Up to this many groups, each gets a card rather than a line.
  static const roomyUpTo = 2;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final store = context.store;
    final groups = store.namedGroups;
    bool settled(Group g) => g.youOweHere == 0 && g.owedToYouHere == 0;
    final open = groups.where((g) => !settled(g)).toList();
    final done = groups.where(settled).toList();
    final roomy = groups.length <= roomyUpTo;

    void openGroup(Group g, {GroupTab tab = GroupTab.overview}) => Navigator.of(context).push(
      CupertinoPageRoute(builder: (_) => GroupScreen(groupId: g.id, initialTab: tab)),
    );

    Widget rows(List<Group> list) => Stacked(
      gap: roomy ? 12 : 8,
      padding: const EdgeInsets.symmetric(horizontal: Gutter.card),
      children: [
        for (final g in list)
          roomy
              ? _GroupCard(key: ValueKey(g.id), group: g, onOpen: (tab) => openGroup(g, tab: tab))
              : _LedgerRow(key: ValueKey(g.id), group: g, onTap: () => openGroup(g)),
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
        if (groups.isEmpty) _NoGroups(onStart: () => onStart()),
        if (open.isNotEmpty) rows(open),
        if (done.isNotEmpty) ...[
          if (!roomy || open.isNotEmpty)
            const Eyebrow(
              'Settled',
              size: 10.5,
              tracking: .18,
              padding: EdgeInsets.fromLTRB(Gutter.text, 34, Gutter.text, 14),
            ),
          rows(done),
        ],
        if (groups.isNotEmpty && roomy) _StartAnother(onTap: () => onStart()),
        const SizedBox(height: 12),
      ],
    );
  }
}

/// A group with room to breathe: for when there are only one or two.
class _GroupCard extends StatelessWidget {
  const _GroupCard({super.key, required this.group, required this.onOpen});

  final Group group;
  final void Function(GroupTab tab) onOpen;

  @override
  Widget build(BuildContext context) {
    final store = context.store;
    final owing = group.youOweHere;
    final owed = group.owedToYouHere;
    final others = group.seated.where((m) => !m.isYou).toList();

    final (label, amount) = switch (null) {
      _ when owing > 0 && owed > 0 => ('get back ${inr(owed)} · you owe', owing),
      _ when owing > 0 => ('you owe', owing),
      _ when owed > 0 => ('you get back', owed),
      _ => ('settled up', null),
    };

    // "You paid Ananya", "Sahil paid you": you are only capitalised first.
    String name(String id, {bool first = false}) => switch (group.memberById(id)) {
      final m? when m.isYou => first ? 'You' : 'you',
      final m? => store.shortName(m),
      null => 'Someone',
    };
    final items = <Object>[...group.expenses, ...group.settlements]
      ..sort((a, b) => newestFirst(ledgerMoment(a), ledgerMoment(b)));
    final latest = items.firstOrNull;
    final when = latest == null ? '' : daysAgo(ledgerMoment(latest).$1, DateTime.now());
    final last = switch (latest) {
      Expense e => '${e.description} · ${inr(e.amount)} · $when',
      Settlement s when s.offset => '${name(s.fromId, first: true)} and ${name(s.toId)} netted off · $when',
      Settlement s => '${name(s.fromId, first: true)} paid ${name(s.toId)} ${inr(s.amount)} · $when',
      _ => null,
    };

    return _CardFace(
      badge: GroupBadge(group: group, size: 46, glyphSize: 22, quiet: true),
      title: group.title,
      roster: _roster(store, others),
      label: label,
      amount: amount,
      faces: [for (final m in others) _initials(m.name)],
      last: last,
      flat: amount == null,
      semanticLabel: amount == null ? '${group.title}, settled up' : '${group.title}, $label ${inr(amount)}',
      onTap: () => onOpen(GroupTab.overview),
      onLongPress: () => showLedgerActions(context, group),
      actions: [
        if (others.isEmpty)
          // An expense split with nobody moves no money; the group's + says
          // the same thing.
          InlineButton("Add who's in", height: 44, expand: true, onTap: () => onOpen(GroupTab.people))
        else
          InlineButton('Add expense', height: 44, expand: true, onTap: () => showAddExpense(context, group)),
        if (!group.youAreSquare)
          InlineButton('Settle up', height: 44, expand: true, filled: false, onTap: () => onOpen(GroupTab.overview)),
      ],
    );
  }
}

String _initials(String name) =>
    name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).take(2).map((w) => w[0]).join().toUpperCase();

String _roster(MullStore store, List<Member> others) => others.isEmpty
    ? 'Nobody else in here yet'
    : others.length <= 3
    ? 'You, ${others.map(store.shortName).join(', ')}'
    : 'You, ${others.take(2).map(store.shortName).join(', ')} and ${others.length - 2} more';

/// What a group card shows, from whatever it is given: a real group, or the
/// example on an empty Groups tab.
class _CardFace extends StatelessWidget {
  const _CardFace({
    required this.badge,
    required this.title,
    required this.roster,
    required this.label,
    required this.amount,
    required this.faces,
    this.last,
    this.flat = false,
    this.semanticLabel,
    this.onTap,
    this.onLongPress,
    this.actions = const [],
  });

  final Widget badge;
  final String title;
  final String roster;
  final String label;
  final int? amount;

  /// Initials of everyone else in it.
  final List<String> faces;

  /// The latest thing added, already worded.
  final String? last;

  /// Settled: sits flatter, the way a settled row does.
  final bool flat;

  final String? semanticLabel;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    const shown = 4;

    final body = Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      decoration: surfaceOf(c, flat ? Lift.flat : Lift.card, radius: BorderRadius.circular(28)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              badge,
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: MullType.cardTitle(c.ink, size: 19), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 3),
                    Text(roster, style: MullType.caption(c.ink3, size: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: MullType.caption(c.ink3, size: 12)),
                    const SizedBox(height: 4),
                    amount == null
                        ? Text('All square', style: MullType.cardAmount(c.ink2, size: 30))
                        : AnimatedAmount(amount!, style: MullType.cardAmount(c.ink, size: 34)),
                  ],
                ),
              ),
              for (final (i, face) in faces.take(shown).indexed)
                Padding(
                  padding: EdgeInsets.only(left: i == 0 ? 0 : 4),
                  child: _Face(face),
                ),
              if (faces.length > shown)
                Padding(padding: const EdgeInsets.only(left: 4), child: _Face('+${faces.length - shown}')),
            ],
          ),
          if (last != null) ...[
            const SizedBox(height: 18),
            Container(height: 1, color: c.line),
            const SizedBox(height: 14),
            Row(
              children: [
                Text('Latest', style: MullType.caption(c.ink2, size: 12)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(last!, style: MullType.caption(c.ink3, size: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ],
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                for (final (i, action) in actions.indexed) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(child: action),
                ],
              ],
            ),
          ],
        ],
      ),
    );

    if (onTap == null) return ExcludeSemantics(child: body);
    return Semantics(
      container: true,
      label: semanticLabel,
      child: Pressable(onTap: onTap, onLongPress: onLongPress, scale: .99, child: body),
    );
  }
}

class _Face extends StatelessWidget {
  const _Face(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(shape: BoxShape.circle, color: c.quiet),
      child: Text(text, style: MullType.caption(c.ink2, size: 10.5).copyWith(height: 1)),
    );
  }
}

/// Groups with nothing in it yet: two example cards, fanned, and what a group
/// is for. Home already asks what you are splitting first; this tab shows
/// what you will get.
class _NoGroups extends StatelessWidget {
  const _NoGroups({required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final c = context.c;

    // Cards are translucent in dark mode, so each example sits on the
    // screen colour: otherwise the one behind shows through the one in front.
    Widget solid(Widget child) => DecoratedBox(
      decoration: BoxDecoration(color: c.screen, borderRadius: BorderRadius.circular(28)),
      child: child,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          label: 'An example group: Goa trip, with Sahil, Ananya and Kabir. You get back ₹2,400.',
          child: ExcludeSemantics(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Gutter.card + 6, 8, Gutter.card + 6, 0),
              child: Stack(
                children: [
                  // Another group behind, peeking out above and to the right:
                  // a stack, so it reads as one of several.
                  Positioned.fill(
                    child: Transform.translate(
                      offset: const Offset(12, -16),
                      child: Transform.rotate(
                        angle: .05,
                        child: solid(
                          DecoratedBox(decoration: surfaceOf(c, Lift.flat, radius: BorderRadius.circular(28))),
                        ),
                      ),
                    ),
                  ),
                  Transform.rotate(
                    angle: -.025,
                    child: solid(
                      _CardFace(
                        badge: IconWell(iconKey: 'beach', size: 46, glyphSize: 22, quiet: true, fallback: MullGlyph.groups),
                        title: 'Goa trip',
                        roster: 'You, Sahil, Ananya, Kabir',
                        label: 'you get back',
                        amount: 2400,
                        faces: const ['SM', 'AR', 'KA'],
                        last: 'Villa · ₹18,000 · yesterday',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Gutter.text, 36, Gutter.text, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('One group for\neach thing you share.', style: MullType.statement(c.ink, size: 30)),
              const SizedBox(height: 12),
              Text(
                'The flat, a trip, a standing Friday dinner. Everyone in it sees the '
                'same list of who paid, and Mull works out who pays whom.',
                style: MullType.body(c.ink3),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Gutter.card, 24, Gutter.card, 0),
          child: PillButton('Start a group', onTap: onStart),
        ),
      ],
    );
  }
}

/// Under one or two group cards: the next one, without a second big button.
class _StartAnother extends StatelessWidget {
  const _StartAnother({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gutter.card, 12, Gutter.card, 0),
      child: Pressable(
        onTap: onTap,
        scale: .99,
        semanticLabel: 'Start another group',
        child: ExcludeSemantics(
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 18, 18, 18),
            decoration: surfaceOf(c, Lift.flat, radius: BorderRadius.circular(24)),
            child: Row(
              children: [
                MullIcon(MullGlyph.plus, size: 20, color: c.ink2, strokeWidth: 1.7),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Start another group', style: MullType.cardTitle(c.ink2, size: 16)),
                      const SizedBox(height: 2),
                      Text('Keep each trip, flat or dinner to itself', style: MullType.caption(c.ink3, size: 11.5)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
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
