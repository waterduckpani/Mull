import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../ui/icons.dart';
import '../../ui/sheet.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets.dart';

/// The four places inside a group, in the order the bar shows them.
enum GroupTab {
  overview('Overview', MullGlyph.overview),
  ledger('Ledger', MullGlyph.ledger),
  recurring('Recurring', MullGlyph.repeat),
  people('People', MullGlyph.groups);

  const GroupTab(this.label, this.glyph);

  final String label;
  final MullGlyph glyph;
}

/// The bar under every tab of a group, with the + in the middle.
///
/// It holds still. The + is where a thumb goes without looking, so every tab
/// keeps one fixed width and the open tab's name goes *under* its icon rather
/// than beside it: beside it, the open tab widened and pushed its neighbours,
/// and the + drifted with whichever tab you were on.
///
/// Holding the + is kept free for adding by voice.
class GroupBar extends StatelessWidget {
  const GroupBar({
    super.key,
    required this.current,
    required this.onSelect,
    required this.onAdd,
    this.addEnabled = true,
  });

  final GroupTab current;
  final ValueChanged<GroupTab> onSelect;
  final VoidCallback onAdd;

  /// False while you are alone in the group: an expense split with nobody
  /// moves no money, so the + says so instead of opening the form.
  final bool addEnabled;

  static const double height = 60;

  @override
  Widget build(BuildContext context) {
    final c = context.c;

    Widget half(List<GroupTab> tabs) => Expanded(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          for (final tab in tabs)
            _Tab(
              tab: tab,
              open: tab == current,
              onTap: () {
                if (tab != current) onSelect(tab);
              },
            ),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(height / 2),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [c.sheetTop, c.sheetBottom],
          ),
          boxShadow: [BoxShadow(color: c.shadowFocal, blurRadius: 50, offset: const Offset(0, 23))],
        ),
        child: Row(
          children: [
            half([GroupTab.overview, GroupTab.ledger]),
            _Add(
              enabled: addEnabled,
              onTap: addEnabled ? onAdd : () => Toast.show(context, 'Add someone first'),
            ),
            half([GroupTab.recurring, GroupTab.people]),
          ],
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({required this.tab, required this.open, required this.onTap});

  final GroupTab tab;
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final duration = motion(context, const Duration(milliseconds: 220));
    return Semantics(
      selected: open,
      child: Pressable(
        onTap: onTap,
        scale: .94,
        haptic: !open,
        semanticLabel: '${tab.label}, tab ${tab.index + 1} of ${GroupTab.values.length}',
        child: ExcludeSemantics(
          child: AnimatedContainer(
            duration: duration,
            curve: Curves.easeOutCubic,
            width: 58,
            height: 50,
            decoration: BoxDecoration(
              color: open ? c.quiet : c.quiet.withValues(alpha: 0),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                MullIcon(tab.glyph, size: 21, color: open ? c.ink : c.ink3, strokeWidth: 1.7),
                // The name only for the tab you are on. Clamped, because the
                // tab cannot grow to fit it without moving the +.
                AnimatedSize(
                  duration: duration,
                  curve: Curves.easeOutCubic,
                  child: open
                      ? Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: MediaQuery.withClampedTextScaling(
                            maxScaleFactor: 1.15,
                            child: Text(
                              tab.label,
                              maxLines: 1,
                              overflow: TextOverflow.fade,
                              softWrap: false,
                              style: ranade(10, height: 1, color: c.ink),
                            ),
                          ),
                        )
                      : const SizedBox(width: 58),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Add extends StatelessWidget {
  const _Add({required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Pressable(
      onTap: () {
        if (enabled) HapticFeedback.lightImpact();
        onTap();
      },
      scale: .92,
      haptic: false,
      semanticLabel: 'Add an expense',
      child: ExcludeSemantics(
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: enabled ? c.pill : c.quiet,
            boxShadow: enabled ? [BoxShadow(color: c.shadowLow, blurRadius: 16, offset: const Offset(0, 6))] : null,
          ),
          child: Center(
            child: MullIcon(MullGlyph.plus, size: 22, color: enabled ? c.pillInk : c.ink3, strokeWidth: 2),
          ),
        ),
      ),
    );
  }
}
