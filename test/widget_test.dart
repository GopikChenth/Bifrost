import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bifrost/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    
    // Mock path_provider method channel
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async {
        return '.'; // Return current directory as mock path
      },
    );
  });

  testWidgets('Add Server Morph Dialog Test', (WidgetTester tester) async {
    // Build the app
    await tester.pumpWidget(const BifrostApp());
    
    // Pump a few times to let ServerManagerService load servers
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // Verify FAB is present
    final Finder fabFinder = find.byType(FloatingActionButton);
    expect(fabFinder, findsOneWidget);

    // Tap the FAB to trigger the push transition
    await tester.tap(fabFinder);
    
    // Run the push animation (duration is 300ms)
    // Pump frames to complete the transition
    await tester.pump(); // Start transition
    for (int i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 30));
    }

    // Verify dialog is shown
    expect(find.text('Add Server'), findsOneWidget);

    // Close the dialog to trigger pop transition
    final Finder closeFinder = find.text('Close');
    expect(closeFinder, findsOneWidget);
    await tester.tap(closeFinder);

    // Run the reverse animation (reverse duration is 250ms)
    await tester.pump(); // Start transition
    for (int i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 30));
    }

    // Pump a bit more to ensure it settled back
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  });
}
