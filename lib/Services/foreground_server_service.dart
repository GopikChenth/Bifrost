import 'package:flutter/services.dart';

class ForegroundServerServiceException implements Exception {
  const ForegroundServerServiceException(this.message);

  final String message;

  @override
  String toString() => 'ForegroundServerServiceException: $message';
}

class ForegroundServerNotification {
  const ForegroundServerNotification({
    required this.serverName,
    required this.statusText,
  });

  final String serverName;
  final String statusText;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'serverName': serverName,
      'statusText': statusText,
    };
  }
}

class ForegroundServerService {
  const ForegroundServerService();

  static const MethodChannel _channel = MethodChannel(
    'bifrost/foreground_server',
  );

  Future<void> start(ForegroundServerNotification notification) async {
    try {
      await _channel.invokeMethod<void>('start', notification.toMap());
    } on MissingPluginException {
      throw const ForegroundServerServiceException(
        'Android foreground service integration is not connected yet.',
      );
    } on PlatformException catch (error) {
      throw ForegroundServerServiceException(
        error.message ?? 'Unable to start the Android foreground service.',
      );
    }
  }

  Future<void> update(ForegroundServerNotification notification) async {
    try {
      await _channel.invokeMethod<void>('update', notification.toMap());
    } on MissingPluginException {
      throw const ForegroundServerServiceException(
        'Android foreground service integration is not connected yet.',
      );
    } on PlatformException catch (error) {
      throw ForegroundServerServiceException(
        error.message ?? 'Unable to update the Android foreground service.',
      );
    }
  }

  Future<void> stop() async {
    try {
      await _channel.invokeMethod<void>('stop');
    } on MissingPluginException {
      throw const ForegroundServerServiceException(
        'Android foreground service integration is not connected yet.',
      );
    } on PlatformException catch (error) {
      throw ForegroundServerServiceException(
        error.message ?? 'Unable to stop the Android foreground service.',
      );
    }
  }
}
