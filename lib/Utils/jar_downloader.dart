import 'dart:io';

typedef JarDownloadProgress = void Function(int receivedBytes, int? totalBytes);

class JarDownloadException implements Exception {
  const JarDownloadException(this.message);

  final String message;

  @override
  String toString() => 'JarDownloadException: $message';
}

class JarDownloadResult {
  const JarDownloadResult({
    required this.file,
    required this.receivedBytes,
    required this.totalBytes,
  });

  final File file;
  final int receivedBytes;
  final int? totalBytes;
}

class JarDownloader {
  const JarDownloader();

  Future<JarDownloadResult> downloadJar({
    required Uri sourceUrl,
    required String destinationPath,
    JarDownloadProgress? onProgress,
    Map<String, String>? headers,
  }) async {
    if (!sourceUrl.hasScheme || (sourceUrl.scheme != 'https' && sourceUrl.scheme != 'http')) {
      throw const JarDownloadException('Jar source URL must use http or https.');
    }

    if (!destinationPath.toLowerCase().endsWith('.jar')) {
      throw const JarDownloadException('Destination path must point to a .jar file.');
    }

    final HttpClient client = HttpClient();
    final File destinationFile = File(destinationPath);
    final Directory parentDirectory = destinationFile.parent;

    if (!await parentDirectory.exists()) {
      await parentDirectory.create(recursive: true);
    }

    IOSink? sink;

    try {
      final HttpClientRequest request = await client.getUrl(sourceUrl);
      headers?.forEach(request.headers.add);

      final HttpClientResponse response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw JarDownloadException(
          'Jar download failed with status code ${response.statusCode}.',
        );
      }

      sink = destinationFile.openWrite();
      final int? totalBytes = response.contentLength > 0 ? response.contentLength : null;
      int receivedBytes = 0;

      await for (final List<int> chunk in response) {
        receivedBytes += chunk.length;
        sink.add(chunk);
        onProgress?.call(receivedBytes, totalBytes);
      }

      await sink.flush();
      await sink.close();
      sink = null;

      return JarDownloadResult(
        file: destinationFile,
        receivedBytes: receivedBytes,
        totalBytes: totalBytes,
      );
    } catch (error) {
      await sink?.close();

      if (await destinationFile.exists()) {
        await destinationFile.delete();
      }

      if (error is JarDownloadException) {
        rethrow;
      }

      throw JarDownloadException('Unable to download jar: $error');
    } finally {
      client.close(force: true);
    }
  }
}
