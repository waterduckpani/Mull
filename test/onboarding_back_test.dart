import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mull/data/store.dart';
import 'package:mull/screens/onboarding_flow.dart';
import 'package:mull/ui/tokens.dart';

/// Android's back gesture during sign-up. The steps are one screen, not
/// routes, so a back swipe to fix a mistyped email used to close the app.
void main() {
  Future<void> pumpFlow(WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(
      StoreScope(
        store: MullStore.memory(),
        child: MaterialApp(theme: buildTheme(MullColors.dark), home: const OnboardingFlow()),
      ),
    );
    await t.pumpAndSettle();
  }

  Future<void> systemBack(WidgetTester t) async {
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
  }

  testWidgets('back goes back a step, not out of the app', (t) async {
    await pumpFlow(t);
    await t.tap(find.text('Get started'));
    await t.pumpAndSettle();
    expect(find.text('What should we call you?'), findsOneWidget);

    // The other steps' fields are in the tree too, just not on screen.
    await t.enterText(find.byType(TextField).hitTestable(), 'Bharat');
    await t.pump();
    await t.tap(find.text('Continue'));
    await t.pumpAndSettle();
    expect(find.text('Your UPI ID?'), findsOneWidget);

    await systemBack(t);
    expect(find.text('What should we call you?'), findsOneWidget);
    await systemBack(t);
    expect(find.text('Get started'), findsOneWidget, reason: 'back on the welcome screen');
  });
}
