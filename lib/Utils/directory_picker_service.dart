import 'package:flutter/services.dart';

class PickedDirectory {
  const PickedDirectory({
    required this.path,
    required this.uri,
  });

  final String path;
  final String uri;
}

class DirectoryPickerService {
  const DirectoryPickerService();

  static const MethodChannel _channel = MethodChannel(
    'bifrost/storage_access',
  );

  Future<PickedDirectory?> pickDirectory() async {
    final Map<Object?, Object?>? result =
        await _channel.invokeMapMethod<Object?, Object?>('pickDirectory');
    if (result == null) {
      return null;
    }

    final String path = (result['path'] as String? ?? '').trim();
    final String uri = (result['uri'] as String? ?? '').trim();
    if (path.isEmpty || uri.isEmpty) {
      return null;
    }

    return PickedDirectory(path: path, uri: uri);
  }
}
