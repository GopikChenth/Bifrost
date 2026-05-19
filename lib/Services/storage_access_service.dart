import 'package:flutter/services.dart';

class StorageAccessException implements Exception {
  const StorageAccessException(this.message);

  final String message;

  @override
  String toString() => 'StorageAccessException: $message';
}

/// Thin wrapper over the `bifrost/storage_access` method channel.
///
/// With MANAGE_EXTERNAL_STORAGE the only native calls needed are
/// permission checks.  All file I/O happens through plain `dart:io`.
class StorageAccessService {
  const StorageAccessService();

  static const MethodChannel _channel = MethodChannel(
    'bifrost/storage_access',
  );

  /// Returns `true` when the app has the MANAGE_EXTERNAL_STORAGE
  /// permission (or the device is below API 30).
  Future<bool> hasAllFilesAccess() async {
    try {
      return await _channel.invokeMethod<bool>('hasAllFilesAccess') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Opens the system settings page where the user can grant
  /// "All files access" to this app.
  Future<void> requestAllFilesAccess() async {
    try {
      await _channel.invokeMethod<void>('requestAllFilesAccess');
    } on PlatformException catch (error) {
      throw StorageAccessException(
        error.message ?? 'Unable to open storage settings.',
      );
    } on MissingPluginException {
      throw const StorageAccessException(
        'Android storage bridge is not available.',
      );
    }
  }

  /// Returns the default external base path for Bifrost
  /// (e.g. `/storage/emulated/0/Bifrost`).
  Future<String> getDefaultExternalBasePath() async {
    try {
      final String? result = await _channel.invokeMethod<String>(
        'getDefaultExternalBasePath',
      );
      return result ?? '';
    } on PlatformException catch (error) {
      throw StorageAccessException(
        error.message ?? 'Unable to resolve external storage path.',
      );
    } on MissingPluginException {
      throw const StorageAccessException(
        'Android storage bridge is not available.',
      );
    }
  }
}
