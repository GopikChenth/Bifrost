import 'package:bifrost/Components/server_navigation_drawer.dart';
import 'package:bifrost/Models/bifrost_server.dart';
import 'package:bifrost/Pages/server_settings_page.dart';
import 'package:bifrost/Pages/server_page.dart';
import 'package:bifrost/Pages/server_terminal_page.dart';
import 'package:bifrost/Services/server_manager_service.dart';
import 'package:flutter/material.dart';

class ServerPlayersPage extends StatefulWidget {
  const ServerPlayersPage({
    super.key,
    required this.serverPath,
    required this.serverManager,
  });

  final String serverPath;
  final ServerManagerService serverManager;

  @override
  State<ServerPlayersPage> createState() => _ServerPlayersPageState();
}

class _ServerPlayersPageState extends State<ServerPlayersPage> {
  final TextEditingController _whitelistController = TextEditingController();
  final TextEditingController _opController = TextEditingController();
  final TextEditingController _banController = TextEditingController();
  final TextEditingController _banIpController = TextEditingController();

  bool _isLoading = true;
  bool _isSending = false;
  Map<String, List<String>> _lists = const <String, List<String>>{};
  final List<String> _pendingWhitelist = <String>[];
  final List<String> _pendingOps = <String>[];
  final List<String> _pendingBans = <String>[];
  final List<String> _pendingIpBans = <String>[];
  String? _message;

  @override
  void initState() {
    super.initState();
    widget.serverManager.addListener(_refresh);
    _loadLists();
  }

  void _refresh() {
    if (mounted) {
      setState(() {});
    }
  }

  void _goHome() {
    Navigator.of(context).popUntil((Route<dynamic> route) => route.isFirst);
  }

  Future<void> _loadLists() async {
    final BifrostServer? server = widget.serverManager.serverByPath(
      widget.serverPath,
    );
    if (server == null) {
      return;
    }

    try {
      final Map<String, List<String>> lists = await widget.serverManager
          .readPlayerAccessLists(server);
      if (!mounted) {
        return;
      }
      setState(() {
        _lists = lists;
        _isLoading = false;
        _message = null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
        _message = error.toString();
      });
    }
  }

  Future<void> _sendCommand(
    BifrostServer server,
    String command, {
    TextEditingController? controller,
  }) async {
    if (!server.isOnline) {
      setState(() {
        _message = 'Start the server before changing player lists.';
      });
      return;
    }

    setState(() {
      _isSending = true;
      _message = null;
    });

    final String? message = await widget.serverManager.sendServerCommand(
      server: server,
      command: command,
    );

    if (!mounted) {
      return;
    }

    controller?.clear();
    setState(() {
      _isSending = false;
      _message = message;
    });
    await Future<void>.delayed(const Duration(milliseconds: 600));
    await _loadLists();
  }

  void _addPendingEntry({
    required TextEditingController controller,
    required List<String> target,
  }) {
    final String value = controller.text.trim();
    if (value.isEmpty) {
      return;
    }

    final bool exists = target.any(
      (String current) => current.toLowerCase() == value.toLowerCase(),
    );
    if (exists) {
      controller.clear();
      return;
    }

    setState(() {
      target.add(value);
      controller.clear();
    });
  }

  void _removePendingEntry({
    required List<String> target,
    required String value,
  }) {
    setState(() {
      target.remove(value);
    });
  }

  Future<void> _applyPendingEntries({
    required BifrostServer server,
    required List<String> target,
    required String Function(String value) commandFor,
  }) async {
    if (target.isEmpty) {
      return;
    }
    if (!server.isOnline) {
      setState(() {
        _message = 'Start the server before changing player lists.';
      });
      return;
    }

    final List<String> entries = List<String>.from(target);
    setState(() {
      _isSending = true;
      _message = null;
    });

    String? lastMessage;
    for (final String entry in entries) {
      lastMessage = await widget.serverManager.sendServerCommand(
        server: server,
        command: commandFor(entry),
      );
    }

    if (!mounted) {
      return;
    }

    setState(() {
      target.clear();
      _isSending = false;
      _message = lastMessage ?? 'Updated ${entries.length} entries.';
    });
    await Future<void>.delayed(const Duration(milliseconds: 600));
    await _loadLists();
  }

