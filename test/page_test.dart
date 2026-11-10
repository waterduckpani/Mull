import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mull/data/store.dart';
import 'package:mull/ui/page.dart';
import 'package:mull/ui/tokens.dart';

void main() {
  Future<void> pumpPage(WidgetTester t, {required int rows}) async {
    await t.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(
      StoreScope(
        store: MullStore.memory(),
        child: MaterialApp(
          theme: buildTheme(MullColors.light),
          home: MullPage(
            bottom: const Text('Budget covers 5 of 7'),
            children: [for (var i = 0; i < rows; i++) SizedBox(height: 90, child: Text('row $i'))],
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  /// The floating footer sits over the list, so anything in it — not just a
  /// button — has to have something solid behind it.
  // By key, not by type: the profile avatar is also an AnimatedOpacity, and
  // matching that one made an earlier version of this test pass on a widget
  // 44 pixels tall in the opposite corner of the screen.
  final finder = find.byKey(const ValueKey('footerScrim'));

  /// The alpha the solid part of the footer backing is painted at.
  double backing(WidgetTester t) {
    // AnimatedContainer folds a plain `color:` into a BoxDecoration.
    final box = t.widget<AnimatedContainer>(
      find.descendant(of: find.byType(MullPage), matching: find.byType(AnimatedContainer)).last,
    );
    return ((box.decoration as BoxDecoration?)?.color ?? const Color(0x00000000)).a;
  }

  testWidgets('the footer is backed once the list runs underneath it', (t) async {
    await pumpPage(t, rows: 20);
    expect(backing(t), greaterThan(.9));

    // The fade has to sit entirely above the content, so the content itself is
    // always on solid ground rather than halfway down a gradient.
    final fade = t.getRect(finder);
    final label = t.getRect(find.text('Budget covers 5 of 7'));
    expect(fade.bottom, lessThanOrEqualTo(label.top), reason: 'the fade must end before the text starts');
  });

  testWidgets('and stays clear when everything already fits', (t) async {
    await pumpPage(t, rows: 1);
    expect(backing(t), 0, reason: 'a solid band over nothing would just hide the backdrop');
  });

  testWidgets('bottomInset keeps the last row clear of a bar laid over the page', (t) async {
    await t.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(
      StoreScope(
        store: MullStore.memory(),
        child: MaterialApp(
          theme: buildTheme(MullColors.dark),
          home: Builder(
            builder: (context) => Stack(
              children: [
                MullPage(
                  bottomInset: 60,
                  header: const SizedBox(height: 44),
                  children: [for (var i = 0; i < 20; i++) SizedBox(height: 80, child: Text('row $i'))],
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: ShellMetrics.ctaBottom(context),
                  height: 60,
                  child: const ColoredBox(key: Key('bar'), color: Color(0xFF000000)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.drag(find.byType(Scrollable).first, const Offset(0, -4000));
    await t.pumpAndSettle();

    expect(
      t.getRect(find.text('row 19')).bottom,
      lessThanOrEqualTo(t.getRect(find.byKey(const Key('bar'))).top),
      reason: 'the last row has to scroll all the way out from under the bar',
    );
  });
}
