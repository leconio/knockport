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
    expect(find.text('UDP knock ports'), findsOneWidget);
    expect(find.text('Protected ports'), findsOneWidget);
  });
}
