import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'icons.dart';
import 'sheet.dart';
import 'tokens.dart';
import 'widgets.dart';

/// One place in a tab bar: its name and its icon.
class TabItem {
  const TabItem(this.label, this.glyph);

  final String label;
  final MullGlyph glyph;
}

/// The floating bar under the home screen and every group, with the + in the
/// middle.
///
/// It holds still. The + is where a thumb goes without looking, so every tab
/// keeps one fixed width and the open tab's name goes *under* its icon rather
/// than beside it: beside it, the open tab widened and pushed its neighbours,
/// and the + drifted with whichever tab you were on.
///
/// Holding the + is kept free for adding by voice.
class MullTabBar extends StatelessWidget {
  const MullTabBar({
    super.key,
    required this.items,
    required this.current,
    required this.onSelect,
    required this.onAdd,
    this.addEnabled = true,
    this.whyNot = 'Add someone first',
  }) : assert(items.length == 4, 'two tabs either side of the +');

  final List<TabItem> items;
  final int current;
  final ValueChanged<int> onSelect;
  final VoidCallback onAdd;

  /// False when there is nothing the + could do yet; tapping it then says
  /// [whyNot] instead of opening anything.
  final bool addEnabled;
  final String whyNot;

  static const double height = 60;

  @override
  Widget build(BuildContext context) {
    final c = context.c;

    Widget half(int from) => Expanded(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          for (var i = from; i < from + 2; i++)
            _Tab(
              item: items[i],
              index: i,
              count: items.length,
              open: i == current,
              onTap: () {
                if (i != current) onSelect(i);
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
            half(0),
            _Add(
              enabled: addEnabled,
              onTap: addEnabled ? onAdd : () => Toast.show(context, whyNot),
            ),
            half(2),
          ],
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({required this.item, required this.index, required this.count, required this.open, required this.onTap});

  final TabItem item;
  final int index;
  final int count;
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
        semanticLabel: '${item.label}, tab ${index + 1} of $count',
        child: ExcludeSemantics(
          child: AnimatedContainer(
            duration: duration,
            curve: Curves.easeOutCubic,
            // Wide enough for "Recurring" with room either side; at 58 its
            // name nearly touched the pill's edges.
            width: 68,
            height: 50,
            decoration: BoxDecoration(
              color: open ? c.quiet : c.quiet.withValues(alpha: 0),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                MullIcon(item.glyph, size: 21, color: open ? c.ink : c.ink3, strokeWidth: 1.7),
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
                              item.label,
                              maxLines: 1,
                              overflow: TextOverflow.fade,
                              softWrap: false,
                              style: ranade(10, height: 1, color: c.ink),
                            ),
                          ),
                        )
                      : const SizedBox(width: 68),
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
