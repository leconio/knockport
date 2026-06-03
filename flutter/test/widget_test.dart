import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:knockgate_client/main.dart';

void main() {
  testWidgets('KnockGate home screen renders', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const KnockGateApp());
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.text('KnockGate'),
      ),
      findsOneWidget,
    );
    final appBar = tester.widget<AppBar>(find.byType(AppBar));
    expect(appBar.backgroundColor, Colors.transparent);
    expect(appBar.surfaceTintColor, Colors.transparent);
    expect(appBar.shadowColor, Colors.transparent);
    expect(appBar.forceMaterialTransparency, isTrue);
    expect(appBar.systemOverlayStyle?.statusBarColor, Colors.transparent);
    expect(appBar.systemOverlayStyle?.statusBarIconBrightness, Brightness.dark);
    expect(appBar.systemOverlayStyle?.statusBarBrightness, Brightness.light);
    expect(appBar.bottom, isNull);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('UDP knock ports'), findsOneWidget);
    expect(find.text('TCP ports to check'), findsNothing);
    expect(find.text('Activity'), findsNothing);
    expect(find.text('Ready'), findsNothing);
    expect(find.text('Knock'), findsWidgets);
    expect(find.text('Check'), findsWidgets);

    await tester.tap(find.text('Check').last);
    await tester.pumpAndSettle();

    expect(find.text('TCP ports to check'), findsOneWidget);
    expect(find.text('UDP knock ports'), findsNothing);
  });
}
