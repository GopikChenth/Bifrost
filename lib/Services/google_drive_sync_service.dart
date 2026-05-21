import 'dart:async';
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

  /// Uploads or updates the world zip file on Google Drive.
  /// Returns the Google Drive file ID.
  Future<String> uploadWorldSyncFile({
    required String serverName,
    required File zipFile,
    required String localWorldPath,
  }) async {
    final driveApi = await _getDriveApi();
    if (driveApi == null) {
      throw Exception('User is not authenticated with Google.');
    }

    final filename = 'bifrost_sync_${serverName.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_')}.zip';

    // Search for existing file
    final filesList = await driveApi.files.list(
      q: "name = '$filename' and trashed = false",
      spaces: 'drive',
      $fields: 'files(id, name)',
    );

    final media = drive.Media(
      zipFile.openRead(),
      zipFile.lengthSync(),
    );

    if (filesList.files != null && filesList.files!.isNotEmpty) {
      final existingFile = filesList.files!.first;
      final fileId = existingFile.id!;
      
      final updatedFile = drive.File()
        ..description = 'Bifrost Minecraft World Sync Backup. Path: $localWorldPath. Synced at: ${DateTime.now().toIso8601String()}';

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
        ..description = 'Bifrost Minecraft World Sync Backup. Path: $localWorldPath. Synced at: ${DateTime.now().toIso8601String()}'
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
      q: "name contains 'bifrost_sync_' and mimeType = 'application/zip' and trashed = false",
      spaces: 'drive',
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
}
