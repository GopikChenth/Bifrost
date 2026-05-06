import 'package:bifrost/Models/bifrost_server.dart';
import 'package:bifrost/Services/server_manager_service.dart';
import 'package:bifrost/Pages/terminalpage.dart';
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
  @override
  void initState() {
    super.initState();
    widget.serverManager.addListener(_refresh);
  }

  void _refresh() {
    if (mounted) {
      setState(() {});
    }
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
    final bool canStartTunnel = server.isOnline && !server.isTunnelOnline;
    final bool canStopTunnel = server.isTunnelOnline;

    return Scaffold(
      endDrawer: ServerNavigationDrawer(
        server: server,
        onOpenDashboard: () {
          Navigator.of(context).pop();
        },
        onOpenTerminal: () {
          Navigator.of(context).pop();
          Navigator.of(context).push(
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
      ),
      appBar: AppBar(
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
                        widget.serverManager.startServer(server);
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
              OutlinedButton.icon(
                onPressed: canStartTunnel
                    ? () async {
                        final String? message =
                            await widget.serverManager.startPlayitTunnel(server);
                        if (context.mounted && message != null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(message)),
                          );
                        }
                      }
                    : null,
                icon: const Icon(Icons.public_rounded),
                label: const Text('Start Playit'),
              ),
              OutlinedButton.icon(
                onPressed: canStopTunnel
                    ? () async {
                        final String? message =
                            await widget.serverManager.stopPlayitTunnel(server);
                        if (context.mounted && message != null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(message)),
                          );
                        }
                      }
                    : null,
                icon: const Icon(Icons.public_off_rounded),
                label: const Text('Stop Playit'),
              ),
            ],
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
              _DashboardMetric(
                icon: Icons.public_rounded,
                label: 'Playit Tunnel',
                value: server.tunnelStatus,
              ),
              _DashboardPathMetric(path: server.path),
            ],
          ),
          const SizedBox(height: 10),
          _TunnelPanel(
            server: server,
            tunnelLog: widget.serverManager.tunnelOutputFor(widget.serverPath),
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

class _TunnelPanel extends StatelessWidget {
  const _TunnelPanel({
    required this.server,
    this.tunnelLog = '',
  });

  final BifrostServer server;
  final String tunnelLog;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final String address = server.tunnelAddress?.trim() ?? '';
    final String? claimUrl = server.tunnelClaimUrl?.trim().isNotEmpty == true
        ? server.tunnelClaimUrl
        : null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // Header row
          Row(
            children: <Widget>[
              Icon(Icons.public_rounded, color: colors.primary, size: 20),
              const SizedBox(width: 8),
              Text(
                'Playit Tunnel',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const Spacer(),
              _StatusPill(
                label: server.tunnelStatus,
                isOnline: server.isTunnelOnline,
              ),
            ],
          ),

          // ── Starting: info + live log ────────────────────────────────────
          if (server.tunnelStatus == 'Starting') ...<Widget>[
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Connecting to Playit servers…\n'
                    'On first run a claim URL will appear below — '
                    'copy it and open it in your browser.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Log box — always shown while Starting so the user sees output arrive
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(minHeight: 60, maxHeight: 180),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: colors.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: tunnelLog.trim().isEmpty
                  ? Center(
                      child: Text(
                        'Waiting for agent output…',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant.withAlpha(120),
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    )
                  : SingleChildScrollView(
                      reverse: true,
                      child: SelectableText(
                        tunnelLog,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          color: colors.onSurfaceVariant,
                          height: 1.4,
                        ),
                      ),
                    ),
            ),
          ],

          // ── Claim URL (first run) ────────────────────────────────────────
          if (claimUrl != null) ...<Widget>[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.tertiaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Icon(
                        Icons.link_rounded,
                        size: 18,
                        color: colors.onTertiaryContainer,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'One-time setup required',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: colors.onTertiaryContainer,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Copy this URL and open it in your browser to link the Playit agent to your account:',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onTertiaryContainer,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    claimUrl,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onTertiaryContainer,
                      fontWeight: FontWeight.w700,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: colors.tertiary,
                      foregroundColor: colors.onTertiary,
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: claimUrl));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Claim URL copied — paste it in your browser.',
                            ),
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.copy_rounded, size: 16),
                    label: const Text('Copy Claim URL'),
                  ),
                ],
              ),
            ),
          ],

          // ── Active tunnel address ────────────────────────────────────────
          if (address.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: colors.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Share this address with friends',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colors.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(height: 4),
                  SelectableText(
                    address,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: colors.onPrimaryContainer,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: address));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Address copied to clipboard.')),
                  );
                }
              },
              icon: const Icon(Icons.copy_rounded, size: 16),
              label: const Text('Copy Address'),
            ),
          ],

          // ── Idle / no address ────────────────────────────────────────────
          if (address.isEmpty && claimUrl == null &&
              server.tunnelStatus != 'Starting') ...<Widget>[
            const SizedBox(height: 10),
            Text(
              server.tunnelMessage?.trim().isNotEmpty == true
                  ? server.tunnelMessage!
                  : 'Start Playit after the server is online to get a shareable address.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ],

          // ── Raw agent log ────────────────────────────────────────────────
          if (tunnelLog.trim().isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            Text(
              'Agent output',
              style: theme.textTheme.labelSmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxHeight: 160),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: colors.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: SingleChildScrollView(
                reverse: true,
                child: SelectableText(
                  tunnelLog,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    color: colors.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class ServerNavigationDrawer extends StatelessWidget {
  const ServerNavigationDrawer({
    super.key,
    required this.server,
    required this.onOpenDashboard,
    required this.onOpenTerminal,
  });

  final BifrostServer server;
  final VoidCallback onOpenDashboard;
  final VoidCallback onOpenTerminal;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;

    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: <Widget>[
            Container(
              padding: const EdgeInsets.all(18),
              color: colors.primaryContainer,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(
                    Icons.storage_rounded,
                    color: colors.onPrimaryContainer,
                    size: 34,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    server.name,
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: colors.onPrimaryContainer,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${server.type} • ${server.version}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.onPrimaryContainer.withOpacity(0.78),
                    ),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.dashboard_rounded),
              title: const Text('Dashboard'),
              subtitle: const Text('Status and server stats'),
              onTap: onOpenDashboard,
            ),
            ListTile(
              leading: const Icon(Icons.terminal_rounded),
              title: const Text('Terminal'),
              subtitle: const Text('Console view and commands'),
              onTap: onOpenTerminal,
            ),
          ],
        ),
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
