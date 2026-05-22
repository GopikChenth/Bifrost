import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bifrost/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'getApplicationSupportPath') {
          return '.'; // Return current directory as mock path
        }
        return null;
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

  testWidgets('Dashboard renders and shows empty state', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const BifrostApp());

    // Pump a few frames with a small duration to let async futures resolve
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // Verify that the title/empty state is shown
    expect(find.text('No servers yet'), findsOneWidget);
    expect(find.text('New Server'), findsOneWidget);
  });
}
