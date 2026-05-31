import 'package:bifrost/Utils/local_runtime_models.dart';
import 'package:flutter/services.dart';

class LocalRuntimeServiceException implements Exception {
  const LocalRuntimeServiceException(this.message);

  final String message;
}

class LocalRuntimeService {
  const LocalRuntimeService();

  static const MethodChannel _channel = MethodChannel(
    'bifrost/local_runtime',
  );

  Future<LocalRuntimeStatus> getRuntimeStatus() async {
    try {
      final Map<Object?, Object?>? result =
          await _channel.invokeMapMethod<Object?, Object?>('getRuntimeStatus');
      return LocalRuntimeStatus.fromMap(
        result ?? <Object?, Object?>{},
      );
    } on PlatformException catch (error) {
      throw LocalRuntimeServiceException(
        error.message ?? 'Unable to inspect the local runtime status.',
      );
    }
  }

  Future<LocalRuntimeStatus> prepareBundledRuntimeHome({
    int runtimeMajor = 21,
  }) async {
    try {
      final Map<Object?, Object?>? result =
          await _channel.invokeMapMethod<Object?, Object?>(
        'prepareBundledRuntimeHome',
        <String, Object?>{'runtimeMajor': runtimeMajor},
      );
      return LocalRuntimeStatus.fromMap(
        result ?? <Object?, Object?>{},
      );
    } on PlatformException catch (error) {
      throw LocalRuntimeServiceException(
        error.message ?? 'Unable to prepare the bundled runtime.',
      );
    }
  }

  Future<LocalRuntimeTestResult> runJavaVersion({
    String? workingDirectory,
    int runtimeMajor = 21,
  }) async {
    try {
      final Map<Object?, Object?>? result = await _channel
          .invokeMapMethod<Object?, Object?>('runJavaVersion', <String, Object?>{
            'workingDirectory': workingDirectory,
            'runtimeMajor': runtimeMajor,
          });
      return LocalRuntimeTestResult.fromMap(
        result ?? <Object?, Object?>{},
      );
    } on PlatformException catch (error) {
      throw LocalRuntimeServiceException(
        error.message ?? 'Unable to run the bundled Java runtime.',
      );
    }
  }

  Future<LocalServerStatus> getServerStatus() async {
    try {
      final Map<Object?, Object?>? result =
          await _channel.invokeMapMethod<Object?, Object?>('getServerStatus');
      return LocalServerStatus.fromMap(
        result ?? <Object?, Object?>{},
      );
    } on PlatformException catch (error) {
      throw LocalRuntimeServiceException(
        error.message ?? 'Unable to inspect the local server status.',
      );
    }
  }

  Future<LocalConsoleOutput> getServerConsoleOutput(int lastTotalRead) async {
    try {
      final Map<Object?, Object?>? result = await _channel
          .invokeMapMethod<Object?, Object?>('getServerConsoleOutput', <String, Object?>{
        'lastTotalRead': lastTotalRead,
      });
      return LocalConsoleOutput.fromMap(
        result ?? <Object?, Object?>{},
      );
    } on PlatformException catch (error) {
      throw LocalRuntimeServiceException(
        error.message ?? 'Unable to inspect the server console output.',
      );
    }
  }

  Future<LocalServerStatus> startServer({
    required String serverPath,
    required String jarPath,
    required int maxRamMb,
    int runtimeMajor = 21,
  }) async {
    try {
      final Map<Object?, Object?>? result = await _channel
          .invokeMapMethod<Object?, Object?>('startServer', <String, Object?>{
            'serverPath': serverPath,
            'jarPath': jarPath,
            'maxRamMb': maxRamMb,
            'runtimeMajor': runtimeMajor,
          });
      return LocalServerStatus.fromMap(
        result ?? <Object?, Object?>{},
      );
    } on PlatformException catch (error) {
      throw LocalRuntimeServiceException(
        error.message ?? 'Unable to start the local server runtime.',
      );
    }
  }

  Future<LocalServerStatus> stopServer() async {
    try {
      final Map<Object?, Object?>? result =
          await _channel.invokeMapMethod<Object?, Object?>('stopServer');
      return LocalServerStatus.fromMap(
        result ?? <Object?, Object?>{},
      );
    } on PlatformException catch (error) {
      throw LocalRuntimeServiceException(
        error.message ?? 'Unable to stop the local server runtime.',
      );
    }
  }

  Future<LocalServerStatus> sendServerCommand(String command) async {
    try {
      final Map<Object?, Object?>? result =
          await _channel.invokeMapMethod<Object?, Object?>(
        'sendServerCommand',
        <String, Object?>{'command': command},
      );
      return LocalServerStatus.fromMap(
        result ?? <Object?, Object?>{},
      );
    } on PlatformException catch (error) {
      throw LocalRuntimeServiceException(
        error.message ?? 'Unable to send the server command.',
      );
    }
  }

  Future<void> updateNotification({
    required String name,
    required String type,
    required String version,
    required String status,
  }) async {
    try {
      await _channel.invokeMethod('updateNotification', <String, Object?>{
        'name': name,
        'type': type,
        'version': version,
        'status': status,
      });
    } on PlatformException catch (error) {
      throw LocalRuntimeServiceException(
        error.message ?? 'Unable to update the server notification.',
      );
    }
  }

  Future<void> cancelNotification() async {
    try {
      await _channel.invokeMethod('cancelNotification');
    } on PlatformException catch (error) {
      throw LocalRuntimeServiceException(
        error.message ?? 'Unable to cancel the server notification.',
      );
    }
  }

  void setNotificationCallback({
    required Function() onStart,
    required Function() onStop,
  }) {
    _channel.setMethodCallHandler((MethodCall call) async {
      switch (call.method) {
        case 'startServerFromNotification':
          onStart();
          break;
        case 'stopServerFromNotification':
          onStop();
          break;
      }
    });
  }
}
