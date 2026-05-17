import 'dart:async';

import 'package:bifrost/Components/server_navigation_drawer.dart';
import 'package:bifrost/Models/bifrost_server.dart';
import 'package:bifrost/Pages/server_page.dart';
import 'package:bifrost/Pages/server_players_page.dart';
import 'package:bifrost/Pages/server_settings_page.dart';
import 'package:bifrost/Pages/server_world_page.dart';
import 'package:bifrost/Services/server_manager_service.dart';
import 'package:flutter/material.dart';

class TerminalPage extends StatefulWidget {
  const TerminalPage({
    super.key,
    required this.serverPath,
    required this.serverManager,
  });

  final String serverPath;
  final ServerManagerService serverManager;

  @override
  State<TerminalPage> createState() => _TerminalPageState();
}

class _TerminalPageState extends State<TerminalPage> {
  final TextEditingController _commandController = TextEditingController();
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    widget.serverManager.addListener(_refresh);
    widget.serverManager.refreshServerStatusFor(widget.serverPath);
    _refreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      widget.serverManager.refreshServerStatusFor(widget.serverPath);
    });
  }

  void _refresh() {
    if (mounted) {
      setState(() {});
    }
  }

  void _goHome() {
    Navigator.of(context).popUntil((Route<dynamic> route) => route.isFirst);
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _commandController.dispose();
    widget.serverManager.removeListener(_refresh);
    super.dispose();
  }

  Future<void> _sendCommand(BifrostServer server) async {
    final String command = _commandController.text.trim();
    if (command.isEmpty) {
      return;
    }

    final String? message = await widget.serverManager.sendServerCommand(
      server: server,
      command: command,
    );
    if (!mounted) {
      return;
    }
    if (message != null) {
      _commandController.clear();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final BifrostServer? server = widget.serverManager.serverByPath(
      widget.serverPath,
    );

    if (server == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Terminal')),
        body: const Center(child: Text('Server no longer exists.')),
      );
    }

    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final String consoleOutput = widget.serverManager.consoleOutputFor(
      server.path,
    );

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
        },
        onOpenPlayers: () {
          Navigator.of(context).pop();
          Navigator.of(context).pushReplacement(
            MaterialPageRoute<ServerPlayersPage>(
              builder: (BuildContext context) {
                return ServerPlayersPage(
                  serverPath: server.path,
                  serverManager: widget.serverManager,
                );
              },
            ),
          );
        },
        onOpenWorld: () {
          Navigator.of(context).pop();
          Navigator.of(context).pushReplacement(
            MaterialPageRoute<WorldPage>(
              builder: (BuildContext context) {
                return WorldPage(
                  serverPath: server.path,
                  serverManager: widget.serverManager,
                );
              },
            ),
          );
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
        title: Text('${server.name} Terminal'),
        actions: <Widget>[
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: _TerminalBadge(label: server.status),
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
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                _TerminalBadge(label: server.status),
                const SizedBox(width: 8),
                _TerminalBadge(label: server.consoleLabel),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF101417),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: colors.outlineVariant),
                ),
                child: SingleChildScrollView(
                  reverse: true,
                  child: Text(
                    _terminalText(server, consoleOutput),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFFE3F6E8),
                      fontFamily: 'monospace',
                      height: 1.25,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _commandController,
              enabled: server.isOnline,
              textInputAction: TextInputAction.send,
              onSubmitted: server.isOnline
                  ? (_) {
                      _sendCommand(server);
                    }
                  : null,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.chevron_right_rounded),
                hintText: server.isOnline
                    ? 'Type a Minecraft command, e.g. say hello'
                    : 'Start the server to use terminal commands.',
                suffixIcon: IconButton(
                  onPressed: server.isOnline
                      ? () {
                          _sendCommand(server);
                        }
                      : null,
                  icon: const Icon(Icons.send_rounded),
                  tooltip: 'Send command',
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _terminalText(BifrostServer server, String consoleOutput) {
    final String message = server.runtimeMessage?.trim().isNotEmpty == true
        ? server.runtimeMessage!.trim()
        : 'No console output captured yet.';

    if (consoleOutput.trim().isNotEmpty) {
      return consoleOutput.trimRight();
    }

    return <String>[
      'Bifrost terminal',
      'Server: ${server.name}',
      'Type: ${server.type}',
      'Version: ${server.version}',
      'Status: ${server.status}',
      '',
      message,
      '',
      'Waiting for JVM console output.',
    ].join('\n');
  }
}

class _TerminalBadge extends StatelessWidget {
  const _TerminalBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: colors.onSurfaceVariant,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}
