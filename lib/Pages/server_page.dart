import 'dart:io';

import 'package:bifrost/Components/eulawindow.dart';
import 'package:bifrost/Components/server_navigation_drawer.dart';
import 'package:bifrost/Models/bifrost_server.dart';
import 'package:bifrost/Pages/server_settings_page.dart';
import 'package:bifrost/Pages/server_terminal_page.dart';
import 'package:bifrost/Pages/server_players_page.dart';
import 'package:bifrost/Pages/world_page.dart';
import 'package:bifrost/Services/server_manager_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ServerPage extends StatefulWidget {
  const ServerPage({
    super.key,
    required this.serverPath,
    required this.serverManager,
  });

  final String serverPath;
  final ServerManagerService serverManager;

  @override
  State<ServerPage> createState() => _ServerPageState();
}

class _ServerPageState extends State<ServerPage> {
  String? _localIpAddress;
  bool _isLoadingLocalIp = true;

  void _goHome() {
    Navigator.of(context).popUntil((Route<dynamic> route) => route.isFirst);
  }

  Future<void> _startServer(BifrostServer server) async {
    final bool eulaAccepted = await widget.serverManager.isEulaAccepted(server);
    if (!mounted) {
      return;
    }

    if (!eulaAccepted) {
      final bool accepted = await showEulaWindow(context) ?? false;
      if (!mounted || !accepted) {
        return;
      }

      final String? error = await widget.serverManager.acceptEula(server);
      if (!mounted) {
        return;
      }
      if (error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error)),
        );
        return;
      }
    }

    widget.serverManager.startServer(server);
  }

  @override
  void initState() {
    super.initState();
    widget.serverManager.addListener(_refresh);
    _loadLocalIpAddress();
  }

  void _refresh() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _loadLocalIpAddress() async {
    try {
      final List<NetworkInterface> interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      final String? address = _bestLocalAddress(interfaces);
      if (!mounted) {
        return;
      }
      setState(() {
        _localIpAddress = address;
        _isLoadingLocalIp = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _localIpAddress = null;
        _isLoadingLocalIp = false;
      });
    }
  }

  String? _bestLocalAddress(List<NetworkInterface> interfaces) {
    final List<String> candidates = <String>[
      for (final NetworkInterface networkInterface in interfaces)
        for (final InternetAddress address in networkInterface.addresses)
          if (_isUsableLanAddress(address.address)) address.address,
    ];

    if (candidates.isEmpty) {
      return null;
    }

    return candidates.firstWhere(
      (String address) => address.startsWith('192.168.'),
      orElse: () => candidates.first,
    );
  }

  bool _isUsableLanAddress(String address) {
    return !address.startsWith('127.') &&
        !address.startsWith('169.254.') &&
        !address.startsWith('0.');
  }

  @override
  void dispose() {
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
        appBar: AppBar(title: const Text('Server Dashboard')),
        body: const Center(child: Text('Server no longer exists.')),
      );
    }

    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final bool canStart = !server.isBusy && !server.isOnline;
    final bool canStop = server.isOnline;
    final bool canRestart = server.isOnline && !server.isBusy;

    return Scaffold(
      endDrawer: ServerNavigationDrawer(
        server: server,
        onOpenDashboard: () {
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
        title: Text(server.name),
        actions: <Widget>[
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: _StatusPill(
              label: server.status,
              isOnline: server.isOnline,
            ),
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
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: <Widget>[
          _HeroPanel(server: server),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              FilledButton.icon(
                onPressed: canStart
                    ? () {
                        _startServer(server);
                      }
                    : null,
                icon: const Icon(Icons.rocket_launch_rounded),
                label: const Text('Start'),
              ),
              FilledButton.tonalIcon(
                onPressed: canStop
                    ? () {
                        widget.serverManager.stopServer(server);
                      }
                    : null,
                icon: const Icon(Icons.stop_circle_rounded),
                label: const Text('Stop'),
                style: FilledButton.styleFrom(
                  foregroundColor: colors.onErrorContainer,
                  backgroundColor: colors.errorContainer,
                ),
              ),
              OutlinedButton.icon(
                onPressed: canRestart
                    ? () {
                        widget.serverManager.restartServer(server);
                      }
                    : null,
                icon: const Icon(Icons.restart_alt_rounded),
                label: const Text('Restart'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _LocalNetworkPanel(
            isLoading: _isLoadingLocalIp,
            ipAddress: _localIpAddress,
          ),
          const SizedBox(height: 10),
          GridView.count(
            crossAxisCount: MediaQuery.sizeOf(context).width > 640 ? 4 : 2,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1.85,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: <Widget>[
              _DashboardMetric(
                icon: Icons.dns_rounded,
                label: 'Server Type',
                value: server.type,
              ),
              _DashboardMetric(
                icon: Icons.new_releases_rounded,
                label: 'Version',
                value: server.version,
              ),
              const _DashboardMetric(
                icon: Icons.groups_rounded,
                label: 'Players Online',
                value: 'Not tracked',
              ),
              _DashboardMetric(
                icon: Icons.memory_rounded,
                label: 'Allocated RAM',
                value: server.memoryLabel,
              ),
              const _DashboardMetric(
                icon: Icons.speed_rounded,
                label: 'RAM Usage',
                value: 'Pending',
              ),
              _DashboardMetric(
                icon: Icons.terminal_rounded,
                label: 'Console',
                value: server.consoleLabel,
              ),
              _DashboardMetric(
                icon: Icons.power_settings_new_rounded,
                label: 'Runtime State',
                value: server.status,
              ),
              _DashboardPathMetric(path: server.path),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Runtime Message',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Text(
              server.runtimeMessage?.trim().isNotEmpty == true
                  ? server.runtimeMessage!
                  : 'No runtime message yet.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroPanel extends StatelessWidget {
  const _HeroPanel({required this.server});

  final BifrostServer server;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: <Color>[
            colors.primaryContainer,
            colors.tertiaryContainer,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            Icons.storage_rounded,
            size: 30,
            color: colors.onPrimaryContainer,
          ),
          const SizedBox(height: 8),
          Text(
            server.name,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w900,
              color: colors.onPrimaryContainer,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${server.type} • ${server.version}',
            style: theme.textTheme.titleMedium?.copyWith(
              color: colors.onPrimaryContainer.withOpacity(0.78),
            ),
          ),
        ],
      ),
    );
  }
}

class _LocalNetworkPanel extends StatelessWidget {
  const _LocalNetworkPanel({
    required this.isLoading,
    required this.ipAddress,
  });

  final bool isLoading;
  final String? ipAddress;

  static const int _minecraftPort = 25565;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final String? address = ipAddress == null
        ? null
        : '${ipAddress!}:$_minecraftPort';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: colors.primaryContainer,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              Icons.wifi_tethering_rounded,
              color: colors.onPrimaryContainer,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Local Network Address',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: colors.onSurfaceVariant,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                SelectableText(
                  isLoading
                      ? 'Finding device IP...'
                      : address ?? 'No LAN IP found. Connect to Wi-Fi.',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: address == null ? colors.onSurfaceVariant : null,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Friends on the same Wi-Fi can join with this address.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filledTonal(
            onPressed: address == null
                ? null
                : () async {
                    await Clipboard.setData(ClipboardData(text: address));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Copied $address')),
                      );
                    }
                  },
            icon: const Icon(Icons.copy_rounded),
            tooltip: 'Copy LAN address',
          ),
        ],
      ),
    );
  }
}

class _DashboardMetric extends StatelessWidget {
  const _DashboardMetric({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Icon(icon, size: 18, color: colors.primary),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DashboardPathMetric extends StatelessWidget {
  const _DashboardPathMetric({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Icon(Icons.folder_rounded, size: 18, color: colors.primary),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Path',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                path,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  height: 1.05,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.label,
    required this.isOnline,
  });

  final String label;
  final bool isOnline;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: isOnline ? colors.primaryContainer : colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Text(
          label,
          style: theme.textTheme.labelLarge?.copyWith(
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
