import 'package:flutter/material.dart';

enum MullGlyph {
  groups,
  person,
  repeat,
  bell,
  pause,
  chevronRight,
  chevronLeft,
  chevronDown,
  close,
  check,
  more,
  plus,
  arrowUpRight,
  overview,
  ledger,
  home,
  grid,
}

/// The design's hand-drawn 24×24 stroke icons, painted directly (no SVG dependency).
///
/// [filled] is the solid version a tab bar shows for the open tab, the way
/// Instagram does: with no names under the icons, solid against outline is
/// what says which tab you are on. The tab glyphs (home, grid, groups,
/// person, overview, ledger, repeat) have one; the rest ignore it.
class MullIcon extends StatelessWidget {
  const MullIcon(this.glyph, {super.key, this.size = 20, this.color, this.strokeWidth, this.filled = false});

  final MullGlyph glyph;
  final double size;
  final Color? color;
  final double? strokeWidth;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final c = color ?? DefaultTextStyle.of(context).style.color ?? IconTheme.of(context).color!;
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _GlyphPainter(glyph, c, strokeWidth, filled)),
    );
  }
}

class _GlyphPainter extends CustomPainter {
  _GlyphPainter(this.glyph, this.color, this.strokeWidth, this.filled);

  final MullGlyph glyph;
  final Color color;
  final double? strokeWidth;
  final bool filled;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = strokeWidth ?? 1.6;
    final fill = Paint()..color = color;

    // An outline, or the same shape solid. Solid shapes get the stroke too,
    // so their corners stay as round as the outline's.
    void shape(Path path) {
      if (filled) canvas.drawPath(path, fill);
      canvas.drawPath(path, stroke);
    }

    // Paints [solid], then cuts [holes] out of it so the bar shows through:
    // a door in the house, the lines on the receipt.
    void cutOut(void Function() solid, void Function(Paint hole) holes) {
      canvas.saveLayer(const Rect.fromLTWH(-2, -2, 28, 28), Paint());
      solid();
      holes(
        Paint()
          ..blendMode = BlendMode.clear
          ..strokeCap = StrokeCap.round
          ..strokeWidth = stroke.strokeWidth,
      );
      canvas.restore();
    }

    Path circle(Offset centre, double radius) => Path()..addOval(Rect.fromCircle(center: centre, radius: radius));

