import 'dart:async';
import 'dart:io';
import 'package:googleapis/drive/v3.dart' as drive;

class GoogleDriveUser {
  final String email;
  final String? displayName;
  final String? photoUrl;

  GoogleDriveUser({
    required this.email,
    this.displayName,
    this.photoUrl,
  });
}

class GoogleDriveSyncService {
  GoogleDriveSyncService._internal();
  
  static final GoogleDriveSyncService instance = GoogleDriveSyncService._internal();

  GoogleDriveUser? get currentUser => null;
  
  Stream<GoogleDriveUser?> get onCurrentUserChanged => const Stream<GoogleDriveUser?>.empty();

  Future<GoogleDriveUser?> signIn() async {
    throw Exception('Cloud Sync is not available in the F-Droid FOSS build of Bifrost.');
  }

  Future<GoogleDriveUser?> signInSilently() async {
    return null;
  }

  Future<void> signOut() async {}

  Future<bool> ensureWriteAccess() async => false;

  Future<String> uploadWorldSyncFile({
    required String serverName,
    required File zipFile,
    required String localWorldPath,
    required String version,
    required String type,
    required String memoryLabel,
    String? existingFileId,
  }) async {
    throw Exception('Cloud Sync is not available in this FOSS build.');
  }

  Future<void> shareWorldFile({
    required String fileId,
    required String friendEmail,
  }) async {
    throw Exception('Cloud Sync is not available in this FOSS build.');
  }

  Future<List<drive.File>> listAvailableWorldSyncFiles() async => [];

  Future<void> downloadWorldSyncFile({
    required String fileId,
    required File destinationFile,
  }) async {
    throw Exception('Cloud Sync is not available in this FOSS build.');
  }

  Future<List<drive.Permission>> getFilePermissions(String fileId) async => [];

  Future<void> revokeSharingPermission({
    required String fileId,
    required String permissionId,
  }) async {
    throw Exception('Cloud Sync is not available in this FOSS build.');
  }

  Future<String?> getFileOwnerEmail(String fileId) async => null;

  Future<drive.File?> getSyncFileById(String fileId) async => null;

  Future<drive.File?> getSyncFileByName(String filename) async => null;
}
