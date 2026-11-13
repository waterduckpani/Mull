import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart';
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
/// It works like Instagram's. Icons only, the open tab's filled in, and a
/// highlight that moves: tap a tab and it springs across to it; press
/// anywhere on the bar and slide, and it follows your finger, filling in
/// whichever icon it is over, then opens that tab when you let go. The names
/// are off the screen but not out of the app: each tab still says its name to
/// a screen reader.
///
/// It holds still. The + is where a thumb goes without looking, so the tabs
/// sit in four fixed slots either side of it and nothing changes width.
///
/// Holding the + is kept free for adding by voice.
class MullTabBar extends StatefulWidget {
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
  State<MullTabBar> createState() => _MullTabBarState();
}

class _MullTabBarState extends State<MullTabBar> with TickerProviderStateMixin {
  static const _pillWidth = 64.0;
  static const _pillHeight = 48.0;
  static const _plusSize = 48.0;

  /// Lands on a tab with a little overshoot.
  static final _settle = SpringDescription.withDampingRatio(mass: 1, stiffness: 380, ratio: .74);

  /// How quickly the highlight closes on a sliding finger, per second: under
  /// it within a few frames, without jumping to it where the slide begins.
  static const _catchUp = 35.0;

  /// Where the highlight is, counted in tabs: 0 is the first tab's centre, 3
  /// the last's, and 1.5 is under the +. Counted in tabs rather than pixels so
  /// it keeps its place if the bar changes width.
  late final AnimationController _at = AnimationController.unbounded(vsync: this, value: widget.current.toDouble());

