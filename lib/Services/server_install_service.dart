import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

class ServerInstallException implements Exception {
  const ServerInstallException(this.message);

  final String message;

  @override
  String toString() => 'ServerInstallException: $message';
}

class PreparedServerInstall {
  const PreparedServerInstall({
    required this.serverName,
    required this.serverPath,
    required this.serverType,
    required this.minecraftVersion,
    required this.allocatedRam,
    required this.jarFile,
    required this.eulaFile,
    required this.metadataFile,
  });

  final String serverName;
  final String serverPath;
  final String serverType;
  final String minecraftVersion;
  final String allocatedRam;
  final File jarFile;
  final File eulaFile;
  final File metadataFile;
}

class ServerInstallService {
  const ServerInstallService();

  Future<PreparedServerInstall> prepareServer({
    required String serverPath,
  }) async {
    final Directory serverDirectory = Directory(serverPath);
    final File metadataFile = File(
      path.join(serverDirectory.path, 'bifrost_server.json'),
    );

    try {
      if (!await serverDirectory.exists()) {
        throw const ServerInstallException(
          'The selected server folder does not exist.',
        );
      }

      if (!await metadataFile.exists()) {
        throw ServerInstallException(
          'Missing bifrost_server.json in ${serverDirectory.path}.',
        );
      }

      final Map<String, dynamic> metadata =
          jsonDecode(await metadataFile.readAsString()) as Map<String, dynamic>;

      final String serverName = (metadata['name'] as String?)?.trim() ?? '';
      final String serverType = (metadata['type'] as String?)?.trim() ?? '';
      final String minecraftVersion =
          (metadata['version'] as String?)?.trim() ?? '';
      final String allocatedRam =
          (metadata['allocatedRam'] as String?)?.trim() ?? '1.0 GB';

      if (serverName.isEmpty || serverType.isEmpty || minecraftVersion.isEmpty) {
        throw const ServerInstallException(
          'Server metadata is incomplete. Name, type, and version are required.',
        );
      }

      final File jarFile = await _resolveJarFile(
        serverDirectory: serverDirectory,
        metadata: metadata,
      );
      final File eulaFile = File(path.join(serverDirectory.path, 'eula.txt'));

      await eulaFile.writeAsString('eula=true\n', flush: true);

      return PreparedServerInstall(
        serverName: serverName,
        serverPath: serverDirectory.path,
        serverType: serverType,
        minecraftVersion: minecraftVersion,
        allocatedRam: allocatedRam,
        jarFile: jarFile,
        eulaFile: eulaFile,
        metadataFile: metadataFile,
      );
    } on FileSystemException catch (error) {
      throw ServerInstallException(
        'Unable to prepare ${serverDirectory.path}: ${error.message}',
      );
    } on FormatException catch (_) {
      throw ServerInstallException(
        'bifrost_server.json is not valid JSON for ${serverDirectory.path}.',
      );
    } on ServerInstallException {
      rethrow;
    } catch (error) {
      throw ServerInstallException('Unable to prepare the server: $error');
    }
  }

  Future<File> _resolveJarFile({
    required Directory serverDirectory,
    required Map<String, dynamic> metadata,
  }) async {
    final Map<String, dynamic>? downloadMetadata =
        metadata['download'] as Map<String, dynamic>?;
    final String? downloadedPath = downloadMetadata?['path'] as String?;

    if (downloadedPath != null && downloadedPath.trim().isNotEmpty) {
      final File jarFile = File(downloadedPath);
      if (await jarFile.exists()) {
        return jarFile;
      }
    }

    final Directory jarsDirectory = Directory(
      path.join(serverDirectory.path, 'jars'),
    );

    if (!await jarsDirectory.exists()) {
      throw ServerInstallException(
        'Missing jars folder in ${serverDirectory.path}.',
      );
    }

    final List<FileSystemEntity> jarFiles = await jarsDirectory
        .list()
        .where((FileSystemEntity entity) {
          return entity is File && entity.path.toLowerCase().endsWith('.jar');
        })
        .toList();

    if (jarFiles.isEmpty) {
      throw ServerInstallException(
        'No runnable server jar was found in ${jarsDirectory.path}.',
      );
    }

    jarFiles.sort((FileSystemEntity a, FileSystemEntity b) {
      return b.statSync().modified.compareTo(a.statSync().modified);
    });

    return jarFiles.first as File;
  }
}
