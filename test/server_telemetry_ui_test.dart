import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bifrost/Models/bifrost_server.dart';
import 'package:bifrost/Pages/server_page.dart';
import 'package:bifrost/Services/server_manager_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    final String absoluteMockPath = Directory('./mock_servers').absolute.path;
    SharedPreferences.setMockInitialValues(<String, Object>{
      'use_default_server_directory': false,
      'custom_server_directory_path': absoluteMockPath,
    });

    // Create a mock server directory and metadata file
    final Directory mockDir = Directory('./mock_servers/test_server');
    await mockDir.create(recursive: true);
    final File metadataFile = File('./mock_servers/test_server/bifrost_server.json');
    await metadataFile.writeAsString(jsonEncode(<String, dynamic>{
      'name': 'Test Server',
      'version': '1.20.4',
      'type': 'vanilla',
      'allocatedRam': '2.0 GB',
      'paths': <String, String>{
        'root': mockDir.absolute.path,
        'world': '${mockDir.absolute.path}/world',
        'jars': '${mockDir.absolute.path}/jars',
        'mods': '${mockDir.absolute.path}/mods',
        'backups': '${mockDir.absolute.path}/backups',
        'properties': '${mockDir.absolute.path}/server.properties',
      },
    }));

    // Mock path provider
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'getApplicationSupportPath') {
          return '.';
        }
        return null;
      },
    );
  });

  tearDown(() async {
    final Directory mockDir = Directory('./mock_servers');
    if (await mockDir.exists()) {
      await mockDir.delete(recursive: true);
    }
  });

  testWidgets('ServerPage displays dynamic RAM and Players telemetry', (WidgetTester tester) async {
    final List<MethodCall> methodCalls = <MethodCall>[];

    // Mock local runtime to return custom status (e.g. state: running, memoryUsageMb: 1234)
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('bifrost/local_runtime'),
      (MethodCall methodCall) async {
        methodCalls.add(methodCall);
        switch (methodCall.method) {
          case 'getServerStatus':
            return <String, dynamic>{
              'state': 'running',
              'isBusy': false,
              'activeServerPath': Directory('./mock_servers/test_server').absolute.path,
              'consoleOutput': '[12:00:00] [Server thread/INFO]: PlayerOne joined the game\n[12:00:05] [Server thread/INFO]: PlayerTwo joined the game\n',
              'lastMessage': 'Server is running normally',
              'memoryUsageMb': 1234,
            };
          default:
            return null;
        }
      },
    );

    final ServerManagerService serverManager = ServerManagerService()..resetForTesting();
    await serverManager.loadStoredServers();

    final BifrostServer? server = serverManager.serverByPath(
      Directory('./mock_servers/test_server').absolute.path,
    );
    expect(server, isNotNull);
    expect(server!.name, equals('Test Server'));

    // Set server status to 'Running' via refreshing status
    await serverManager.refreshServerStatusFor(server.path);

    // Verify status was applied in serverManager
    expect(serverManager.memoryUsageFor(server.path), equals(1234));
    expect(serverManager.onlinePlayersFor(server.path), containsAll(<String>['PlayerOne', 'PlayerTwo']));

    // Build the ServerPage
    await tester.pumpWidget(
      MaterialApp(
        home: ServerPage(
          serverPath: server.path,
          serverManager: serverManager,
        ),
      ),
    );

    // Pump frames to complete the entrance transition without hanging on the periodic refresh timer
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));

    // Verify that RAM usage '1234 MB' is displayed
    expect(find.text('1234 MB'), findsWidgets);

    // Verify that '2 online (PlayerOne, PlayerTwo)' is displayed
    expect(find.text('2 online (PlayerOne, PlayerTwo)'), findsWidgets);
  });
}
