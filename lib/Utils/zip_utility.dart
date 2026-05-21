import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';

class ZipUtility {
  /// Compresses a directory into a zip file on a separate Isolate.
  static Future<void> zipDirectory(Directory sourceDir, File zipFile) async {
    await compute(_zipDirectoryIsolate, _ZipParams(sourceDir.path, zipFile.path));
  }

  /// Extracts a zip file into a destination directory on a separate Isolate.
  static Future<void> unzipFile(File zipFile, Directory destinationDir) async {
    await compute(_unzipFileIsolate, _ZipParams(zipFile.path, destinationDir.path));
  }

  static void _zipDirectoryIsolate(_ZipParams params) {
    final encoder = ZipFileEncoder();
    encoder.create(params.zipPath);
    encoder.addDirectory(Directory(params.sourcePath));
    encoder.close();
  }

  static void _unzipFileIsolate(_ZipParams params) {
    final destinationDir = Directory(params.zipPath); // zipPath acts as destination here
    if (!destinationDir.existsSync()) {
      destinationDir.createSync(recursive: true);
    }

    final bytes = File(params.sourcePath).readAsBytesSync(); // sourcePath acts as zipPath here
    final archive = ZipDecoder().decodeBytes(bytes);

    for (final file in archive) {
      final filename = file.name;
      if (file.isFile) {
        final data = file.content as List<int>;
        final outFile = File('${destinationDir.path}/$filename');
        outFile.parent.createSync(recursive: true);
        outFile.writeAsBytesSync(data);
      } else {
        Directory('${destinationDir.path}/$filename').createSync(recursive: true);
      }
    }
  }
}

class _ZipParams {
  final String sourcePath;
  final String zipPath;

  _ZipParams(this.sourcePath, this.zipPath);
}
