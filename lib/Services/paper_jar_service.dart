import 'dart:convert';
import 'dart:io';

import 'package:bifrost/Services/server_storage_service.dart';
import 'package:bifrost/Services/storage_access_service.dart';
import 'package:bifrost/Utils/jar_downloader.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

class PaperJarDownloadException implements Exception {
  const PaperJarDownloadException(this.message);

  final String message;

  @override
  String toString() => 'PaperJarDownloadException: $message';
}

class PaperJarArtifact {
  const PaperJarArtifact({
    required this.minecraftVersion,
    required this.fileName,
    required this.downloadUrl,
    this.sha256,
    this.buildId,
    this.channel,
  });

  final String minecraftVersion;
  final String fileName;
  final Uri downloadUrl;
  final String? sha256;
  final int? buildId;
  final String? channel;
}

class PaperJarDownloadResult {
  const PaperJarDownloadResult({
    required this.artifact,
    required this.download,
    required this.destinationFile,
  });

  final PaperJarArtifact artifact;
  final JarDownloadResult download;
  final File destinationFile;
}

class PaperJarService {
  const PaperJarService({
    this.jarDownloader = const JarDownloader(),
    this.storageAccessService = const StorageAccessService(),
  });

  static const String _project = 'paper';
  static const String _baseUrl = 'https://fill.papermc.io/v3';
  static const String _userAgent =
      'bifrost/1.0.0 (https://github.com/GopikChenth/Bifrost)';

  final JarDownloader jarDownloader;
  final StorageAccessService storageAccessService;

  Future<List<String>> getAvailableVersions() async {
    final Map<String, dynamic> project = await _getJson(
      Uri.parse('$_baseUrl/projects/$_project'),
    ) as Map<String, dynamic>;
    final Map<String, dynamic> versions =
        project['versions'] as Map<String, dynamic>? ?? <String, dynamic>{};
    final List<String> allVersions = <String>[];

    for (final dynamic value in versions.values) {
      if (value is List<dynamic>) {
        allVersions.addAll(value.whereType<String>());
      }
    }

    allVersions.sort(_compareMinecraftVersionsDescending);
    return allVersions;
  }

  Future<PaperJarArtifact> resolveArtifact(String minecraftVersion) async {
    final List<dynamic> builds = _extractBuilds(await _getJson(
      Uri.parse('$_baseUrl/projects/$_project/versions/$minecraftVersion/builds'),
    ));

    final List<Map<String, dynamic>> stableBuilds = builds
        .whereType<Map<String, dynamic>>()
        .where((Map<String, dynamic> build) {
          return (build['channel'] as String?)?.toUpperCase() == 'STABLE';
        })
        .toList();

    if (stableBuilds.isEmpty) {
      throw PaperJarDownloadException(
        'No stable Paper build exists for Minecraft $minecraftVersion.',
      );
    }

    stableBuilds.sort((Map<String, dynamic> a, Map<String, dynamic> b) {
      final int aId = _buildId(a);
      final int bId = _buildId(b);
      return bId.compareTo(aId);
    });

    final Map<String, dynamic> build = stableBuilds.first;
    final Map<String, dynamic>? downloads =
        build['downloads'] as Map<String, dynamic>?;
    final Map<String, dynamic>? serverDownload =
        downloads?['server:default'] as Map<String, dynamic>?;
    final String url = serverDownload?['url'] as String? ?? '';

    if (url.trim().isEmpty) {
      throw PaperJarDownloadException(
        'Paper did not return a server download URL for Minecraft $minecraftVersion.',
      );
    }

    final int buildId = _buildId(build);
    return PaperJarArtifact(
      minecraftVersion: minecraftVersion,
      fileName: buildId > 0
          ? 'paper-$minecraftVersion-$buildId.jar'
          : 'paper-$minecraftVersion.jar',
      downloadUrl: Uri.parse(url),
      sha256: serverDownload?['sha256'] as String?,
      buildId: buildId > 0 ? buildId : null,
      channel: build['channel'] as String?,
    );
  }

