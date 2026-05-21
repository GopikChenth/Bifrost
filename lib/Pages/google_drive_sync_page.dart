import 'package:flutter/material.dart';
import 'package:bifrost/Models/bifrost_server.dart';
import 'package:bifrost/Services/server_manager_service.dart';
import 'package:bifrost/Services/google_drive_sync_service.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:shared_preferences/shared_preferences.dart';

class GoogleDriveSyncPage extends StatefulWidget {
  const GoogleDriveSyncPage({
    super.key,
    required this.serverPath,
    required this.serverManager,
  });

  final String serverPath;
  final ServerManagerService serverManager;

  @override
  State<GoogleDriveSyncPage> createState() => _GoogleDriveSyncPageState();
}

class _GoogleDriveSyncPageState extends State<GoogleDriveSyncPage> {
  final GoogleDriveSyncService _driveService = GoogleDriveSyncService.instance;
  final TextEditingController _emailController = TextEditingController();

  bool _isAutoSyncEnabled = false;
  bool _isLoadingDriveFiles = false;
  bool _isSharing = false;
  bool _isRevoking = false;
  bool _isPerformingAction = false;
  String? _statusMessage;
  List<drive.File> _sharedWorlds = <drive.File>[];
  List<drive.Permission> _currentPermissions = <drive.Permission>[];
  String? _currentFileId;

  @override
  void initState() {
    super.initState();
    widget.serverManager.addListener(_onServerManagerChange);
    _driveService.onCurrentUserChanged.listen((user) {
      if (mounted) {
        setState(() {});
        if (user != null) {
          _loadDriveData();
        }
      }
    });
    _loadSettings();
    if (_driveService.currentUser != null) {
      _loadDriveData();
    } else {
      _driveService.signInSilently().then((user) {
        if (user != null && mounted) {
          _loadDriveData();
        }
      });
    }
  }

  @override
  void dispose() {
    widget.serverManager.removeListener(_onServerManagerChange);
    _emailController.dispose();
    super.dispose();
  }