  @override
  void dispose() {
    _whitelistController.dispose();
    _opController.dispose();
    _banController.dispose();
    _banIpController.dispose();
    widget.serverManager.removeListener(_refresh);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final BifrostServer? server = widget.serverManager.serverByPath(
      widget.serverPath,
    );

    if (server == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Players')),
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
              builder: (BuildContext context) {
                return ServerPage(
                  serverPath: server.path,
                  serverManager: widget.serverManager,
                );
              },
            ),
          );
        },
        onOpenTerminal: () {
          Navigator.of(context).pop();
          Navigator.of(context).pushReplacement(
            MaterialPageRoute<TerminalPage>(
              builder: (BuildContext context) {
                return TerminalPage(
                  serverPath: server.path,
                  serverManager: widget.serverManager,
                );
              },
            ),
          );
        },
        onOpenPlayers: () {
          Navigator.of(context).pop();
        },
        onOpenSettings: () {
          Navigator.of(context).pop();
          Navigator.of(context).pushReplacement(
            MaterialPageRoute<ServerSettingsPage>(
              builder: (BuildContext context) {
                return ServerSettingsPage(
                  serverPath: server.path,
                  serverManager: widget.serverManager,
                );
              },
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
        title: Text('${server.name} Players'),
        actions: <Widget>[
          IconButton(
            onPressed: _isLoading ? null : _loadLists,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh lists',
          ),
          Builder(
            builder: (BuildContext context) {
              return IconButton(
                onPressed: () {
                  Scaffold.of(context).openEndDrawer();
                },
                icon: const Icon(Icons.menu_rounded),
                tooltip: 'Server menu',
              );
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(12),
              children: <Widget>[
                if (_message != null) ...<Widget>[
                  _MessagePanel(message: _message!),
                  const SizedBox(height: 10),
                ],
                _PlayerAccessCard(
                  title: 'Whitelist',
                  subtitle: 'Players allowed when whitelist is enabled.',
                  values: _lists['whitelist'] ?? const <String>[],
                  pendingValues: _pendingWhitelist,
                  controller: _whitelistController,
                  hintText: 'Player name',
                  addLabel: 'Add',
                  applyLabel: 'Apply Whitelist',
                  removeLabel: 'Remove',
                  isSending: _isSending,
                  onAddPending: () {
                    _addPendingEntry(
                      controller: _whitelistController,
                      target: _pendingWhitelist,
                    );
                  },
                  onRemovePending: (String value) {
                    _removePendingEntry(
                      target: _pendingWhitelist,
                      value: value,
                    );
                  },
                  onApplyPending: () {
                    _applyPendingEntries(
                      server: server,
                      target: _pendingWhitelist,
                      commandFor: (String value) => 'whitelist add $value',
                    );
                  },
                  onRemoveSaved: (String value) {
                    _sendCommand(server, 'whitelist remove $value');
                  },
                ),
                _PlayerAccessCard(
                  title: 'OP',
                  subtitle: 'Server operators with admin permissions.',
                  values: _lists['ops'] ?? const <String>[],
                  pendingValues: _pendingOps,
                  controller: _opController,
                  hintText: 'Player name',
                  addLabel: 'Add',
                  applyLabel: 'Apply OP',
                  removeLabel: 'De-op',
                  isSending: _isSending,
                  onAddPending: () {
                    _addPendingEntry(
                      controller: _opController,
                      target: _pendingOps,
                    );
                  },
                  onRemovePending: (String value) {
                    _removePendingEntry(target: _pendingOps, value: value);
                  },
                  onApplyPending: () {
                    _applyPendingEntries(
                      server: server,
                      target: _pendingOps,
                      commandFor: (String value) => 'op $value',
                    );
                  },
                  onRemoveSaved: (String value) {
                    _sendCommand(server, 'deop $value');
                  },
                ),
                _PlayerAccessCard(
                  title: 'Blacklist',
                  subtitle: 'Banned players.',
                  values: _lists['bannedPlayers'] ?? const <String>[],
                  pendingValues: _pendingBans,
                  controller: _banController,
                  hintText: 'Player name',
                  addLabel: 'Add',
                  applyLabel: 'Apply Bans',
                  removeLabel: 'Pardon',
                  isSending: _isSending,
                  onAddPending: () {
                    _addPendingEntry(
                      controller: _banController,
                      target: _pendingBans,
                    );
                  },
                  onRemovePending: (String value) {
                    _removePendingEntry(target: _pendingBans, value: value);
                  },
                  onApplyPending: () {
                    _applyPendingEntries(
                      server: server,
                      target: _pendingBans,
                      commandFor: (String value) => 'ban $value',
                    );
                  },
                  onRemoveSaved: (String value) {
                    _sendCommand(server, 'pardon $value');
                  },
                ),
                _PlayerAccessCard(
                  title: 'Banned IP',
                  subtitle: 'Blocked IP addresses.',
                  values: _lists['bannedIps'] ?? const <String>[],
                  pendingValues: _pendingIpBans,
                  controller: _banIpController,
                  hintText: 'IP address',
                  addLabel: 'Add',
                  applyLabel: 'Apply IP Bans',
                  removeLabel: 'Pardon IP',
                  isSending: _isSending,
                  onAddPending: () {
                    _addPendingEntry(
                      controller: _banIpController,
                      target: _pendingIpBans,
                    );
                  },
                  onRemovePending: (String value) {
                    _removePendingEntry(target: _pendingIpBans, value: value);
                  },
                  onApplyPending: () {
                    _applyPendingEntries(
                      server: server,
                      target: _pendingIpBans,
                      commandFor: (String value) => 'ban-ip $value',
                    );
                  },
                  onRemoveSaved: (String value) {
                    _sendCommand(server, 'pardon-ip $value');
                  },
                ),
              ],
            ),
    );
  }
}

class _PlayerAccessCard extends StatelessWidget {
  const _PlayerAccessCard({
    required this.title,
    required this.subtitle,
    required this.values,
    required this.pendingValues,
    required this.controller,
    required this.hintText,
    required this.addLabel,
    required this.applyLabel,
    required this.removeLabel,
    required this.isSending,
    required this.onAddPending,
    required this.onRemovePending,
    required this.onApplyPending,
    required this.onRemoveSaved,
  });

  final String title;
  final String subtitle;
  final List<String> values;
  final List<String> pendingValues;
  final TextEditingController controller;
  final String hintText;
  final String addLabel;
  final String applyLabel;
  final String removeLabel;
  final bool isSending;
  final VoidCallback onAddPending;
  final ValueChanged<String> onRemovePending;
  final VoidCallback onApplyPending;
  final ValueChanged<String> onRemoveSaved;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: controller,
                  decoration: InputDecoration(
                    hintText: hintText,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  onSubmitted: isSending
                      ? null
                      : (String value) {
                          final String trimmed = value.trim();
                          if (trimmed.isNotEmpty) {
                            onAddPending();
                          }
                        },
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: isSending
                    ? null
                    : () {
                        final String trimmed = controller.text.trim();
                        if (trimmed.isNotEmpty) {
                          onAddPending();
                        }
                      },
                child: Text(addLabel),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (pendingValues.isNotEmpty) ...<Widget>[
            Text(
              'Pending',
              style: theme.textTheme.labelLarge?.copyWith(
                color: colors.onSurfaceVariant,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                for (final String value in pendingValues)
                  InputChip(
                    label: Text(value),
                    onDeleted: isSending
                        ? null
                        : () {
                            onRemovePending(value);
                          },
                    deleteIcon: const Icon(Icons.close_rounded),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: isSending ? null : onApplyPending,
                icon: const Icon(Icons.done_all_rounded),
                label: Text(applyLabel),
              ),
            ),
            const Divider(height: 22),
          ],
          if (values.isEmpty)
            Text(
              'No saved entries yet.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                for (final String value in values)
                  InputChip(
                    label: Text(value),
                    onDeleted: isSending
                        ? null
                        : () {
                            onRemoveSaved(value);
                          },
                    deleteIcon: const Icon(Icons.close_rounded),
                    deleteButtonTooltipMessage: removeLabel,
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _MessagePanel extends StatelessWidget {
  const _MessagePanel({required this.message});

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
      child: Text(
        message,
        style: TextStyle(color: colors.onSurfaceVariant),
      ),
    );
  }
}
