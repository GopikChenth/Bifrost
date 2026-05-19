import 'dart:convert';
import 'dart:io';

import 'package:bifrost/Components/add_server_window.dart';
import 'package:bifrost/Utils/jar_downloader.dart';
import 'package:bifrost/Services/server_storage_service.dart';
import 'package:path/path.dart' as path;

class OfficialServerDownloadException implements Exception {
  const OfficialServerDownloadException(this.message);

  final String message;

  @override
  String toString() => 'OfficialServerDownloadException: $message';
}

class OfficialServerArtifact {
  const OfficialServerArtifact({
    required this.projectName,
    required this.minecraftVersion,
    required this.fileName,
    required this.downloadUrl,
    this.sha1,
    this.buildId,
    this.channel,
  });

  final String projectName;
  final String minecraftVersion;
  final String fileName;
  final Uri downloadUrl;
  final String? sha1;
  final int? buildId;
  final String? channel;
}

class OfficialServerDownloadResult {
  const OfficialServerDownloadResult({
    required this.artifact,
    required this.download,
    required this.destinationFile,
  });

  final OfficialServerArtifact artifact;
  final JarDownloadResult download;
  final File destinationFile;
}

class OfficialServerDownloadService {
  const OfficialServerDownloadService({
    this.jarDownloader = const JarDownloader(),
  });

  final JarDownloader jarDownloader;

  Future<List<String>> getAvailableVersions(
    String serverType, {
    bool forceRefresh = false,
  }) async {
    switch (serverType.toLowerCase()) {
      case 'vanilla':
        return _getVanillaVersions();
      default:
        return <String>[];
    }
  }

  Future<OfficialServerDownloadResult> downloadSelectedServer({
    required AddServerResult server,
    required ServerStorageResult storage,
    JarDownloadProgress? onProgress,
  }) async {
    final OfficialServerArtifact artifact = await resolveArtifact(server);
    return downloadResolvedArtifact(
      artifact: artifact,
      storage: storage,
      onProgress: onProgress,
    );
  }

  Future<OfficialServerDownloadResult> downloadResolvedArtifact({
    required OfficialServerArtifact artifact,
    required ServerStorageResult storage,
    JarDownloadProgress? onProgress,
  }) async {
    try {
      final String destinationPath = path.join(
        storage.jarsDirectory.path,
        artifact.fileName,
      );

      final JarDownloadResult download = await jarDownloader.downloadJar(
        sourceUrl: artifact.downloadUrl,
        destinationPath: destinationPath,
        onProgress: onProgress,
      );

      return OfficialServerDownloadResult(
        artifact: artifact,
        download: download,
        destinationFile: File(destinationPath),
      );
    } on JarDownloadException catch (error) {
      throw OfficialServerDownloadException(error.message);
    }
  }


  Future<OfficialServerArtifact> resolveArtifact(AddServerResult server) async {
    switch (server.serverType.toLowerCase()) {
      case 'vanilla':
        return _resolveVanillaArtifact(server.version);
      default:
        throw OfficialServerDownloadException(
          '${server.serverType} downloads are not implemented yet.',
        );
    }
  }

  Future<OfficialServerArtifact> _resolveVanillaArtifact(
    String minecraftVersion,
  ) async {
    final HttpClient client = HttpClient();
    try {
      final List<Map<String, dynamic>> versions =
          await _getVanillaReleaseEntries(sharedClient: client);
      final Map<String, dynamic>? versionEntry = versions
          .cast<Map<String, dynamic>?>()
          .firstWhere(
            (Map<String, dynamic>? entry) => entry?['id'] == minecraftVersion,
            orElse: () => null,
          );

      if (versionEntry == null) {
        throw OfficialServerDownloadException(
          'Minecraft version $minecraftVersion was not found in the official Mojang manifest.',
        );
      }

      final String versionUrl = versionEntry['url'] as String? ?? '';
      if (versionUrl.isEmpty) {
        throw OfficialServerDownloadException(
          'The official Mojang manifest did not provide a version details URL for $minecraftVersion.',
        );
      }

      final Map<String, dynamic> versionDetails = await _getJson(
        Uri.parse(versionUrl),
        sharedClient: client,
      );
      final Map<String, dynamic>? serverDownload =
          (versionDetails['downloads'] as Map<String, dynamic>?)?['server']
              as Map<String, dynamic>?;

      if (serverDownload == null) {
        throw OfficialServerDownloadException(
          'The official Mojang version data does not contain a server download for $minecraftVersion.',
        );
      }

      final String downloadUrl = serverDownload['url'] as String? ?? '';
      if (downloadUrl.isEmpty) {
        throw OfficialServerDownloadException(
          'The official Mojang server download URL for $minecraftVersion was empty.',
        );
      }

      return OfficialServerArtifact(
        projectName: 'vanilla',
        minecraftVersion: minecraftVersion,
        fileName: 'server.jar',
        downloadUrl: Uri.parse(downloadUrl),
        sha1: serverDownload['sha1'] as String?,
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<List<String>> _getVanillaVersions() async {
    final List<Map<String, dynamic>> entries =
        await _getVanillaReleaseEntries();
    return entries
        .map((Map<String, dynamic> entry) => entry['id'] as String)
        .toList();
  }

  Future<List<Map<String, dynamic>>> _getVanillaReleaseEntries({
    HttpClient? sharedClient,
  }) async {
    final Map<String, dynamic> manifest =
        await _getJson(
              Uri.parse(
                'https://piston-meta.mojang.com/mc/game/version_manifest_v2.json',
              ),
              sharedClient: sharedClient,
            )
            as Map<String, dynamic>;

    final List<dynamic> versions =
        manifest['versions'] as List<dynamic>? ?? <dynamic>[];

    return versions
        .whereType<Map<String, dynamic>>()
        .where((Map<String, dynamic> entry) => entry['type'] == 'release')
        .toList();
  }

  Future<dynamic> _getJson(
    Uri url, {
    Map<String, String>? headers,
    HttpClient? sharedClient,
  }) async {
    final HttpClient client = sharedClient ?? HttpClient();

    try {
      final HttpClientRequest request = await client.getUrl(url);
      headers?.forEach(request.headers.add);
      final HttpClientResponse response = await request.close();

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw OfficialServerDownloadException(
          'Official download lookup failed with status code ${response.statusCode} for $url.',
        );
      }

      final String body = await utf8.decoder.bind(response).join();
      return jsonDecode(body);
    } on OfficialServerDownloadException {
      rethrow;
    } catch (error) {
      throw OfficialServerDownloadException(
        'Unable to fetch official download metadata from $url: $error',
      );
    } finally {
      if (sharedClient == null) {
        client.close(force: true);
      }
    }
  }
}
