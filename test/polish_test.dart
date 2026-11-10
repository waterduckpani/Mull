import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mull/data/models.dart';
import 'package:mull/data/store.dart';
import 'package:mull/screens/groups/group_bar.dart';
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

  testWidgets('the open tab name has room either side of it, Recurring included', (t) async {
    await t.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => t.binding.setSurfaceSize(null));
    for (final tab in GroupTab.values) {
      await t.pumpWidget(
        app(Align(alignment: Alignment.bottomCenter, child: GroupBar(current: tab, onSelect: (_) {}, onAdd: () {}))),
      );
      await t.pumpAndSettle();
      final label = t.getRect(find.text(tab.label));
      final pill = t.getRect(
        find.ancestor(of: find.text(tab.label), matching: find.byType(AnimatedContainer)).first,
      );
      expect(label.left - pill.left, greaterThanOrEqualTo(8), reason: '${tab.label}, left');
      expect(pill.right - label.right, greaterThanOrEqualTo(8), reason: '${tab.label}, right');
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
