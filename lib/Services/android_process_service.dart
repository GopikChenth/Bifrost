import 'package:flutter/services.dart';

enum AndroidProcessEventType { stdout, stderr, started, exited }

class AndroidProcessServiceException implements Exception {
  const AndroidProcessServiceException(this.message);

  final String message;

  @override
  String toString() => 'AndroidProcessServiceException: $message';
}

class AndroidProcessStartRequest {
  const AndroidProcessStartRequest({
    required this.serverPath,
    required this.serverName,
    required this.executablePath,
    required this.arguments,
    required this.workingDirectory,
  });

  final String serverPath;
  final String serverName;
  final String executablePath;
  final List<String> arguments;
  final String workingDirectory;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'serverPath': serverPath,
      'serverName': serverName,
      'executablePath': executablePath,
      'arguments': arguments,
      'workingDirectory': workingDirectory,
    };
  }
}

class AndroidProcessEvent {
  const AndroidProcessEvent({
    required this.type,
    required this.serverPath,
    this.message,
    this.exitCode,
  });

  final AndroidProcessEventType type;
  final String serverPath;
  final String? message;
  final int? exitCode;
}

class AndroidProcessService {
  const AndroidProcessService();

  static const MethodChannel _methodChannel = MethodChannel(
    'bifrost/android_process',
  );
  static const EventChannel _eventChannel = EventChannel(
    'bifrost/android_process/events',
  );

  Stream<AndroidProcessEvent> get events {
    return _eventChannel.receiveBroadcastStream().map<AndroidProcessEvent>((
      dynamic rawEvent,
    ) {
      final Map<Object?, Object?> eventMap = rawEvent as Map<Object?, Object?>;
      final String rawType = (eventMap['type'] as String?)?.trim() ?? '';
      final String serverPath = (eventMap['serverPath'] as String?)?.trim() ?? '';
      final String? message = (eventMap['message'] as String?)?.trim();
      final int? exitCode = eventMap['exitCode'] as int?;

      if (serverPath.isEmpty) {
        throw const AndroidProcessServiceException(
          'Received a process event without a server path.',
        );
      }

      return AndroidProcessEvent(
        type: _parseEventType(rawType),
        serverPath: serverPath,
        message: message,
        exitCode: exitCode,
      );
    });
  }

  Future<void> startProcess(AndroidProcessStartRequest request) async {
    try {
      await _methodChannel.invokeMethod<void>('startProcess', request.toMap());
    } on MissingPluginException {
      throw const AndroidProcessServiceException(
        'Android process integration is not connected yet.',
      );
    } on PlatformException catch (error) {
      throw AndroidProcessServiceException(
        error.message ?? 'Unable to start the Android server process.',
      );
    }
  }

  Future<void> sendCommand({
    required String serverPath,
    required String command,
  }) async {
    try {
      await _methodChannel.invokeMethod<void>('sendCommand', <String, Object?>{
        'serverPath': serverPath,
        'command': command,
      });
    } on MissingPluginException {
      throw const AndroidProcessServiceException(
        'Android process integration is not connected yet.',
      );
    } on PlatformException catch (error) {
      throw AndroidProcessServiceException(
        error.message ?? 'Unable to send a command to the server process.',
      );
    }
  }

  Future<void> stopProcess({required String serverPath}) async {
    try {
      await _methodChannel.invokeMethod<void>('stopProcess', <String, Object?>{
        'serverPath': serverPath,
      });
    } on MissingPluginException {
      throw const AndroidProcessServiceException(
        'Android process integration is not connected yet.',
      );
    } on PlatformException catch (error) {
      throw AndroidProcessServiceException(
        error.message ?? 'Unable to stop the Android server process.',
      );
    }
  }

  AndroidProcessEventType _parseEventType(String rawType) {
    switch (rawType) {
      case 'stdout':
        return AndroidProcessEventType.stdout;
      case 'stderr':
        return AndroidProcessEventType.stderr;
      case 'started':
        return AndroidProcessEventType.started;
      case 'exited':
        return AndroidProcessEventType.exited;
      default:
        throw AndroidProcessServiceException(
          'Received an unknown Android process event type: $rawType',
        );
    }
  }
}
