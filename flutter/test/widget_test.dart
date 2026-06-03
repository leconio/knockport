import 'package:flutter_test/flutter_test.dart';

import 'package:knockgate_client/main.dart';

void main() {
  testWidgets('KnockGate home screen renders', (WidgetTester tester) async {
    await tester.pumpWidget(const KnockGateApp());
    await tester.pumpAndSettle();

    expect(find.text('KnockGate Client'), findsOneWidget);
    expect(find.text('UDP knock ports'), findsOneWidget);
    expect(find.text('Protected TCP ports'), findsOneWidget);
  });
}
