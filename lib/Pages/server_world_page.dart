import 'package:bifrost/Components/server_navigation_drawer.dart';
import 'package:bifrost/Models/bifrost_server.dart';
import 'package:bifrost/Pages/server_page.dart';
import 'package:bifrost/Pages/server_players_page.dart';
import 'package:bifrost/Pages/server_settings_page.dart';
import 'package:bifrost/Pages/server_terminal_page.dart';
import 'package:bifrost/Pages/world_options_page.dart';
import 'package:bifrost/Services/file_manager_service.dart';
import 'package:bifrost/Services/server_manager_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class WorldPage extends StatefulWidget {
  const WorldPage({
    super.key,
    required this.serverPath,
    required this.serverManager,
  });

  final String serverPath;
  final ServerManagerService serverManager;

  @override
  State<WorldPage> createState() => _WorldPageState();
}

class _WorldPageState extends State<WorldPage> {
  static const FileManagerService _fileManagerService = FileManagerService();

  bool _isBusy = false;
  String? _message;
  String? _worldPath;

  @override
  void initState() {
    super.initState();
    widget.serverManager.addListener(_refresh);
    _loadWorldPath();
  }

  void _refresh() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _loadWorldPath() async {
    final BifrostServer? server = widget.serverManager.serverByPath(widget.serverPath);
    if (server == null) {
      return;
    }
    final String path = await widget.serverManager.resolveWorldDirectoryPath(server);
    if (!mounted) {
      return;
    }
    setState(() {
      _worldPath = path;
    });
  }

  @override
  void dispose() {
    widget.serverManager.removeListener(_refresh);
    super.dispose();
  }

  void _goHome() {
    Navigator.of(context).popUntil((Route<dynamic> route) => route.isFirst);
  }

  Future<void> _runAction(Future<String?> Function() action) async {
    setState(() {
      _isBusy = true;
      _message = null;
    });
    final String? message = await action();
    if (!mounted) {
      return;
    }
    setState(() {
      _isBusy = false;
      _message = message;
    });
    if (message != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
    await _loadWorldPath();
  }

  Future<void> _uploadWorld(BifrostServer server) async {
    final String? selectedPath = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select world folder to upload',
    );
    if (selectedPath == null || selectedPath.trim().isEmpty) {
      return;
    }
    await _runAction(() {
      return widget.serverManager.importWorldFromDirectory(
        server: server,
        sourcePath: selectedPath,
      );
    });
  }

