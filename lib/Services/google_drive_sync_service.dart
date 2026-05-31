import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';

class GoogleDriveSyncService {
  GoogleDriveSyncService._internal();
  
  static final GoogleDriveSyncService instance = GoogleDriveSyncService._internal();

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: <String>[
      drive.DriveApi.driveFileScope,
      drive.DriveApi.driveReadonlyScope,
    ],
  );

  GoogleSignInAccount? get currentUser => _googleSignIn.currentUser;
  
  Stream<GoogleSignInAccount?> get onCurrentUserChanged => _googleSignIn.onCurrentUserChanged;

  Future<GoogleSignInAccount?> signIn() async {
    try {
      return await _googleSignIn.signIn();
    } catch (e) {
      rethrow;
    }
  }

  Future<GoogleSignInAccount?> signInSilently() async {
    try {
      return await _googleSignIn.signInSilently();
    } catch (e) {
      return null;
    }
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();
  }

  Future<drive.DriveApi?> _getDriveApi() async {
    final client = await _googleSignIn.authenticatedClient();
    if (client == null) {
      return null;
    }
    return drive.DriveApi(client);
  }

  /// Checks if the app has write access (drive.file scope) and requests it if not.
  Future<bool> ensureWriteAccess() async {
    final user = _googleSignIn.currentUser;
    if (user == null) return false;

    try {
      final hasAccess = await _googleSignIn.canAccessScopes(<String>[drive.DriveApi.driveFileScope]);
      if (!hasAccess) {
        final granted = await _googleSignIn.requestScopes(<String>[drive.DriveApi.driveFileScope]);
        return granted;
      }
      return true;
    } catch (e) {
      // Fallback for platforms/versions where canAccessScopes throws an UnimplementedError or other exception
      try {
        final granted = await _googleSignIn.requestScopes(<String>[drive.DriveApi.driveFileScope]);
        return granted;
      } catch (_) {
        return false;
      }
    }
  }

  /// Uploads or updates the world zip file on Google Drive.
  /// Returns the Google Drive file ID.
  Future<String> uploadWorldSyncFile({
    required String serverName,
    required File zipFile,
    required String localWorldPath,
    required String version,
    required String type,
    required String memoryLabel,
    String? existingFileId,
  }) async {
    final hasWriteAccess = await ensureWriteAccess();
    if (!hasWriteAccess) {
      throw Exception('Write permission to Google Drive was not granted. Please allow the app to create/update files when prompted.');
    }

    final driveApi = await _getDriveApi();
    if (driveApi == null) {
      throw Exception('User is not authenticated with Google.');
    }

    final filename = 'bifrost_sync_${serverName.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_')}.zip';

    String? fileId = existingFileId;

    if (fileId == null) {
      // Search for existing file owned by the current user
      final filesList = await driveApi.files.list(
        q: "name = '$filename' and 'me' in owners and trashed = false",
        spaces: 'drive',
        $fields: 'files(id, name)',
      );
      if (filesList.files != null && filesList.files!.isNotEmpty) {
        fileId = filesList.files!.first.id;
      }
    }

    final media = drive.Media(
      zipFile.openRead(),
      zipFile.lengthSync(),
    );

    final metadataJson = jsonEncode({
      'version': version,
      'type': type,
      'memoryLabel': memoryLabel,
      'serverName': serverName,
    });
    final descriptionText = 'Bifrost Minecraft World Sync Backup. Path: $localWorldPath. Synced at: ${DateTime.now().toIso8601String()}\nBifrostMetadata:$metadataJson';

    if (fileId != null) {
      
      final updatedFile = drive.File()
        ..description = descriptionText;

      final result = await driveApi.files.update(
        updatedFile,
        fileId,
        uploadMedia: media,
        $fields: 'id',
      );
      return result.id!;
    } else {
      final newFile = drive.File()
        ..name = filename
        ..description = descriptionText
        ..mimeType = 'application/zip';

      final result = await driveApi.files.create(
        newFile,
        uploadMedia: media,
        $fields: 'id',
      );
      return result.id!;
    }
  }

  /// Shares a file with a friend's Gmail, granting write access.
  Future<void> shareWorldFile({
    required String fileId,
    required String friendEmail,
  }) async {
    final driveApi = await _getDriveApi();
    if (driveApi == null) {
      throw Exception('User is not authenticated with Google.');
    }

    final permission = drive.Permission()
      ..type = 'user'
      ..role = 'writer' // Grant writer so friend can also update and sync changes back!
      ..emailAddress = friendEmail;

    await driveApi.permissions.create(
      permission,
      fileId,
      sendNotificationEmail: true,
    );
  }

  /// Lists all world sync files owned by or shared with the user.
  Future<List<drive.File>> listAvailableWorldSyncFiles() async {
    final driveApi = await _getDriveApi();
    if (driveApi == null) {
      return [];
    }

    final response = await driveApi.files.list(
      q: "name contains 'bifrost_sync_' and mimeType = 'application/zip' and (sharedWithMe = true or 'me' in owners) and trashed = false",
      spaces: 'drive',
      supportsAllDrives: true,
      includeItemsFromAllDrives: true,
      $fields: 'files(id, name, owners(displayName, emailAddress), modifiedTime, size, description)',
    );

    return response.files ?? [];
  }

  /// Downloads a world sync file by ID from Google Drive.
  Future<void> downloadWorldSyncFile({
    required String fileId,
    required File destinationFile,
  }) async {
    final driveApi = await _getDriveApi();
    if (driveApi == null) {
      throw Exception('User is not authenticated with Google.');
    }

    final drive.Media media = await driveApi.files.get(
      fileId,
      downloadOptions: drive.DownloadOptions.fullMedia,
    ) as drive.Media;

    if (destinationFile.existsSync()) {
      destinationFile.deleteSync();
    }
    destinationFile.createSync(recursive: true);

    final sink = destinationFile.openWrite();
    await media.stream.pipe(sink);
  }

  /// Fetches permissions for a file to show who it is shared with.
  Future<List<drive.Permission>> getFilePermissions(String fileId) async {
    final driveApi = await _getDriveApi();
    if (driveApi == null) {
      return [];
    }

    final response = await driveApi.permissions.list(
      fileId,
      $fields: 'permissions(id, emailAddress, role, displayName)',
    );
    return response.permissions ?? [];
  }

  /// Deletes a sharing permission.
  Future<void> revokeSharingPermission({
    required String fileId,
    required String permissionId,
  }) async {
    final driveApi = await _getDriveApi();
    if (driveApi == null) {
      throw Exception('User is not authenticated with Google.');
    }

    await driveApi.permissions.delete(fileId, permissionId);
  }

  /// Fetches the email address of the file's owner.
  Future<String?> getFileOwnerEmail(String fileId) async {
    final driveApi = await _getDriveApi();
    if (driveApi == null) {
      return null;
    }
    try {
      final file = await driveApi.files.get(
        fileId,
        $fields: 'owners(emailAddress)',
      ) as drive.File;
      return file.owners?.first.emailAddress;
    } catch (_) {
      return null;
    }
  }

  /// Fetches a single sync file's metadata by its file ID.
  Future<drive.File?> getSyncFileById(String fileId) async {
    final driveApi = await _getDriveApi();
    if (driveApi == null) {
      return null;
    }
    try {
      final file = await driveApi.files.get(
        fileId,
        $fields: 'id, name, owners(displayName, emailAddress), modifiedTime, size, description',
      ) as drive.File;
      return file;
    } catch (_) {
      return null;
    }
  }

  /// Searches for a single sync file matching the exact filename (escaped and limited to 1 result).
  Future<drive.File?> getSyncFileByName(String filename) async {
    final driveApi = await _getDriveApi();
    if (driveApi == null) {
      return null;
    }
    try {
      final String escaped = filename.replaceAll('\\', '\\\\').replaceAll("'", "\\'");
      final response = await driveApi.files.list(
        q: "name = '$escaped' and mimeType = 'application/zip' and (sharedWithMe = true or 'me' in owners) and trashed = false",
        spaces: 'drive',
        supportsAllDrives: true,
        includeItemsFromAllDrives: true,
        $fields: 'files(id, name, owners(displayName, emailAddress), modifiedTime, size, description)',
        pageSize: 1,
      );
      if (response.files != null && response.files!.isNotEmpty) {
        return response.files!.first;
      }
    } catch (_) {
      return null;
    }
    return null;
  }
}

