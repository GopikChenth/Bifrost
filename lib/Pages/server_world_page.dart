import 'package:bifrost/Components/server_navigation_drawer.dart';
import 'package:bifrost/Models/bifrost_server.dart';
import 'package:bifrost/Pages/server_page.dart';
import 'package:bifrost/Pages/server_players_page.dart';
import 'package:bifrost/Pages/server_settings_page.dart';
import 'package:bifrost/Pages/server_terminal_page.dart';
import 'package:bifrost/Pages/google_drive_sync_page.dart';
import 'package:bifrost/Pages/world_options_page.dart';

import 'package:bifrost/Services/file_manager_service.dart';
import 'package:bifrost/Services/server_manager_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bifrost/Services/google_drive_sync_service.dart';
import 'package:bifrost/Services/discord_webhook_service.dart';

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
  final TextEditingController _discordWebhookController = TextEditingController();
  final TextEditingController _discordCreatorController = TextEditingController();

  bool _isBusy = false;
  String? _message;
  String? _worldPath;
  bool _discordEnabled = false;
  bool _discordNotifyOnStart = true;
  bool _discordNotifyOnStop = true;
  bool _discordNotifyOnSync = true;
  bool _isDiscordTesting = false;

  @override
  void initState() {
    super.initState();
    widget.serverManager.addListener(_refresh);
    _loadWorldPath();
    _loadDiscordSettings();
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
    _discordWebhookController.dispose();
    _discordCreatorController.dispose();
    widget.serverManager.removeListener(_refresh);
    super.dispose();
  }

  void _goHome() {
    Navigator.of(context).popUntil((Route<dynamic> route) => route.isFirst);
  }

  Future<void> _loadDiscordSettings() async {
    final BifrostServer? server = widget.serverManager.serverByPath(widget.serverPath);
    if (server == null) return;

    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String path = server.path;
      final String discordWebhookUrl = prefs.getString('discord_webhook_url_$path') ?? '';
      
      final String defaultCreator = GoogleDriveSyncService.instance.currentUser?.displayName ?? 'Host';
      final String discordCreatorName = prefs.getString('discord_creator_name_$path') ?? defaultCreator;
      
      final bool discordEnabled = prefs.getBool('discord_enabled_$path') ?? false;
      final bool notifyStart = prefs.getBool('discord_notify_on_start_$path') ?? true;
      final bool notifyStop = prefs.getBool('discord_notify_on_stop_$path') ?? true;
      final bool notifySync = prefs.getBool('discord_notify_on_sync_$path') ?? true;

      if (!mounted) {
        return;
      }
      setState(() {
        _discordWebhookController.text = discordWebhookUrl;
        _discordCreatorController.text = discordCreatorName;
        _discordEnabled = discordEnabled;
        _discordNotifyOnStart = notifyStart;
        _discordNotifyOnStop = notifyStop;
        _discordNotifyOnSync = notifySync;
      });
    } catch (_) {}
  }

  Future<void> _saveDiscordSettings() async {
    final BifrostServer? server = widget.serverManager.serverByPath(widget.serverPath);
    if (server == null) return;

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String path = server.path;

    await prefs.setString('discord_webhook_url_$path', _discordWebhookController.text.trim());
    await prefs.setString('discord_creator_name_$path', _discordCreatorController.text.trim());
    await prefs.setBool('discord_enabled_$path', _discordEnabled);
    await prefs.setBool('discord_notify_on_start_$path', _discordNotifyOnStart);
    await prefs.setBool('discord_notify_on_stop_$path', _discordNotifyOnStop);
    await prefs.setBool('discord_notify_on_sync_$path', _discordNotifyOnSync);
  }

  Future<void> _sendTestDiscordMessage(BifrostServer server) async {
    final String url = _discordWebhookController.text.trim();
    if (url.isEmpty || !url.startsWith('http')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid Discord Webhook URL first.')),
      );
      return;
    }

    setState(() {
      _isDiscordTesting = true;
    });

    try {
      final String creator = _discordCreatorController.text.trim().isNotEmpty
          ? _discordCreatorController.text.trim()
          : 'Host';
      
      final Color color = Theme.of(context).colorScheme.primary;
      final int embedColor = color.toARGB32() & 0xFFFFFF;

      await const DiscordWebhookService().sendTestNotification(
        webhookUrl: url,
        creatorName: creator,
        themeColor: embedColor,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Test message sent successfully to Discord!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send test message: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isDiscordTesting = false;
        });
      }
    }
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

  void _openGoogleDriveSync(BifrostServer server) {
    Navigator.of(context).push(
      MaterialPageRoute<GoogleDriveSyncPage>(
        builder: (BuildContext context) {
          return GoogleDriveSyncPage(
            serverPath: server.path,
            serverManager: widget.serverManager,
          );
        },
      ),
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

    final ThemeData theme = Theme.of(context);

    return Scaffold(
      endDrawer: ServerNavigationDrawer(
        server: server,
        selectedIndex: ServerDrawerIndex.world,
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
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: _message != null
                ? Padding(
                    key: ValueKey<String>(_message!),
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _WorldMessage(message: _message!),
                  )
                : const SizedBox.shrink(key: ValueKey<String>('no-msg')),
          ),
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
            childAspectRatio: 2.2,
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
                onTap: () => _openGoogleDriveSync(server),
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
                subtitle: 'Open world in file manager',
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
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.notifications_active_rounded,
                          color: theme.colorScheme.primary,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Discord Integration',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Enable Discord Webhook'),
                    subtitle: const Text('Send status notifications to a Discord channel.'),
                    value: _discordEnabled,
                    onChanged: (bool value) {
                      setState(() {
                        _discordEnabled = value;
                      });
                      _saveDiscordSettings();
                    },
                  ),
                  if (_discordEnabled) ...[
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: TextField(
                        controller: _discordWebhookController,
                        keyboardType: TextInputType.url,
                        decoration: InputDecoration(
                          labelText: 'Webhook URL',
                          helperText: 'Paste the Discord channel Webhook URL here.',
                          suffixIcon: IconButton(
                            onPressed: () {
                              _saveDiscordSettings();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Saved Discord Webhook URL.')),
                              );
                            },
                            icon: const Icon(Icons.save_rounded),
                            tooltip: 'Save Webhook URL',
                          ),
                        ),
                        onSubmitted: (_) {
                          _saveDiscordSettings();
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: TextField(
                        controller: _discordCreatorController,
                        keyboardType: TextInputType.name,
                        decoration: InputDecoration(
                          labelText: 'Server Host / Creator Name',
                          helperText: 'Attributed as creator in Discord notifications.',
                          suffixIcon: IconButton(
                            onPressed: () {
                              _saveDiscordSettings();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Saved Creator Name.')),
                              );
                            },
                            icon: const Icon(Icons.save_rounded),
                            tooltip: 'Save Creator Name',
                          ),
                        ),
                        onSubmitted: (_) {
                          _saveDiscordSettings();
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Notification Triggers',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Notify on Server Start'),
                      subtitle: const Text('Sends a message when the server goes Live.'),
                      value: _discordNotifyOnStart,
                      onChanged: (bool value) {
                        setState(() {
                          _discordNotifyOnStart = value;
                        });
                        _saveDiscordSettings();
                      },
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Notify on Server Stop'),
                      subtitle: const Text('Sends a message when the server is stopped.'),
                      value: _discordNotifyOnStop,
                      onChanged: (bool value) {
                        setState(() {
                          _discordNotifyOnStop = value;
                        });
                        _saveDiscordSettings();
                      },
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Notify on World Sync'),
                      subtitle: const Text('Sends a message when Google Drive syncs backups.'),
                      value: _discordNotifyOnSync,
                      onChanged: (bool value) {
                        setState(() {
                          _discordNotifyOnSync = value;
                        });
                        _saveDiscordSettings();
                      },
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _isDiscordTesting
                            ? null
                            : () => _sendTestDiscordMessage(server),
                        icon: _isDiscordTesting
                            ? SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: theme.colorScheme.onPrimary,
                                ),
                              )
                            : const Icon(Icons.send_rounded),
                        label: const Text('Send Test Message'),
                        style: FilledButton.styleFrom(
                          backgroundColor: theme.colorScheme.primary,
                          foregroundColor: theme.colorScheme.onPrimary,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: _isBusy
                ? const Padding(
                    key: ValueKey<String>('busy'),
                    padding: EdgeInsets.only(top: 16),
                    child: LinearProgressIndicator(),
                  )
                : const SizedBox.shrink(key: ValueKey<String>('idle')),
          ),
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: colors.primaryContainer,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(Icons.public_rounded, color: colors.onPrimaryContainer, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('World folder', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
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

class _WorldActionTile extends StatefulWidget {
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
  State<_WorldActionTile> createState() => _WorldActionTileState();
}

class _WorldActionTileState extends State<_WorldActionTile> {
  double _scale = 1.0;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    return AnimatedScale(
      scale: _scale,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutBack,
      child: Material(
        color: colors.surfaceContainerLow,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(color: colors.outlineVariant),
        ),
        child: InkWell(
          onTap: widget.enabled ? widget.onTap : null,
          onTapDown: widget.enabled ? (_) => setState(() => _scale = 0.95) : null,
          onTapUp: widget.enabled ? (_) => setState(() => _scale = 1.0) : null,
          onTapCancel: () => setState(() => _scale = 1.0),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: <Widget>[
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: widget.enabled
                        ? colors.primaryContainer
                        : colors.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    widget.icon,
                    color: widget.enabled
                        ? colors.onPrimaryContainer
                        : colors.outline,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Text(
                        title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String get title => widget.title;
  String get subtitle => widget.subtitle;
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