  void _onServerManagerChange() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isAutoSyncEnabled = prefs.getBool('gdrive_autosync_${widget.serverPath}') ?? false;
    });
  }

  Future<void> _toggleAutoSync(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('gdrive_autosync_${widget.serverPath}', value);
    if (!mounted) return;
    setState(() {
      _isAutoSyncEnabled = value;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          value
              ? 'Auto-Sync enabled. World will sync after 5 minutes of playtime.'
              : 'Auto-Sync disabled.',
        ),
      ),
    );
  }

  Future<void> _loadDriveData() async {
    if (_isLoadingDriveFiles) return;
    setState(() {
      _isLoadingDriveFiles = true;
      _statusMessage = null;
    });

    try {
      final files = await _driveService.listAvailableWorldSyncFiles();
      final BifrostServer? server = widget.serverManager.serverByPath(widget.serverPath);
      
      String? matchedFileId;
      if (server != null) {
        final expectedName = 'bifrost_sync_${server.name.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_')}.zip';
        for (final file in files) {
          if (file.name == expectedName) {
            matchedFileId = file.id;
            break;
          }
        }
      }

      List<drive.Permission> perms = <drive.Permission>[];
      if (matchedFileId != null) {
        perms = await _driveService.getFilePermissions(matchedFileId);
      }

      if (mounted) {
        setState(() {
          _sharedWorlds = files;
          _currentFileId = matchedFileId;
          _currentPermissions = perms.where((p) => p.role != 'owner').toList();
          _isLoadingDriveFiles = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingDriveFiles = false;
          _statusMessage = 'Error loading Google Drive data: $e';
        });
      }
    }
  }

  Future<void> _signIn() async {
    try {
      await _driveService.signIn();
      await _loadDriveData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to sign in: $e')),
      );
    }
  }

  Future<void> _signOut() async {
    await _driveService.signOut();
    setState(() {
      _sharedWorlds = <drive.File>[];
      _currentPermissions = <drive.Permission>[];
      _currentFileId = null;
    });
  }

  Future<void> _manualSync(BifrostServer server) async {
    setState(() {
      _isPerformingAction = true;
    });
    final result = await widget.serverManager.syncWorldToGoogleDrive(server);
    if (!mounted) return;
    setState(() {
      _isPerformingAction = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result ?? 'Sync completed.')),
    );
    _loadDriveData();
  }

  Future<void> _shareWorld() async {
    final email = _emailController.text.trim();
    final fileId = _currentFileId;
    if (email.isEmpty || fileId == null) return;

    setState(() {
      _isSharing = true;
    });

    try {
      await _driveService.shareWorldFile(fileId: fileId, friendEmail: email);
      if (!mounted) return;
      _emailController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Successfully shared world with $email')),
      );
      await _loadDriveData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to share: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSharing = false;
        });
      }
    }
  }

  Future<void> _revokePermission(String permissionId, String email) async {
    final fileId = _currentFileId;
    if (fileId == null) return;

    setState(() {
      _isRevoking = true;
    });

    try {
      await _driveService.revokeSharingPermission(fileId: fileId, permissionId: permissionId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Access revoked for $email')),
      );
      await _loadDriveData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to revoke permission: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isRevoking = false;
        });
      }
    }
  }

  Future<void> _importFriendWorld(BifrostServer server, drive.File file) async {
    final String ownerEmail = file.owners?.first.emailAddress ?? 'Unknown';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Sync world from friend?'),
          content: Text(
            'This will download and overwrite your current local world with the version shared by $ownerEmail.\n\n'
            'A local backup of your current world will be saved automatically.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Download & Sync'),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;

    setState(() {
      _isPerformingAction = true;
    });

    final result = await widget.serverManager.downloadAndSyncWorldFromGoogleDrive(server, file.id!);

    if (!mounted) return;
    setState(() {
      _isPerformingAction = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result ?? 'Sync completed.')),
    );
    _loadDriveData();
  }

  String _formatPlaytime(int seconds) {
    final int minutes = seconds ~/ 60;
    final int remainingSecs = seconds % 60;
    return '${minutes}m ${remainingSecs}s';
  }

  String _formatDateTime(DateTime? dateTime) {
    if (dateTime == null) return 'Never';
    final local = dateTime.toLocal();
    return '${local.month}/${local.day}/${local.year} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  String _cleanFileName(String name) {
    return name
        .replaceAll('bifrost_sync_', '')
        .replaceAll('.zip', '')
        .replaceAll('_', ' ');
  }

  @override
  Widget build(BuildContext context) {
    final BifrostServer? server = widget.serverManager.serverByPath(widget.serverPath);
    if (server == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Google Drive Sync')),
        body: const Center(child: Text('Server no longer exists.')),
      );
    }

    final user = _driveService.currentUser;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isSyncingOrBusy = widget.serverManager.isSyncing || _isPerformingAction;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Google Drive Sync'),
        actions: [
          if (user != null)
            IconButton(
              onPressed: _isLoadingDriveFiles ? null : _loadDriveData,
              icon: _isLoadingDriveFiles
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded),
              tooltip: 'Refresh Drive data',
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_statusMessage != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.errorContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                _statusMessage!,
                style: TextStyle(color: colors.onErrorContainer),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Account Connection Card
          _AccountConnectionCard(
            user: user,
            onSignIn: _signIn,
            onSignOut: _signOut,
          ),
          const SizedBox(height: 16),

          if (user != null) ...[
            // Sync & Playtime Card
            _SyncControlsCard(
              server: server,
              isAutoSyncEnabled: _isAutoSyncEnabled,
              isSyncing: isSyncingOrBusy,
              playtimeText: _formatPlaytime(widget.serverManager.playtimeFor(server.path)),
              lastSyncText: _formatDateTime(widget.serverManager.lastSyncTimeFor(server.path)),
              onToggleAutoSync: _toggleAutoSync,
              onSyncNow: () => _manualSync(server),
            ),
            const SizedBox(height: 16),

            // Share section (only available if we have already synced and have a file ID)
            if (_currentFileId != null) ...[
              _ShareSectionCard(
                emailController: _emailController,
                isSharing: _isSharing,
                isRevoking: _isRevoking,
                permissions: _currentPermissions,
                onShare: _shareWorld,
                onRevoke: _revokePermission,
              ),
              const SizedBox(height: 16),
            ],

            // Friends' Shared Worlds
            _FriendsWorldsCard(
              sharedFiles: _sharedWorlds.where((file) {
                // Filter out current user's file to show friend worlds
                final expectedName = 'bifrost_sync_${server.name.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_')}.zip';
                return file.name != expectedName;
              }).toList(),
              isBusy: isSyncingOrBusy,
              onImport: (file) => _importFriendWorld(server, file),
              cleanName: _cleanFileName,
              formatDateTime: _formatDateTime,
            ),
          ],
        ],
      ),
    );
  }
}

class _AccountConnectionCard extends StatelessWidget {
  const _AccountConnectionCard({
    required this.user,
    required this.onSignIn,
    required this.onSignOut,
  });

