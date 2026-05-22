import 'package:bifrost/Models/bifrost_server.dart';
import 'package:flutter/material.dart';

/// Identifies which section of the server UI is currently active.
///
/// The index order matches the [NavigationDrawerDestination] list inside
/// [ServerNavigationDrawer].
class ServerDrawerIndex {
  const ServerDrawerIndex._();

  static const int dashboard = 0;
  static const int terminal = 1;
  static const int players = 2;
  static const int world = 3;
  static const int settings = 4;
}

class ServerNavigationDrawer extends StatelessWidget {
  const ServerNavigationDrawer({
    super.key,
    required this.server,
    required this.selectedIndex,
    required this.onOpenDashboard,
    required this.onOpenTerminal,
    required this.onOpenSettings,
    required this.onOpenPlayers,
    required this.onOpenWorld,
  });

  final BifrostServer server;
  final int selectedIndex;
  final VoidCallback onOpenDashboard;
  final VoidCallback onOpenTerminal;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenPlayers;
  final VoidCallback onOpenWorld;

  void _onDestinationSelected(int index) {
    switch (index) {
      case ServerDrawerIndex.dashboard:
        onOpenDashboard();
        return;
      case ServerDrawerIndex.terminal:
        onOpenTerminal();
        return;
      case ServerDrawerIndex.players:
        onOpenPlayers();
        return;
      case ServerDrawerIndex.world:
        onOpenWorld();
        return;
      case ServerDrawerIndex.settings:
        onOpenSettings();
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;

    return NavigationDrawer(
      selectedIndex: selectedIndex,
      onDestinationSelected: _onDestinationSelected,
      children: <Widget>[
        // ── Header ──────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 16, 16, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: colors.primaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.storage_rounded,
                  color: colors.onPrimaryContainer,
                  size: 26,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                server.name,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${server.type} • ${server.version}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              _StatusChip(
                label: server.status,
                isOnline: server.isOnline,
              ),
            ],
          ),
        ),

        const Padding(
          padding: EdgeInsets.fromLTRB(28, 12, 28, 8),
          child: Divider(),
        ),

        // ── Section label ───────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 0, 28, 4),
          child: Text(
            'Server',
            style: theme.textTheme.titleSmall?.copyWith(
              color: colors.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),

        // ── Destinations ────────────────────────────────────────
        const NavigationDrawerDestination(
          icon: Icon(Icons.dashboard_outlined),
          selectedIcon: Icon(Icons.dashboard_rounded),
          label: Text('Dashboard'),
        ),
        const NavigationDrawerDestination(
          icon: Icon(Icons.terminal_outlined),
          selectedIcon: Icon(Icons.terminal_rounded),
          label: Text('Terminal'),
        ),
        const NavigationDrawerDestination(
          icon: Icon(Icons.group_outlined),
          selectedIcon: Icon(Icons.group_rounded),
          label: Text('Players'),
        ),
        const NavigationDrawerDestination(
          icon: Icon(Icons.public_outlined),
          selectedIcon: Icon(Icons.public_rounded),
          label: Text('World'),
        ),

        const Padding(
          padding: EdgeInsets.fromLTRB(28, 12, 28, 8),
          child: Divider(),
        ),

        Padding(
          padding: const EdgeInsets.fromLTRB(28, 0, 28, 4),
          child: Text(
            'Configuration',
            style: theme.textTheme.titleSmall?.copyWith(
              color: colors.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),

        const NavigationDrawerDestination(
          icon: Icon(Icons.tune_outlined),
          selectedIcon: Icon(Icons.tune_rounded),
          label: Text('Server Settings'),
        ),
      ],
    );
  }
}

class _StatusChip extends StatefulWidget {
  const _StatusChip({
    required this.label,
    required this.isOnline,
  });

  final String label;
  final bool isOnline;

  @override
  State<_StatusChip> createState() => _StatusChipState();
}

class _StatusChipState extends State<_StatusChip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.5).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    if (widget.isOnline) {
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(_StatusChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isOnline && !_pulseController.isAnimating) {
      _pulseController.repeat(reverse: true);
    } else if (!widget.isOnline && _pulseController.isAnimating) {
      _pulseController.stop();
      _pulseController.reset();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: widget.isOnline
            ? colors.primaryContainer
            : colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          ScaleTransition(
            scale: widget.isOnline
                ? _pulseAnimation
                : const AlwaysStoppedAnimation<double>(1.0),
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: widget.isOnline ? colors.primary : colors.outline,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            widget.label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: widget.isOnline
                  ? colors.onPrimaryContainer
                  : colors.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
