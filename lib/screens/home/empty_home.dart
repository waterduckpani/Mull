import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';

import '../../data/remote/friends_service.dart';
import '../../data/store.dart';
import '../../ui/group_icons.dart';
import '../../ui/icons.dart';
import '../../ui/page.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets.dart';
import '../friends_sheet.dart';

/// Home before your first group.
///
/// It used to say what Mull is ("Who paid. Who owes. Sorted.") over a
/// paragraph, which read like every app's welcome screen. Someone who has
/// just signed up already knows what they came to split, so this asks them,
/// and every answer is one tap. Above the question are your people: Invite
/// and Add friend look like the circles at the top of Instagram, not a row
/// in a settings list, because Mull does nothing until the people you split
/// with are on it.
class EmptyHome extends StatelessWidget {
  const EmptyHome({super.key, required this.onStart, required this.requests, this.onOpenLedger});

  /// Starts a group, named when a tile was tapped.
  final Future<void> Function({String? name}) onStart;

  /// The "wants to split with you" card, under the people it is about.
  final Widget requests;

  final void Function(String groupId)? onOpenLedger;

  /// What people actually split, in the order they split it.
  static const starters = ['Flat', 'Trip', 'Dinner', 'Night out', 'Office'];

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final name = context.store.profile.name.trim().split(' ').first;

    final tiles = <Widget>[
      for (final starter in starters)
        _StartTile(
          label: starter,
          icon: groupGlyph(suggestGroupIcon(starter)),
          onTap: () => onStart(name: starter),
        ),
      _StartTile(label: 'Your own', onTap: onStart),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Rise(step: 0, child: PeopleRow(onOpenLedger: onOpenLedger)),
        requests,
        _Rise(
          step: 1,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Gutter.text, 34, Gutter.text, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name.isEmpty ? 'Welcome to Mull' : 'Hi $name', style: MullType.caption(c.ink3)),
                const SizedBox(height: 12),
                Text('What are we\nsplitting first?', style: MullType.statement(c.ink, size: 40)),
              ],
            ),
          ),
        ),
        _Rise(
          step: 2,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Gutter.card, 26, Gutter.card, 0),
            child: Column(
              children: [
                for (var i = 0; i < tiles.length; i += 2) ...[
                  if (i > 0) const SizedBox(height: 10),
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: tiles[i]),
                        const SizedBox(width: 10),
                        Expanded(child: tiles[i + 1]),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        _Rise(
          step: 3,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Gutter.text, 18, Gutter.text, 0),
            child: Text(
              "You add who's in next. People not on Mull yet can still be in it.",
              style: MullType.caption(c.ink3, size: 12.5),
            ),
          ),
        ),
      ],
    );
  }
}

/// One answer to "What are we splitting first?". Starts a group with that
/// name and the icon it will get; "Your own" starts a blank one.
class _StartTile extends StatelessWidget {
  const _StartTile({required this.label, required this.onTap, this.icon});

  final String label;
  final IconData? icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final own = icon == null;
    const radius = 22.0;

    return Pressable(
      onTap: onTap,
      scale: .97,
      semanticLabel: own ? 'Start a group of your own' : 'Start a group: $label',
      child: ExcludeSemantics(
        child: CustomPaint(
          foregroundPainter: own ? _Dashed(color: c.inputLine, radius: radius) : null,
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 15, 16, 15),
            decoration: own ? null : surfaceOf(c, Lift.card, radius: BorderRadius.circular(radius)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                own
                    ? MullIcon(MullGlyph.plus, size: 25, color: c.ink2, strokeWidth: 1.6)
                    : Icon(icon, size: 25, color: c.ink),
                const SizedBox(height: 18),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: MullType.cardTitle(own ? c.ink2 : c.ink, size: 16),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The circles across the top: Invite, Add friend, then your people, then
/// empty seats waiting for them.
///
/// Someone who has asked to split with you wears a ring, the way an unseen
/// story does. Someone you have asked and who has not answered is shown
/// faded. The seats are there so that two buttons on their own do not look
/// like the whole of it; tapping one adds a friend.
class PeopleRow extends StatefulWidget {
  const PeopleRow({super.key, this.onOpenLedger});

  final void Function(String groupId)? onOpenLedger;

  /// Circles shown before the row runs off the edge, counting the two
  /// buttons: enough that the last one is cut, which says it scrolls.
  static const seats = 6;

  @override
  State<PeopleRow> createState() => _PeopleRowState();
}

class _PeopleRowState extends State<PeopleRow> with WidgetsBindingObserver {
  List<Friend> _people = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from WhatsApp after inviting someone, who may have joined since.
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    final all = await FriendsService.list();
    if (!mounted) return;
    int rank(Friend f) => switch (f.state) {
      FriendState.incoming => 0,
      FriendState.friends => 1,
      FriendState.outgoing => 2,
    };
    setState(() => _people = [...all]..sort((a, b) => rank(a).compareTo(rank(b))));
  }

  Future<void> _add() async {
    final sent = await showAddFriendSheet(context);
    if (sent == true) await _load();
  }

  Future<void> _open() async {
    await showFriendsSheet(context, onOpenLedger: widget.onOpenLedger);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final empty = (PeopleRow.seats - 2 - _people.length).clamp(0, PeopleRow.seats);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(Gutter.card, 18, Gutter.card, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Circle(
            label: 'Invite',
            semanticLabel: 'Invite someone to Mull',
            solid: true,
            onTap: () => inviteToMull(context),
            child: const _Glyph(MullGlyph.invite, solid: true),
          ),
          _Circle(
            label: 'Add friend',
            semanticLabel: 'Add a friend',
            onTap: _add,
            child: const _Glyph(MullGlyph.addPerson),
          ),
          for (final person in _people)
            _Circle(
              label: person.label.split(' ').first,
              semanticLabel: switch (person.state) {
                FriendState.incoming => '${person.label} wants to split with you',
                FriendState.outgoing => '${person.label}, not accepted yet',
                FriendState.friends => person.label,
              },
              ring: person.state == FriendState.incoming,
              faded: person.state == FriendState.outgoing,
              onTap: _open,
              child: Builder(
                builder: (context) => Text(person.initials, style: MullType.cardTitle(context.c.ink, size: 17)),
              ),
            ),
          for (var i = 0; i < empty; i++)
            _Circle(label: '', semanticLabel: 'Add a friend', seat: true, onTap: _add, child: const SizedBox.shrink()),
        ],
      ),
    );
  }
}

class _Glyph extends StatelessWidget {
  const _Glyph(this.glyph, {this.solid = false});

