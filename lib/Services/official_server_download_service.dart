import 'dart:convert';
import 'dart:io';

import 'package:bifrost/Components/add_server_window.dart';
import 'package:bifrost/Services/storage_access_service.dart';
import 'package:bifrost/Utils/jar_downloader.dart';
import 'package:bifrost/Services/server_storage_service.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
    this.storageAccessService = const StorageAccessService(),
  });

  static const String _paperUserAgent =
      'bifrost/1.0.0 (https://github.com/GopikChenth/Bifrost)';
  static const Duration _versionCacheTtl = Duration(days: 1);
  static const String _paperVersionsCacheKey = 'paper_stable_versions_cache';
  static const String _paperVersionsCacheTimestampKey =
      'paper_stable_versions_cache_timestamp';

  final JarDownloader jarDownloader;
  final StorageAccessService storageAccessService;

  Future<List<String>> getAvailableVersions(
    String serverType, {
    bool forceRefresh = false,
  }) async {
    switch (serverType.toLowerCase()) {
      case 'vanilla':
        return _getVanillaVersions();
      case 'paper':
        return _getPaperStableVersions(forceRefresh: forceRefresh);
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
          headers: artifact.projectName == 'paper'
              ? <String, String>{'User-Agent': _paperUserAgent}
              : null,
        );

        try {
          final Map<String, Object?> downloadResult = await storageAccessService
              .copyFileToDirectory(
                directoryUri: storage.jarsUri!,
                fileName: artifact.fileName,
                sourcePath: download.file.path,
              );
          final String destinationPath =
              (downloadResult['path'] as String?)?.trim().isNotEmpty == true
              ? downloadResult['path'] as String
              : path.join(storage.jarsDirectory.path, artifact.fileName);
          return OfficialServerDownloadResult(
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
        headers: artifact.projectName == 'paper'
            ? <String, String>{'User-Agent': _paperUserAgent}
            : null,
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

  Future<void> _deleteTemporaryFile(File file) async {
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // Cache cleanup is best-effort; a stale temp file must not fail creation.
    }
  }

  Future<OfficialServerArtifact> resolveArtifact(AddServerResult server) async {
    switch (server.serverType.toLowerCase()) {
      case 'vanilla':
        return _resolveVanillaArtifact(server.version);
      case 'paper':
        return _resolvePaperArtifact(server.version);
      default:
        throw OfficialServerDownloadException(
          '${server.serverType} downloads are not implemented yet.',
        );
    }
  }

  Future<OfficialServerArtifact> _resolveVanillaArtifact(
    String minecraftVersion,
  ) async {
    final List<Map<String, dynamic>> versions =
        await _getVanillaReleaseEntries();
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
  }

  Future<OfficialServerArtifact> _resolvePaperArtifact(
    String minecraftVersion,
  ) async {
    final List<dynamic> builds =
        await _getJson(
              Uri.parse(
                'https://fill.papermc.io/v3/projects/paper/versions/$minecraftVersion/builds',
              ),
              headers: <String, String>{'User-Agent': _paperUserAgent},
            )
            as List<dynamic>;

    final Map<String, dynamic>? stableBuild = builds
        .cast<Map<String, dynamic>?>()
        .firstWhere(
          (Map<String, dynamic>? build) => build?['channel'] == 'STABLE',
          orElse: () => null,
        );

    if (stableBuild == null) {
      final String? suggestedVersion =
          await _findLatestPaperVersionWithStableBuild();
      throw OfficialServerDownloadException(
        suggestedVersion == null
            ? 'No stable Paper build was found for Minecraft $minecraftVersion.'
            : 'No stable Paper build exists for Minecraft $minecraftVersion. Try Paper $suggestedVersion, or choose Vanilla if you need the exact Minecraft version.',
      );
    }

    final Map<String, dynamic>? downloads =
        stableBuild['downloads'] as Map<String, dynamic>?;
    final Map<String, dynamic>? serverDownload =
        downloads?['server:default'] as Map<String, dynamic>?;

    if (serverDownload == null) {
      throw OfficialServerDownloadException(
        'The official Paper API did not return a server download for Minecraft $minecraftVersion.',
      );
    }

    final String downloadUrl = serverDownload['url'] as String? ?? '';
    if (downloadUrl.isEmpty) {
      throw OfficialServerDownloadException(
        'The official Paper server download URL for $minecraftVersion was empty.',
      );
    }

    final int? buildId = stableBuild['id'] as int?;

    return OfficialServerArtifact(
      projectName: 'paper',
      minecraftVersion: minecraftVersion,
      fileName:
          'paper-$minecraftVersion${buildId != null ? '-$buildId' : ''}.jar',
      downloadUrl: Uri.parse(downloadUrl),
      sha1: serverDownload['sha256'] as String?,
      buildId: buildId,
      channel: stableBuild['channel'] as String?,
    );
  }

  Future<List<String>> _getVanillaVersions() async {
    final List<Map<String, dynamic>> entries =
        await _getVanillaReleaseEntries();
    return entries
        .map((Map<String, dynamic> entry) => entry['id'] as String)
        .toList();
  }

  Future<List<Map<String, dynamic>>> _getVanillaReleaseEntries() async {
    final Map<String, dynamic> manifest =
        await _getJson(
              Uri.parse(
                'https://piston-meta.mojang.com/mc/game/version_manifest_v2.json',
              ),
            )
            as Map<String, dynamic>;

    final List<dynamic> versions =
        manifest['versions'] as List<dynamic>? ?? <dynamic>[];

    return versions
        .whereType<Map<String, dynamic>>()
        .where((Map<String, dynamic> entry) => entry['type'] == 'release')
        .toList();
  }

  Future<List<String>> _getPaperStableVersions({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh) {
      final List<String>? cachedVersions = await _readCachedPaperVersions();
      if (cachedVersions != null) {
        return cachedVersions;
      }
    }

    final Map<String, dynamic> project =
        await _getJson(
              Uri.parse('https://fill.papermc.io/v3/projects/paper'),
              headers: <String, String>{'User-Agent': _paperUserAgent},
            )
            as Map<String, dynamic>;

    final Map<String, dynamic> versions =
        project['versions'] as Map<String, dynamic>? ?? <String, dynamic>{};
    final List<String> candidates = <String>[];

    for (final dynamic value in versions.values) {
      if (value is List<dynamic>) {
        for (final dynamic version in value) {
          if (version is String) {
            candidates.add(version);
          }
        }
      }
    }

    candidates.sort(_compareSemanticVersionsDescending);

    final List<String> stableVersions = <String>[];
    for (final String version in candidates) {
      final List<dynamic> builds =
          await _getJson(
                Uri.parse(
                  'https://fill.papermc.io/v3/projects/paper/versions/$version/builds',
                ),
                headers: <String, String>{'User-Agent': _paperUserAgent},
              )
              as List<dynamic>;

      final bool hasStable = builds.any(
        (dynamic build) =>
            build is Map<String, dynamic> && build['channel'] == 'STABLE',
      );

      if (hasStable) {
        stableVersions.add(version);
      }
    }

    await _writeCachedPaperVersions(stableVersions);
    return stableVersions;
  }

  Future<List<String>?> _readCachedPaperVersions() async {
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    final int? timestampMs = preferences.getInt(
      _paperVersionsCacheTimestampKey,
    );
    final String? encodedVersions = preferences.getString(
      _paperVersionsCacheKey,
    );

    if (timestampMs == null || encodedVersions == null) {
      return null;
    }

    final DateTime cachedAt = DateTime.fromMillisecondsSinceEpoch(timestampMs);
    if (DateTime.now().difference(cachedAt) > _versionCacheTtl) {
      return null;
    }

    try {
      final Object? decoded = jsonDecode(encodedVersions);
      if (decoded is List<dynamic>) {
        final List<String> versions = decoded.whereType<String>().toList();
        return versions.isEmpty ? null : versions;
      }
    } catch (_) {
      return null;
    }

    return null;
  }

  Future<void> _writeCachedPaperVersions(List<String> versions) async {
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    await preferences.setString(_paperVersionsCacheKey, jsonEncode(versions));
    await preferences.setInt(
      _paperVersionsCacheTimestampKey,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<String?> _findLatestPaperVersionWithStableBuild() async {
    final List<String> stableVersions = await _getPaperStableVersions();
    return stableVersions.isEmpty ? null : stableVersions.first;
  }

  int _compareSemanticVersionsDescending(String a, String b) {
    final List<int> aParts = a.split('.').map(int.parse).toList();
    final List<int> bParts = b.split('.').map(int.parse).toList();
    final int maxLength = aParts.length > bParts.length
        ? aParts.length
        : bParts.length;

    for (var index = 0; index < maxLength; index++) {
      final int aValue = index < aParts.length ? aParts[index] : 0;
      final int bValue = index < bParts.length ? bParts[index] : 0;
      if (aValue != bValue) {
        return bValue.compareTo(aValue);
      }
    }

    return 0;
  }

  Future<dynamic> _getJson(Uri url, {Map<String, String>? headers}) async {
    final HttpClient client = HttpClient();

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
      client.close(force: true);
    }
  }
}
