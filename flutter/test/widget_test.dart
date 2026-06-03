import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:knockgate_client/app/knockgate_app.dart';

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
    expect(find.byType(BottomNavigationBar), findsOneWidget);
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

  testWidgets('Knock failure keeps log sheet open', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const KnockGateApp());
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Knock'));
    await tester.pumpAndSettle();

    expect(find.text('Knock logs'), findsOneWidget);
    expect(find.textContaining('Starting knock'), findsOneWidget);
    expect(find.textContaining('Failed'), findsOneWidget);
    expect(find.byIcon(Icons.close), findsOneWidget);

    final material = tester.widget<Material>(
      find
          .ancestor(
            of: find.text('Knock logs'),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(material.color, Colors.black);
  });

  testWidgets('More menu opens knock log sheet', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const KnockGateApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Knock logs'));
    await tester.pumpAndSettle();

    expect(find.text('Knock logs'), findsOneWidget);
    expect(find.text('No knock logs yet.'), findsOneWidget);
  });

  testWidgets('Scanner menu falls back when scanner is not bundled', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const KnockGateApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan QR'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'QR scanning is not available in this build. Paste the import URL instead.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('Bottom tab removes bottom safe area', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(padding: EdgeInsets.only(bottom: 34)),
        child: const KnockGateApp(),
      ),
    );
    await tester.pumpAndSettle();

    final navigationContext = tester.element(find.byType(BottomNavigationBar));
    expect(MediaQuery.paddingOf(navigationContext).bottom, 0);
  });

  testWidgets('Tapping blank space dismisses focused text field', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const KnockGateApp());
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextField, 'Name'));
    await tester.pump();
    expect(FocusManager.instance.primaryFocus, isNotNull);

    await tester.tapAt(const Offset(390, 420));
    await tester.pumpAndSettle();

    expect(
      FocusManager.instance.primaryFocus?.context?.widget,
      isNot(isA<EditableText>()),
    );
  });
}
