import 'package:flutter/services.dart';

class FileManagerServiceException implements Exception {
  const FileManagerServiceException(this.message);

  final String message;

  @override
  String toString() => 'FileManagerServiceException: $message';
}

class FileManagerService {
  const FileManagerService();

  static const MethodChannel _channel = MethodChannel('bifrost/file_manager');

  Future<void> openFolder(String folderPath) async {
    try {
      await _channel.invokeMethod<void>('openFolder', <String, Object?>{
        'folderPath': folderPath,
      });
    } on MissingPluginException {
      throw const FileManagerServiceException(
        'Android file manager integration is not connected yet.',
      );
    } on PlatformException catch (error) {
      throw FileManagerServiceException(
        error.message ?? 'Unable to open the requested folder.',
      );
    }
  }
}