    switch (glyph) {
      case MullGlyph.groups:
        shape(circle(const Offset(9.5, 9.6), 3.2));
        final front = Path()
          ..moveTo(4, 18.5)
          ..cubicTo(4, 15.7, 6.4, 13.9, 9.5, 13.9)
          ..cubicTo(12.6, 13.9, 15, 15.7, 15, 18.5);
        shape(filled ? (front..close()) : front);
        shape(circle(const Offset(17, 10.2), 2.3));
        // Shoulders for the one behind: a head on its own read as a dot.
        canvas.drawPath(
          Path()
            ..moveTo(17.3, 14.2)
            ..cubicTo(19.2, 14.4, 20.5, 15.9, 20.5, 18.2),
          stroke,
        );
      case MullGlyph.person:
        shape(circle(const Offset(12, 8.6), 3.6));
        final body = Path()
          ..moveTo(5, 19.5)
          ..cubicTo(5, 15.8, 8.1, 13.9, 12, 13.9)
          ..cubicTo(15.9, 13.9, 19, 15.8, 19, 19.5);
        shape(filled ? (body..close()) : body);
      case MullGlyph.repeat:
        // A loop with an arrowhead at each end — "this comes round again".
        // Nothing to fill in a loop, so the open tab's is drawn heavier.
        if (filled) stroke.strokeWidth += .8;
        canvas.drawPath(
          Path()
            ..moveTo(9.2, 16.4)
            ..lineTo(6.1, 14.4)
            ..lineTo(8.9, 12.2),
          stroke,
        );
        canvas.drawPath(
          Path()
            ..moveTo(6.2, 9.5)
            ..arcToPoint(const Offset(17.8, 9.5), radius: const Radius.circular(7), clockwise: true),
          stroke,
        );
        canvas.drawPath(
          Path()
            ..moveTo(17.8, 14.5)
            ..arcToPoint(const Offset(6.2, 14.5), radius: const Radius.circular(7), clockwise: true),
          stroke,
        );
        canvas.drawPath(
          Path()
            ..moveTo(14.8, 7.6)
            ..lineTo(17.9, 9.6)
            ..lineTo(15.1, 11.8),
          stroke,
        );
        canvas.drawPath(
          Path()
            ..moveTo(9.2, 16.4)
            ..lineTo(6.1, 14.4)
            ..lineTo(8.9, 12.2),
          stroke,
        );
      case MullGlyph.bell:
        canvas.drawPath(
          Path()
            ..moveTo(6.5, 17)
            ..lineTo(17.5, 17)
            ..lineTo(16.2, 14.8)
            ..lineTo(16.2, 11)
            ..cubicTo(16.2, 8.1, 14.3, 6.2, 12, 6.2)
            ..cubicTo(9.7, 6.2, 7.8, 8.1, 7.8, 11)
            ..lineTo(7.8, 14.8)
            ..close(),
          stroke,
        );
        canvas.drawPath(
          Path()
            ..moveTo(10.3, 19.2)
            ..cubicTo(10.7, 20.1, 11.3, 20.4, 12, 20.4)
            ..cubicTo(12.7, 20.4, 13.3, 20.1, 13.7, 19.2),
          stroke,
        );
      case MullGlyph.pause:
        canvas.drawLine(const Offset(9.5, 6.5), const Offset(9.5, 17.5), stroke);
        canvas.drawLine(const Offset(14.5, 6.5), const Offset(14.5, 17.5), stroke);
      case MullGlyph.chevronRight:
        canvas.drawPath(
          Path()
            ..moveTo(9.5, 5.5)
            ..lineTo(16, 12)
            ..lineTo(9.5, 18.5),
          stroke,
        );
      case MullGlyph.chevronLeft:
        canvas.drawPath(
          Path()
            ..moveTo(14.5, 5.5)
            ..lineTo(8, 12)
            ..lineTo(14.5, 18.5),
          stroke,
        );
      case MullGlyph.chevronDown:
        canvas.drawPath(
          Path()
            ..moveTo(5.5, 9.5)
            ..lineTo(12, 16)
            ..lineTo(18.5, 9.5),
          stroke,
        );
      case MullGlyph.close:
        canvas.drawLine(const Offset(6, 6), const Offset(18, 18), stroke);
        canvas.drawLine(const Offset(18, 6), const Offset(6, 18), stroke);
      case MullGlyph.check:
        canvas.drawPath(
          Path()
            ..moveTo(5, 12.5)
            ..lineTo(9.5, 17)
            ..lineTo(19, 7),
          stroke,
        );
      case MullGlyph.more:
        for (final y in [6.0, 12.0, 18.0]) {
          canvas.drawCircle(Offset(12, y), 1.5, fill);
        }
      case MullGlyph.plus:
        canvas.drawLine(const Offset(12, 5), const Offset(12, 19), stroke);
        canvas.drawLine(const Offset(5, 12), const Offset(19, 12), stroke);
      case MullGlyph.overview:
        // A pie with one slice pulled out: who has what share. (It was a dial,
        // which without a name under it read as a clock.)
        shape(
          Path()
            ..moveTo(11, 13)
            ..lineTo(11, 5.6)
            ..arcToPoint(const Offset(18.4, 13), radius: const Radius.circular(7.4), largeArc: true, clockwise: false)
            ..close(),
        );
        shape(
          Path()
            ..moveTo(13.3, 10.7)
            ..lineTo(13.3, 3.6)
            ..arcToPoint(const Offset(20.4, 10.7), radius: const Radius.circular(7.1))
            ..close(),
        );
      case MullGlyph.ledger:
        // A receipt. (It was three lines, which without a name under it read
        // as a menu.)
        final paper = Path()
          ..moveTo(6.5, 3.8)
          ..lineTo(17.5, 3.8)
          ..lineTo(17.5, 20);
        for (final (i, x) in const [15.67, 13.83, 12.0, 10.17, 8.33, 6.5].indexed) {
          paper.lineTo(x, i.isEven ? 18.8 : 20);
        }
        paper.close();
        void lines(Paint paint) {
          canvas.drawLine(const Offset(9.6, 8.6), const Offset(14.4, 8.6), paint);
          canvas.drawLine(const Offset(9.6, 12), const Offset(14.4, 12), paint);
          canvas.drawLine(const Offset(9.6, 15.4), const Offset(12.2, 15.4), paint);
        }
        if (filled) {
          cutOut(() => shape(paper), lines);
        } else {
          canvas.drawPath(paper, stroke);
          lines(stroke);
        }
      case MullGlyph.home:
        final house = Path()
          ..moveTo(5, 11)
          ..lineTo(12, 5)
          ..lineTo(19, 11)
          ..lineTo(19, 19)
          ..lineTo(5, 19)
          ..close();
        if (filled) {
          cutOut(
            () => shape(house),
            (hole) => canvas.drawRRect(
              RRect.fromLTRBAndCorners(
                10.2,
                13.6,
                13.8,
                21,
                topLeft: const Radius.circular(1.8),
                topRight: const Radius.circular(1.8),
              ),
              hole,
            ),
          );
        } else {
          canvas.drawPath(house, stroke);
        }
      case MullGlyph.grid:
        // Four tiles: a set of groups.
        for (final o in const [Offset(4.5, 4.5), Offset(13, 4.5), Offset(4.5, 13), Offset(13, 13)]) {
          shape(Path()..addRRect(RRect.fromRectAndRadius(o & const Size(6.5, 6.5), const Radius.circular(2))));
        }
      case MullGlyph.arrowUpRight:
        canvas.drawLine(const Offset(7, 17), const Offset(17, 7), stroke);
        canvas.drawPath(
          Path()
            ..moveTo(8.5, 7)
            ..lineTo(17, 7)
            ..lineTo(17, 15.5),
          stroke,
        );
    }
  }

  @override
  bool shouldRepaint(_GlyphPainter old) =>
      old.glyph != glyph || old.color != color || old.strokeWidth != strokeWidth || old.filled != filled;
}