  Future<void> _openWorldFiles() async {
    final String? path = _worldPath;
    if (path == null || path.trim().isEmpty) {
      return;
    }
    try {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        await _fileManagerService.openFolder(path);
        return;
      }
      setState(() {
        _message = 'Opening folders is configured for Android file managers.';
      });
    } on FileManagerServiceException catch (error) {
      setState(() {
        _message = error.message;
      });
    }
  }

  Future<void> _backupToGoogleDrive(BifrostServer server) async {
    await showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Backup world'),
          content: const Text(
            'This will create a copy of the current world folder '
            'inside the server\'s backups directory.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop();
                _runAction(() => widget.serverManager.exportWorldBackup(server));
              },
              child: const Text('Create Backup'),
            ),
          ],
        );
      },
    );
  }

  void _openWorldOptions(BifrostServer server) {
    Navigator.of(context).push(
      MaterialPageRoute<WorldOptionsPage>(
        builder: (BuildContext context) {
          return WorldOptionsPage(
            serverPath: server.path,
            serverManager: widget.serverManager,
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final BifrostServer? server = widget.serverManager.serverByPath(widget.serverPath);
    if (server == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('World')),
        body: const Center(child: Text('Server no longer exists.')),
      );
    }

    return Scaffold(
      endDrawer: ServerNavigationDrawer(
        server: server,
        onOpenDashboard: () {
          Navigator.of(context).pop();
          Navigator.of(context).pushReplacement(
            MaterialPageRoute<ServerPage>(
              builder: (BuildContext context) => ServerPage(
                serverPath: server.path,
                serverManager: widget.serverManager,
              ),
            ),
          );
        },
        onOpenTerminal: () {
          Navigator.of(context).pop();
          Navigator.of(context).pushReplacement(
            MaterialPageRoute<TerminalPage>(
              builder: (BuildContext context) => TerminalPage(
                serverPath: server.path,
                serverManager: widget.serverManager,
              ),
            ),
          );
        },
        onOpenPlayers: () {
          Navigator.of(context).pop();
          Navigator.of(context).pushReplacement(
            MaterialPageRoute<ServerPlayersPage>(
              builder: (BuildContext context) => ServerPlayersPage(
                serverPath: server.path,
                serverManager: widget.serverManager,
              ),
            ),
          );
        },
        onOpenWorld: () {
          Navigator.of(context).pop();
        },
        onOpenSettings: () {
          Navigator.of(context).pop();
          Navigator.of(context).pushReplacement(
            MaterialPageRoute<ServerSettingsPage>(
              builder: (BuildContext context) => ServerSettingsPage(
                serverPath: server.path,
                serverManager: widget.serverManager,
              ),
            ),
          );
        },
      ),
      appBar: AppBar(
        leading: IconButton(
          onPressed: _goHome,
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Back to servers',
        ),
        title: Text('${server.name} World'),
        actions: <Widget>[
          Builder(
            builder: (BuildContext context) {
              return IconButton(
                onPressed: () => Scaffold.of(context).openEndDrawer(),
                icon: const Icon(Icons.menu_rounded),
                tooltip: 'Server menu',
              );
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: <Widget>[
          if (_message != null) ...<Widget>[
            _WorldMessage(message: _message!),
            const SizedBox(height: 10),
          ],
          _WorldHeaderCard(
            worldPath: _worldPath ?? 'Resolving world folder...',
            isOnline: server.isOnline,
          ),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 1.35,
            children: <Widget>[
              _WorldActionTile(
                title: 'Download',
                subtitle: 'Copy world to backups',
                icon: Icons.download_rounded,
                enabled: !_isBusy,
                onTap: () => _runAction(() => widget.serverManager.exportWorldBackup(server)),
              ),
              _WorldActionTile(
                title: 'Google Drive',
                subtitle: 'Backup world to Drive',
                icon: Icons.cloud_upload_rounded,
                enabled: !_isBusy,
                onTap: () => _backupToGoogleDrive(server),
              ),
              _WorldActionTile(
                title: 'Upload',
                subtitle: 'Replace world from folder',
                icon: Icons.upload_rounded,
                enabled: !_isBusy,
                onTap: () => _uploadWorld(server),
              ),
              _WorldActionTile(
                title: 'Options',
                subtitle: 'Seed, datapacks, gamerules',
                icon: Icons.tune_rounded,
                enabled: !_isBusy,
                onTap: () => _openWorldOptions(server),
              ),
              _WorldActionTile(
                title: 'Files',
                subtitle: 'Open world in Material Files',
                icon: Icons.folder_open_rounded,
                enabled: !_isBusy,
                onTap: _openWorldFiles,
              ),
              _WorldActionTile(
                title: 'Generate',
                subtitle: 'Regenerate random seed',
                icon: Icons.casino_rounded,
                enabled: !_isBusy && !server.isOnline && !server.isBusy,
                onTap: () => _runAction(() => widget.serverManager.regenerateWorld(server)),
              ),
            ],
          ),
          if (_isBusy) ...<Widget>[
            const SizedBox(height: 16),
            const LinearProgressIndicator(),
          ],
        ],
      ),
    );
  }
}

class _WorldHeaderCard extends StatelessWidget {
  const _WorldHeaderCard({required this.worldPath, required this.isOnline});

  final String worldPath;
  final bool isOnline;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.public_rounded, color: colors.primary, size: 36),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('World folder', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Text(worldPath, maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Text(
                  isOnline ? 'Stop the server before upload/regenerate.' : 'Safe for upload and regeneration.',
                  style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WorldActionTile extends StatelessWidget {
  const _WorldActionTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: enabled ? onTap : null,
      child: Ink(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: colors.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(icon, color: enabled ? colors.primary : colors.outline, size: 32),
            const Spacer(),
            Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Text(subtitle, style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

class _WorldMessage extends StatelessWidget {
  const _WorldMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(message, style: TextStyle(color: colors.onSurfaceVariant)),
    );
  }
}