  /// How far the highlight has swelled under a finger, 0 to 1.
  late final AnimationController _press = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 140),
    reverseDuration: const Duration(milliseconds: 320),
  );

  /// The four tab centres across the bar, from its last layout.
  List<double> _centres = const [0, 1, 2, 3];

  /// The finger that has the highlight, if one does.
  int? _pointer;
  double _downX = 0;
  bool _sliding = false;

  /// Moves the highlight while a finger slides it. Its own ticker, because
  /// the first version restarted a spring on every touch update, and a spring
  /// that restarts every frame starts from rest every frame: under a moving
  /// finger the highlight sat still and only the icons changed.
  late final Ticker _slide = createTicker(_follow);
  Duration _lastTick = Duration.zero;

  /// Where the finger is, counted in tabs, and how fast the highlight was
  /// going when it let go, for the spring that lands it.
  double _finger = 0;
  double _speed = 0;

  /// The tab the highlight is on while a finger has it, or has just let go
  /// of it and the screen has not opened it yet. Null when it is on [current].
  int? _held;

  @override
  void didUpdateWidget(MullTabBar old) {
    super.didUpdateWidget(old);
    if (widget.current != old.current && _pointer == null) {
      _held = null;
      _glide(widget.current.toDouble());
    }
  }

  @override
  void dispose() {
    _slide.dispose();
    _at.dispose();
    _press.dispose();
    super.dispose();
  }

  bool get _still => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  void _glide(double to, {double? velocity}) {
    if (_still) {
      _at.value = to;
      return;
    }
    _at.animateWith(SpringSimulation(_settle, _at.value, to, velocity ?? _at.velocity));
  }

  void _follow(Duration elapsed) {
    final dt = (elapsed - _lastTick).inMicroseconds / Duration.microsecondsPerSecond;
    _lastTick = elapsed;
    if (dt <= 0) return;
    final from = _at.value;
    final to = from + (_finger - from) * (1 - math.exp(-dt * _catchUp));
    _at.value = to;
    _speed = (to - from) / dt;
    _hold(to.round());
  }

  /// Pixels across the bar for a position counted in tabs. Straight lines
  /// between tabs, carried on past either end so a spring can overshoot.
  double _px(double at) {
    final c = _centres;
    final i = at.floor().clamp(0, 2);
    return c[i] + (c[i + 1] - c[i]) * (at - i);
  }

  /// The position, counted in tabs, under a point on the bar. Never past the
  /// first or last tab.
  double _tabsAt(double x) {
    final c = _centres;
    if (x <= c[0]) return 0;
    if (x >= c[3]) return 3;
    final i = x < c[1]
        ? 0
        : x < c[2]
        ? 1
        : 2;
    return i + (x - c[i]) / (c[i + 1] - c[i]);
  }

  bool _onPlus(double x) => (x - (_centres[1] + _centres[2]) / 2).abs() < _plusSize / 2 + 4;

  void _hold(int i) {
    if (i == (_held ?? widget.current)) return;
    HapticFeedback.selectionClick();
    setState(() => _held = i);
  }

  void _down(PointerDownEvent e) {
    if (_pointer != null || _onPlus(e.localPosition.dx)) return;
    _pointer = e.pointer;
    _downX = e.localPosition.dx;
    _sliding = false;
    _press.forward();
    // Head for the tab under the finger straight away, before the finger
    // lifts: waiting for the tap to finish makes the bar feel slow.
    final i = _tabsAt(_downX).round();
    _hold(i);
    _glide(i.toDouble());
  }

  void _move(PointerMoveEvent e) {
    if (e.pointer != _pointer) return;
    final x = e.localPosition.dx;
    if (!_sliding && (x - _downX).abs() < kTouchSlop / 3) return;
    _sliding = true;
    _finger = _tabsAt(x);
    if (_still) {
      _at.value = _finger;
      _hold(_finger.round());
    } else if (!_slide.isActive) {
      _lastTick = Duration.zero;
      _speed = 0;
      _slide.start();
    }
  }

  void _up(PointerUpEvent e) {
    if (e.pointer != _pointer) return;
    _pointer = null;
    _slide.stop();
    _press.reverse();
    final i = _tabsAt(e.localPosition.dx).round();
    _hold(i);
    // Carry the slide's speed into the landing, so a flick lands with a
    // little overshoot instead of stopping dead and then springing.
    _glide(i.toDouble(), velocity: _sliding ? _speed : null);
    if (i != widget.current) widget.onSelect(i);
  }

  void _cancel(PointerCancelEvent e) {
    if (e.pointer != _pointer) return;
    _pointer = null;
    _slide.stop();
    _press.reverse();
    setState(() => _held = null);
    _glide(widget.current.toDouble());
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final lit = _held ?? widget.current;

    Widget slot(int i) => Expanded(
      child: Semantics(
        container: true,
        button: true,
        enabled: true,
        selected: i == widget.current,
        label: '${widget.items[i].label}, tab ${i + 1} of ${widget.items.length}',
        onTap: () {
          if (i == widget.current) return;
          HapticFeedback.selectionClick();
          widget.onSelect(i);
        },
        child: SizedBox(
          height: 50,
          child: Center(
            child: _TabIcon(glyph: widget.items[i].glyph, lit: i == lit),
          ),
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        height: MullTabBar.height,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(MullTabBar.height / 2),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [c.sheetTop, c.sheetBottom],
          ),
          boxShadow: [BoxShadow(color: c.shadowFocal, blurRadius: 50, offset: const Offset(0, 23))],
        ),
        child: LayoutBuilder(
          builder: (context, box) {
            final width = box.maxWidth;
            final tab = (width - _plusSize) / 4;
            _centres = [tab / 2, tab * 1.5, width - tab * 1.5, width - tab / 2];

            return Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: _down,
              onPointerMove: _move,
              onPointerUp: _up,
              onPointerCancel: _cancel,
              child: Stack(
                fit: StackFit.expand,
                clipBehavior: Clip.none,
                children: [
                  // The highlight, under the icons.
                  AnimatedBuilder(
                    animation: Listenable.merge([_at, _press]),
                    builder: (context, _) {
                      final swell = Curves.easeOutBack.transform(_press.value);
                      return Positioned(
                        left: _px(_at.value) - _pillWidth / 2,
                        top: (MullTabBar.height - _pillHeight) / 2,
                        width: _pillWidth,
                        height: _pillHeight,
                        child: Transform.scale(
                          scaleX: 1 + .14 * swell,
                          scaleY: 1 + .08 * swell,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Color.lerp(c.quiet, c.quiet.withValues(alpha: c.quiet.a * 2), _press.value),
                              borderRadius: BorderRadius.circular(_pillHeight / 2),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  Row(
                    children: [
                      slot(0),
                      slot(1),
                      _Add(
                        enabled: widget.addEnabled,
                        onTap: widget.addEnabled ? widget.onAdd : () => Toast.show(context, widget.whyNot),
                      ),
                      slot(2),
                      slot(3),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// A tab's icon: an outline, or filled in when the highlight is on it, with a
/// small bounce as it fills.
class _TabIcon extends StatefulWidget {
  const _TabIcon({required this.glyph, required this.lit});

  final MullGlyph glyph;
  final bool lit;

  @override
  State<_TabIcon> createState() => _TabIconState();
}

class _TabIconState extends State<_TabIcon> with SingleTickerProviderStateMixin {
  late final AnimationController _pop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
    value: 1,
  );

  @override
  void didUpdateWidget(_TabIcon old) {
    super.didUpdateWidget(old);
    if (widget.lit && !old.lit && !(MediaQuery.maybeDisableAnimationsOf(context) ?? false)) {
      _pop.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _pop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return AnimatedBuilder(
      animation: _pop,
      builder: (context, child) =>
          Transform.scale(scale: .84 + .16 * Curves.easeOutBack.transform(_pop.value), child: child),
      // ink2 rather than ink3 for the closed tabs: with no names, the icons
      // have to be easy to read on their own.
      child: MullIcon(
        widget.glyph,
        size: 23,
        color: widget.lit ? c.ink : c.ink2,
        strokeWidth: 1.7,
        filled: widget.lit,
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
          width: _MullTabBarState._plusSize,
          height: _MullTabBarState._plusSize,
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
