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
      final BifrostServer? server = widget.serverManager.serverByPath(widget.serverPath);
      if (server != null && (server.isOnline || server.isBusy)) {
        widget.serverManager.fetchConsoleDeltasFor(widget.serverPath);
      }
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
        selectedIndex: ServerDrawerIndex.terminal,
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
            child: _TerminalBadge(label: server.status, isOnline: server.isOnline),
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
                _TerminalBadge(label: server.status, isOnline: server.isOnline),
                const SizedBox(width: 8),
                _TerminalBadge(label: server.consoleLabel),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeInOut,
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D1117),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: server.isOnline
                        ? colors.primary.withValues(alpha: 0.5)
                        : colors.outlineVariant,
                    width: server.isOnline ? 1.5 : 1.0,
                  ),
                  boxShadow: server.isOnline
                      ? <BoxShadow>[
                          BoxShadow(
                            color: colors.primary.withValues(alpha: 0.12),
                            blurRadius: 16,
                            spreadRadius: 2,
                          ),
                        ]
                      : null,
                ),
                child: SingleChildScrollView(
                  reverse: true,
                  child: Text(
                    _terminalText(server, consoleOutput),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFFE6EDF3),
                      fontFamily: 'monospace',
                      height: 1.3,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            AnimatedOpacity(
              duration: const Duration(milliseconds: 300),
              opacity: server.isOnline ? 1.0 : 0.5,
              child: TextField(
                controller: _commandController,
                enabled: server.isOnline,
                textInputAction: TextInputAction.send,
                onSubmitted: server.isOnline
                    ? (_) {
                        _sendCommand(server);
                      }
                    : null,
                decoration: InputDecoration(
                  prefixIcon: Icon(
                    Icons.chevron_right_rounded,
                    color: server.isOnline ? colors.primary : null,
                  ),
                  hintText: server.isOnline
                      ? 'Type a Minecraft command, e.g. say hello'
                      : 'Start the server to use terminal commands.',
                  suffixIcon: _SendButton(
                    enabled: server.isOnline,
                    onPressed: () => _sendCommand(server),
                  ),
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

class _SendButton extends StatefulWidget {
  const _SendButton({
    required this.enabled,
    required this.onPressed,
  });

  final bool enabled;
  final VoidCallback onPressed;

  @override
  State<_SendButton> createState() => _SendButtonState();
}

class _SendButtonState extends State<_SendButton> {
  double _scale = 1.0;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: _scale,
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOutBack,
      child: IconButton(
        onPressed: widget.enabled
            ? () {
                setState(() => _scale = 0.85);
                Future<void>.delayed(const Duration(milliseconds: 150), () {
                  if (mounted) {
                    setState(() => _scale = 1.0);
                  }
                });
                widget.onPressed();
              }
            : null,
        icon: const Icon(Icons.send_rounded),
        tooltip: 'Send command',
      ),
    );
  }
}

class _TerminalBadge extends StatelessWidget {
  const _TerminalBadge({
    required this.label,
    this.isOnline = false,
  });

  final String label;
  final bool isOnline;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        color: isOnline
            ? colors.primaryContainer
            : colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: isOnline
                ? colors.onPrimaryContainer
                : colors.onSurfaceVariant,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}
