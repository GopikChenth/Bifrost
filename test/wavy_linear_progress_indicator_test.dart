import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bifrost/Components/wavy_linear_progress_indicator.dart';

void main() {
  group('WavyLinearProgressIndicator Tests', () {
    testWidgets('Renders correctly with determinate progress', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: WavyLinearProgressIndicator(
                value: 0.5,
                gapSize: 10.0,
              ),
            ),
          ),
        ),
      );

      // Verify that CustomPaint is rendered
      expect(
        find.descendant(
          of: find.byType(WavyLinearProgressIndicator),
          matching: find.byType(CustomPaint),
        ),
        findsOneWidget,
      );

      // Verify widget properties
      final WavyLinearProgressIndicator progressIndicator =
          tester.widget(find.byType(WavyLinearProgressIndicator));
      expect(progressIndicator.value, 0.5);
      expect(progressIndicator.gapSize, 10.0);
    });

    testWidgets('Renders correctly with indeterminate progress', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: WavyLinearProgressIndicator(
                value: null,
                gapSize: 12.0,
              ),
            ),
          ),
        ),
      );

      // Verify that CustomPaint is rendered
      expect(
        find.descendant(
          of: find.byType(WavyLinearProgressIndicator),
          matching: find.byType(CustomPaint),
        ),
        findsOneWidget,
      );

      final WavyLinearProgressIndicator progressIndicator =
          tester.widget(find.byType(WavyLinearProgressIndicator));
      expect(progressIndicator.value, isNull);
      expect(progressIndicator.gapSize, 12.0);
    });
  });
}
