import 'package:flutter/material.dart';

import '../../ui/page.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets.dart';

/// Everything waiting on an answer from you, as one stack.
///
/// These used to be cards one under another — a claim, a due rent, a bill
/// someone asked for, a net-off — and with a few of them the groups were
/// pushed off the screen. Now the first one shows with the rest stacked
/// behind it, and tapping the stack lays them all out. The first card's own
/// buttons still work while it is stacked.
class NeedsYouStack extends StatefulWidget {
  const NeedsYouStack({super.key, required this.cards});

  final List<Widget> cards;

  @override
  State<NeedsYouStack> createState() => _NeedsYouStackState();
}

class _NeedsYouStackState extends State<NeedsYouStack> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final cards = widget.cards;
    if (cards.isEmpty) return const SizedBox.shrink();

    if (_open || cards.length == 1) {
      // The cards bring their own side margins.
      return Stacked(
        gap: 8,
        children: [
          ...cards,
          if (cards.length > 1)
            Center(
              child: Pressable(
                onTap: () => setState(() => _open = false),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                  child: Text('Show less', style: MullType.caption(c.ink3, size: 12.5)),
                ),
              ),
            ),
        ],
      );
    }

    final rest = cards.length - 1;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _open = true),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              // The cards behind, as the edge of a pile.
              Positioned(
                left: Gutter.card + 14,
                right: Gutter.card + 14,
                bottom: -10,
                height: 40,
                child: DecoratedBox(
                  decoration: surfaceOf(c, Lift.flat, radius: BorderRadius.circular(22)),
                ),
              ),
              cards.first,
            ],
          ),
          const SizedBox(height: 18),
          Semantics(
            button: true,
            label: 'Show $rest more',
            child: ExcludeSemantics(
              child: Text(
                rest == 1 ? '1 more' : '$rest more',
                textAlign: TextAlign.center,
                style: MullType.caption(c.ink3, size: 12.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
