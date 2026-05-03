import 'package:flutter/services.dart';

class StorageAccessException implements Exception {
  const StorageAccessException(this.message);

  final String message;

  @override
  String toString() => 'StorageAccessException: $message';
}

class StorageAccessService {
  const StorageAccessService();

  static const MethodChannel _channel = MethodChannel(
    'bifrost/storage_access',
  );

  Future<Map<String, Object?>> createServerStructure({
    required String treeUri,
    required String serverName,
    required String version,
    required String serverType,
    required String memoryLabel,
    required String serverProperties,
  }) async {
    return _invokeMap(
      'createServerStructure',
      <String, Object?>{
        'treeUri': treeUri,
        'serverName': serverName,
        'version': version,
        'serverType': serverType,
        'memoryLabel': memoryLabel,
        'serverProperties': serverProperties,
      },
    );
  }

  Future<List<Map<String, Object?>>> loadStoredServers({
    required String treeUri,
  }) async {
    try {
      final List<dynamic>? result = await _channel.invokeMethod<List<dynamic>>(
        'loadStoredServers',
        <String, Object?>{'treeUri': treeUri},
      );
      return (result ?? <dynamic>[])
          .whereType<Map<Object?, Object?>>()
          .map(
            (Map<Object?, Object?> entry) => entry.map(
              (Object? key, Object? value) =>
                  MapEntry(key.toString(), value as Object?),
            ),
          )
          .toList();
    } on PlatformException catch (error) {
      throw StorageAccessException(error.message ?? 'Unable to load servers.');
    }
  }

  Future<Map<String, Object?>> copyFileToDirectory({
    required String directoryUri,
    required String fileName,
    required String sourcePath,
  }) {
    return _invokeMap(
      'copyFileToDirectory',
      <String, Object?>{
        'directoryUri': directoryUri,
        'fileName': fileName,
        'sourcePath': sourcePath,
      },
    );
  }

  Future<void> writeDownloadMetadata({
    required String metadataUri,
    required Map<String, Object?> downloadMetadata,
  }) async {
    try {
      await _channel.invokeMethod<void>(
        'writeDownloadMetadata',
        <String, Object?>{
          'metadataUri': metadataUri,
          'downloadMetadata': downloadMetadata,
        },
      );
    } on PlatformException catch (error) {
      throw StorageAccessException(
        error.message ?? 'Unable to write server metadata.',
      );
    }
  }

  Future<void> deleteServerDirectory({
    required String treeUri,
    String? serverUri,
    String? serverPath,
  }) async {
    try {
      await _channel.invokeMethod<void>(
        'deleteServerDirectory',
        <String, Object?>{
          'treeUri': treeUri,
          'serverUri': serverUri,
          'serverPath': serverPath,
        },
      );
    } on PlatformException catch (error) {
      throw StorageAccessException(
        error.message ?? 'Unable to delete the server directory.',
      );
    }
  }

  Future<Map<String, Object?>> prepareServerLaunch({
    required String serverUri,
  }) {
    return _invokeMap(
      'prepareServerLaunch',
      <String, Object?>{'serverUri': serverUri},
    );
  }

  Future<Map<String, Object?>> copyServerToDirectory({
    required String serverUri,
    required String destinationPath,
  }) {
    return _invokeMap(
      'copyServerToDirectory',
      <String, Object?>{
        'serverUri': serverUri,
        'destinationPath': destinationPath,
      },
    );
  }

  Future<void> syncDirectoryToServer({
    required String serverUri,
    required String sourcePath,
  }) async {
    try {
      await _channel.invokeMethod<void>(
        'syncDirectoryToServer',
        <String, Object?>{
          'serverUri': serverUri,
          'sourcePath': sourcePath,
        },
      );
    } on PlatformException catch (error) {
      throw StorageAccessException(
        error.message ?? 'Unable to sync server files.',
      );
    }
  }

  Future<Map<String, Object?>> _invokeMap(
    String method,
    Map<String, Object?> arguments,
  ) async {
    try {
      final Map<Object?, Object?>? result = await _channel
          .invokeMapMethod<Object?, Object?>(method, arguments);
      return result?.map(
            (Object? key, Object? value) =>
                MapEntry(key.toString(), value as Object?),
          ) ??
          <String, Object?>{};
    } on PlatformException catch (error) {
      throw StorageAccessException(error.message ?? 'Storage access failed.');
    }
  }
}
