import 'package:bifrost/Models/bifrost_server.dart';
import 'package:flutter/material.dart';

class ServerNavigationDrawer extends StatelessWidget {
  const ServerNavigationDrawer({
    super.key,
    required this.server,
    required this.onOpenDashboard,
    required this.onOpenTerminal,
    required this.onOpenSettings,
    required this.onOpenPlayers,
    required this.onOpenWorld,
  });

  final BifrostServer server;
  final VoidCallback onOpenDashboard;
  final VoidCallback onOpenTerminal;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenPlayers;
  final VoidCallback onOpenWorld;

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
            ListTile(
              leading: const Icon(Icons.group_rounded),
              title: const Text('Players'),
              subtitle: const Text('Whitelist, ops, bans, and IP bans'),
              onTap: onOpenPlayers,
            ),
            ListTile(
              leading: const Icon(Icons.public_rounded),
              title: const Text('World'),
              subtitle: const Text('Backups, upload, files, and generation'),
              onTap: onOpenWorld,
            ),
            ListTile(
              leading: const Icon(Icons.tune_rounded),
              title: const Text('Server Settings'),
              subtitle: const Text('Edit server.properties'),
              onTap: onOpenSettings,
            ),
          ],
        ),
      ),
    );
  }
}