  final MullGlyph glyph;
  final bool solid;

  @override
  Widget build(BuildContext context) =>
      MullIcon(glyph, size: 23, color: solid ? context.c.pillInk : context.c.ink, strokeWidth: 1.7);
}

class _Circle extends StatelessWidget {
  const _Circle({
    required this.label,
    required this.semanticLabel,
    required this.onTap,
    required this.child,
    this.solid = false,
    this.ring = false,
    this.faded = false,
    this.seat = false,
  });

  final String label;
  final String semanticLabel;
  final VoidCallback onTap;
  final Widget child;

  /// The one bright circle: Invite.
  final bool solid;

  /// They asked to split with you and you have not answered.
  final bool ring;

  /// You asked them and they have not answered.
  final bool faded;

  /// An empty seat, drawn as a dashed outline.
  final bool seat;

  static const size = 62.0;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    // Ring, gap, face: with a ring the face is smaller, so every circle in
    // the row is the same size from the outside.
    const ringWidth = 2.0, gap = 3.0;
    final face = ring ? size - 2 * (ringWidth + gap) : size;
    Widget disc = Container(
      width: face,
      height: face,
      decoration: seat ? null : BoxDecoration(shape: BoxShape.circle, color: solid ? c.pill : c.quiet),
      alignment: Alignment.center,
      child: child,
    );
    if (seat) {
      disc = CustomPaint(foregroundPainter: _Dashed(color: c.inputLine, radius: size / 2), child: disc);
    }
    if (ring) {
      disc = Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: c.ink, width: ringWidth),
        ),
        child: disc,
      );
    }

    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Pressable(
        onTap: onTap,
        scale: .94,
        semanticLabel: semanticLabel,
        child: ExcludeSemantics(
          child: Opacity(
            opacity: faded ? .55 : 1,
            child: SizedBox(
              width: 66,
              child: Column(
                children: [
                  disc,
                  const SizedBox(height: 7),
                  MediaQuery.withClampedTextScaling(
                    maxScaleFactor: 1.2,
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: MullType.caption(c.ink2, size: 11.5).copyWith(height: 1.2),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A dashed outline round whatever it is painted over: an empty seat, the
/// "Your own" tile. Something you could fill, rather than something there.
class _Dashed extends CustomPainter {
  const _Dashed({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    const width = 1.3;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width;
    final outline = Path()
      ..addRRect(RRect.fromRectAndRadius((Offset.zero & size).deflate(width / 2), Radius.circular(radius)));
    for (final PathMetric metric in outline.computeMetrics()) {
      // Whole dashes all the way round, so no short one where the ends meet.
      final count = (metric.length / 9).round();
      final step = metric.length / count;
      for (var i = 0; i < count; i++) {
        canvas.drawPath(metric.extractPath(i * step, i * step + step * .55), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_Dashed old) => old.color != color || old.radius != radius;
}

/// Fades and lifts its child into place, a beat after the one above it.
///
/// Only used on screens that would otherwise arrive all at once with nothing
/// on them. A list of real groups does not need choreography.
class _Rise extends StatefulWidget {
  const _Rise({required this.step, required this.child});

  final int step;
  final Widget child;

  @override
  State<_Rise> createState() => _RiseState();
}

class _RiseState extends State<_Rise> {
  bool _in = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: 90 + widget.step * 110), () {
      if (mounted) setState(() => _in = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final d = motion(context, const Duration(milliseconds: 520));
    return AnimatedSlide(
      offset: _in ? Offset.zero : const Offset(0, .06),
      duration: d,
      curve: Curves.easeOutCubic,
      child: AnimatedOpacity(opacity: _in ? 1 : 0, duration: d, child: widget.child),
    );
  }
}