  final GoogleSignInAccount? user;
  final VoidCallback onSignIn;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: colors.outlineVariant),
      ),
      color: colors.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            if (user == null) ...[
              const CircleAvatar(
                radius: 36,
                backgroundColor: Colors.blueAccent,
                child: Icon(Icons.cloud_queue_rounded, size: 40, color: Colors.white),
              ),
              const SizedBox(height: 16),
              Text(
                'Connect Google Drive',
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              Text(
                'Sign in with Google to enable automatic cloud backups and play co-op worlds with friends.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onSignIn,
                icon: const Icon(Icons.login_rounded),
                label: const Text('Sign in with Google'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ] else ...[
              Row(
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundImage: user!.photoUrl != null ? NetworkImage(user!.photoUrl!) : null,
                    child: user!.photoUrl == null
                        ? const Icon(Icons.person_rounded, size: 30)
                        : null,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user!.displayName ?? 'Google User',
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          user!.email,
                          style: theme.textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: onSignOut,
                    icon: const Icon(Icons.logout_rounded),
                    color: colors.error,
                    tooltip: 'Disconnect Account',
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SyncControlsCard extends StatelessWidget {
  const _SyncControlsCard({
    required this.server,
    required this.isAutoSyncEnabled,
    required this.isSyncing,
    required this.playtimeText,
    required this.lastSyncText,
    required this.onToggleAutoSync,
    required this.onSyncNow,
  });

  final BifrostServer server;
  final bool isAutoSyncEnabled;
  final bool isSyncing;
  final String playtimeText;
  final String lastSyncText;
  final ValueChanged<bool> onToggleAutoSync;
  final VoidCallback onSyncNow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: colors.outlineVariant),
      ),
      color: colors.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Sync Status',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Auto-Sync World', style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text('Sync world back to Drive after 5 minutes of play'),
              value: isAutoSyncEnabled,
              onChanged: onToggleAutoSync,
            ),
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Active Playtime Tracker', style: TextStyle(fontWeight: FontWeight.w500)),
                Text(
                  playtimeText,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colors.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Last Synced', style: TextStyle(fontWeight: FontWeight.w500)),
                Text(
                  lastSyncText,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: isSyncing ? null : onSyncNow,
                icon: isSyncing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.cloud_upload_rounded),
                label: Text(isSyncing ? 'Syncing...' : 'Sync Now'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShareSectionCard extends StatelessWidget {
  const _ShareSectionCard({
    required this.emailController,
    required this.isSharing,
    required this.isRevoking,
    required this.permissions,
    required this.onShare,
    required this.onRevoke,
  });

  final TextEditingController emailController;
  final bool isSharing;
  final bool isRevoking;
  final List<drive.Permission> permissions;
  final VoidCallback onShare;
  final Function(String permissionId, String email) onRevoke;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: colors.outlineVariant),
      ),
      color: colors.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Share World with Friends',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(
              'Give your friends access to this world file so they can sync and continue the game on their device.',
              style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: emailController,
                    decoration: InputDecoration(
                      hintText: "Friend's Gmail address",
                      filled: true,
                      fillColor: colors.surfaceContainerHigh,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    keyboardType: TextInputType.emailAddress,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: isSharing ? null : onShare,
                  icon: isSharing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.person_add_alt_1_rounded),
                  style: IconButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    padding: const EdgeInsets.all(12),
                  ),
                ),
              ],
            ),
            if (permissions.isNotEmpty) ...[
              const Divider(height: 24),
              Text(
                'Shared With',
                style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold, color: colors.primary),
              ),
              const SizedBox(height: 8),
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: permissions.length,
                itemBuilder: (context, index) {
                  final perm = permissions[index];
                  final email = perm.emailAddress ?? 'Unknown Email';
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: const Icon(Icons.person_outline_rounded),
                    title: Text(perm.displayName ?? email, style: const TextStyle(fontWeight: FontWeight.w500)),
                    subtitle: Text(email),
                    trailing: isRevoking
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : IconButton(
                            onPressed: () => onRevoke(perm.id!, email),
                            icon: const Icon(Icons.remove_circle_outline_rounded),
                            color: colors.error,
                            tooltip: 'Revoke Access',
                          ),
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FriendsWorldsCard extends StatelessWidget {
  const _FriendsWorldsCard({
    required this.sharedFiles,
    required this.isBusy,
    required this.onImport,
    required this.cleanName,
    required this.formatDateTime,
  });

  final List<drive.File> sharedFiles;
  final bool isBusy;
  final Function(drive.File file) onImport;
  final String Function(String name) cleanName;
  final String Function(DateTime? date) formatDateTime;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: colors.outlineVariant),
      ),
      color: colors.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Shared Worlds from Friends',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 12),
            if (sharedFiles.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.folder_shared_outlined, size: 48, color: colors.outline),
                      const SizedBox(height: 12),
                      Text(
                        'No shared worlds found.',
                        style: theme.textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Ask your friend to share their world zip file with your Gmail.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(color: colors.outline),
                      ),
                    ],
                  ),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: sharedFiles.length,
                separatorBuilder: (context, index) => const Divider(height: 16),
                itemBuilder: (context, index) {
                  final file = sharedFiles[index];
                  final name = cleanName(file.name ?? 'shared_world');
                  final ownerName = file.owners?.first.displayName ?? 'Unknown';
                  final ownerEmail = file.owners?.first.emailAddress ?? 'unknown@gmail.com';
                  final lastModified = formatDateTime(file.modifiedTime);
                  final double sizeMb = (int.tryParse(file.size ?? '0') ?? 0) / (1024 * 1024);

                  return Row(
                    children: [
                      Icon(Icons.public_rounded, size: 36, color: colors.primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Shared by: $ownerName ($ownerEmail)',
                              style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Updated: $lastModified (${sizeMb.toStringAsFixed(2)} MB)',
                              style: theme.textTheme.bodySmall?.copyWith(color: colors.outline),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filledTonal(
                        onPressed: isBusy ? null : () => onImport(file),
                        icon: const Icon(Icons.download_rounded),
                        tooltip: 'Sync & Replace World',
                      ),
                    ],
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}