  Future<PaperJarDownloadResult> downloadResolvedArtifact({
    required PaperJarArtifact artifact,
    required ServerStorageResult storage,
    JarDownloadProgress? onProgress,
  }) async {
    try {
      if (storage.jarsUri != null) {
        final Directory temporaryDirectory = await getTemporaryDirectory();
        final String temporaryPath = path.join(
          temporaryDirectory.path,
          'bifrost-downloads',
          '${DateTime.now().microsecondsSinceEpoch}-${artifact.fileName}',
        );
        final JarDownloadResult download = await jarDownloader.downloadJar(
          sourceUrl: artifact.downloadUrl,
          destinationPath: temporaryPath,
          onProgress: onProgress,
          headers: <String, String>{'User-Agent': _userAgent},
        );

        try {
          final Map<String, Object?> copyResult = await storageAccessService
              .copyFileToDirectory(
                directoryUri: storage.jarsUri!,
                fileName: artifact.fileName,
                sourcePath: download.file.path,
              );
          final String destinationPath =
              (copyResult['path'] as String?)?.trim().isNotEmpty == true
              ? copyResult['path'] as String
              : path.join(storage.jarsDirectory.path, artifact.fileName);
          return PaperJarDownloadResult(
            artifact: artifact,
            download: JarDownloadResult(
              file: File(destinationPath),
              receivedBytes: download.receivedBytes,
              totalBytes: download.totalBytes,
            ),
            destinationFile: File(destinationPath),
          );
        } finally {
          await _deleteTemporaryFile(download.file);
        }
      }

      final String destinationPath = path.join(
        storage.jarsDirectory.path,
        artifact.fileName,
      );
      final JarDownloadResult download = await jarDownloader.downloadJar(
        sourceUrl: artifact.downloadUrl,
        destinationPath: destinationPath,
        onProgress: onProgress,
        headers: <String, String>{'User-Agent': _userAgent},
      );
      return PaperJarDownloadResult(
        artifact: artifact,
        download: download,
        destinationFile: File(destinationPath),
      );
    } on JarDownloadException catch (error) {
      throw PaperJarDownloadException(error.message);
    }
  }

  int _buildId(Map<String, dynamic> build) {
    final Object? id = build['id'] ?? build['number'];
    if (id is int) {
      return id;
    }
    if (id is num) {
      return id.toInt();
    }
    return int.tryParse(id?.toString() ?? '') ?? 0;
  }

  List<dynamic> _extractBuilds(dynamic response) {
    if (response is List<dynamic>) {
      return response;
    }
    if (response is Map<String, dynamic>) {
      final dynamic builds = response['builds'];
      if (builds is List<dynamic>) {
        return builds;
      }
    }

    throw const PaperJarDownloadException(
      'Paper returned an unexpected builds response.',
    );
  }

  int _compareMinecraftVersionsDescending(String a, String b) {
    final List<int> aParts = _numericParts(a);
    final List<int> bParts = _numericParts(b);
    final int maxLength = aParts.length > bParts.length ? aParts.length : bParts.length;
    for (var index = 0; index < maxLength; index++) {
      final int aValue = index < aParts.length ? aParts[index] : 0;
      final int bValue = index < bParts.length ? bParts[index] : 0;
      if (aValue != bValue) {
        return bValue.compareTo(aValue);
      }
    }
    return b.compareTo(a);
  }

  List<int> _numericParts(String version) {
    return RegExp(r'\d+')
        .allMatches(version)
        .map((RegExpMatch match) => int.tryParse(match.group(0) ?? '') ?? 0)
        .toList();
  }

  Future<void> _deleteTemporaryFile(File file) async {
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  Future<dynamic> _getJson(Uri url) async {
    final HttpClient client = HttpClient();
    try {
      final HttpClientRequest request = await client.getUrl(url);
      request.headers.add('User-Agent', _userAgent);
      final HttpClientResponse response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw PaperJarDownloadException(
          'Paper lookup failed with status ${response.statusCode} for $url.',
        );
      }
      final String body = await utf8.decoder.bind(response).join();
      return jsonDecode(body);
    } on PaperJarDownloadException {
      rethrow;
    } catch (error) {
      throw PaperJarDownloadException(
        'Unable to fetch Paper download metadata from $url: $error',
      );
    } finally {
      client.close(force: true);
    }
  }
}
