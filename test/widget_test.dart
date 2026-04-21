import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:productivity_app/screens/assistant_screen.dart';

void main() {
  testWidgets('Mini JARVIS assistant loads', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AssistantScreen(),
      ),
    );

    expect(find.text('Mini JARVIS'), findsOneWidget);
    expect(find.text('Ask JARVIS...'), findsOneWidget);
    expect(find.text('Briefing'), findsOneWidget);
    expect(find.text('Finance'), findsOneWidget);
  });
}
