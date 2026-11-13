import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mull/data/models.dart';
import 'package:mull/data/store.dart';
import 'package:mull/screens/groups/group_bar.dart';
import 'package:mull/ui/icons.dart';
import 'package:mull/ui/sheet.dart';
import 'package:mull/ui/tokens.dart';

/// Three things Bharat saw on the 1.1.0 TestFlight build.
void main() {
  // The tab label is measured in the real typeface: the test font is a row of
  // boxes, and the question is whether "Recurring" crowds its pill.
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final ranade = FontLoader('Ranade')..addFont(rootBundle.load('assets/fonts/Ranade-Regular.otf'));
    await ranade.load();
  });

  Widget app(Widget child, {MullStore? store}) => StoreScope(
    store: store ?? MullStore.memory(),
    child: MaterialApp(theme: buildTheme(MullColors.dark), home: Scaffold(body: child)),
  );

  testWidgets('the highlight comes to rest centred on the open tab', (t) async {
    await t.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => t.binding.setSurfaceSize(null));
    bool isPill(Widget w) =>
        w is DecoratedBox &&
        w.decoration is BoxDecoration &&
        (w.decoration as BoxDecoration).borderRadius == BorderRadius.circular(24);
    for (final tab in GroupTab.values) {
      await t.pumpWidget(
        app(Align(alignment: Alignment.bottomCenter, child: GroupBar(current: tab, onSelect: (_) {}, onAdd: () {}))),
      );
      await t.pumpAndSettle();
      final icon = t.getCenter(find.byWidgetPredicate((w) => w is MullIcon && w.glyph == tab.glyph && w.filled));
      final pill = t.getCenter(find.byWidgetPredicate(isPill));
      expect(pill.dx, closeTo(icon.dx, .5), reason: tab.label);
      expect(pill.dy, closeTo(icon.dy, 1), reason: tab.label);
    }
  });

  testWidgets('a long notice is read in full, not cut off', (t) async {
    await t.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(app(const SizedBox.expand()));
    const message = 'You confirmed this, so only Vivaan can take it off. Ask them if it was a mistake.';
    Toast.show(t.element(find.byType(SizedBox).last), message);
    await t.pumpAndSettle();
    expect(t.renderObject<RenderParagraph>(find.text(message)).didExceedMaxLines, isFalse);
    Toast.hide();
  });

  group('appearance', () {
    test('a new phone follows the system', () {
      expect(Profile().theme, ThemeMode.system);
    });

    test('a phone saved before you could tell dark from untouched follows the system', () {
      expect(Profile.fromJson({'theme': 'dark'}).theme, ThemeMode.system);
    });

    test('light, once picked, stays light', () {
      expect(Profile.fromJson({'theme': 'light'}).theme, ThemeMode.light);
    });

    test('dark picked from now on stays dark', () {
      final saved = (Profile()..theme = ThemeMode.dark).toJson();
      expect(Profile.fromJson(saved).theme, ThemeMode.dark);
    });
  });
}
