import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bifrost/Models/bifrost_server.dart';
import 'package:bifrost/Services/server_manager_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final List<MethodCall> methodCalls = <MethodCall>[];
  late ServerManagerService serverManager;

  setUp(() {
    methodCalls.clear();
    SharedPreferences.setMockInitialValues(<String, Object>{});

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

    // Mock local runtime
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('bifrost/local_runtime'),
      (MethodCall methodCall) async {
        methodCalls.add(methodCall);
        switch (methodCall.method) {
          case 'getServerStatus':
            return <String, dynamic>{
              'state': 'stopped',
              'isBusy': false,
              'activeServerPath': null,
              'consoleOutput': '',
              'lastMessage': null,
            };
          case 'startServer':
            return <String, dynamic>{
              'state': 'starting',
              'isBusy': true,
              'activeServerPath': methodCall.arguments['serverPath'],
              'consoleOutput': '',
              'lastMessage': 'Launching server',
            };
          case 'stopServer':
            return <String, dynamic>{
              'state': 'stopping',
              'isBusy': true,
              'activeServerPath': null,
              'consoleOutput': '',
              'lastMessage': 'Stopping server',
            };
          default:
            return null;
        }
      },
    );

    ServerManagerService.enableAndroidNotificationForTesting = true;
    serverManager = ServerManagerService()..resetForTesting();
  });

  tearDown(() {
    ServerManagerService.enableAndroidNotificationForTesting = false;
  });

  test('ServerManagerService tracks last started server and updates native notification', () async {
    const BifrostServer testServer = BifrostServer(
      name: 'Test Server',
      path: '/path/to/server',
      type: 'vanilla',
      version: '1.20.4',
      memoryLabel: '2.0 GB',
      status: 'Offline',
      isBusy: false,
    );

    // Initial state
    expect(serverManager.lastStartedServerPath, isNull);

    // Inject server into internal list
    // (In a real app, this would happen by loading, but we can call loadStoredServers or mock storage)
    // For testing, let's call loadStoredServers with a mock storage if possible, or just check path tracking.
    // Wait, let's test last started server path saving:
    await serverManager.startServer(testServer);

    expect(serverManager.lastStartedServerPath, equals('/path/to/server'));

    // Check if the updateNotification method call was made
    final Iterable<MethodCall> notificationUpdates = methodCalls.where(
      (MethodCall c) => c.method == 'updateNotification',
    );
    expect(notificationUpdates, isNotEmpty);
    
    final MethodCall updateCall = notificationUpdates.first;
    expect(updateCall.arguments['name'], equals('Test Server'));
    expect(updateCall.arguments['status'], equals('Offline'));
  });

  test('ServerManagerService clears notification when last started server is deleted', () async {
    const BifrostServer testServer = BifrostServer(
      name: 'Test Server',
      path: '/path/to/server',
      type: 'vanilla',
      version: '1.20.4',
      memoryLabel: '2.0 GB',
      status: 'Offline',
      isBusy: false,
    );

    await serverManager.startServer(testServer);
    expect(serverManager.lastStartedServerPath, equals('/path/to/server'));

    // Delete server
    await serverManager.deleteServer(testServer);

    expect(serverManager.lastStartedServerPath, isNull);

    // Check if cancelNotification was called
    final bool hasCancelCall = methodCalls.any((MethodCall c) => c.method == 'cancelNotification');
    expect(hasCancelCall, isTrue);
  });
}
