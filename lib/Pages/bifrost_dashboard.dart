import 'dart:math' as math;

import 'package:bifrost/Components/add_server_window.dart';
import 'package:bifrost/Components/bifrost_container_transform.dart';
import 'package:bifrost/Components/eulawindow.dart';
import 'package:bifrost/Components/server_card.dart';
import 'package:bifrost/Models/bifrost_server.dart';
import 'package:bifrost/Pages/server_page.dart';
import 'package:bifrost/Pages/bifrost_setting_spage.dart';
import 'package:bifrost/Services/server_manager_service.dart';
import 'package:flutter/material.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  late final ServerManagerService _serverManager;
  late final AnimationController _staggerController;

  @override
  void initState() {
    super.initState();
    AddServerWindow.preloadDeviceInfo();
    _staggerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _serverManager = ServerManagerService()..addListener(_refresh);
    _serverManager.loadStoredServers().then((_) {
      if (mounted) {
        _staggerController.forward();
      }
    });
  }

  void _refresh() {
    if (mounted) {
      setState(() {});
    }
  }

  void _openSettingsPage() {
    Navigator.of(context)
        .push(
          MaterialPageRoute<SettingsPage>(
            builder: (BuildContext context) => const SettingsPage(),
          ),
        )
        .then((_) {
          if (mounted) {
            _serverManager.loadStoredServers();
          }
        });
  }

  void _openServerPage(BifrostServer server) {
    Navigator.of(context).push(
      MaterialPageRoute<ServerPage>(
        builder: (BuildContext context) {
          return ServerPage(
            serverPath: server.path,
            serverManager: _serverManager,
          );
        },
      ),
    );
  }

  // Morph transition is now handled by BifrostContainerTransform directly on the FAB.

  Future<void> _deleteServer(BifrostServer server) async {
    final bool? shouldDelete = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        final ColorScheme colors = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
          icon: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: colors.errorContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.delete_forever_rounded,
              color: colors.onErrorContainer,
            ),
          ),
          title: const Text('Delete Server'),
          content: Text(
            'Delete ${server.name}? This removes the server card and its local files.',
          ),
          actions: <Widget>[
            OutlinedButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              style: FilledButton.styleFrom(
                backgroundColor: colors.error,
                foregroundColor: colors.onError,
              ),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (shouldDelete != true || !mounted) {
      return;
    }

    final String? message = await _serverManager.deleteServer(server);
    if (!mounted || message == null) {
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _startServer(BifrostServer server) async {
    final bool eulaAccepted = await _serverManager.isEulaAccepted(server);
    if (!mounted) {
      return;
    }

    if (!eulaAccepted) {
      final bool accepted = await showEulaWindow(context) ?? false;
      if (!mounted || !accepted) {
        return;
      }

      final String? error = await _serverManager.acceptEula(server);
      if (!mounted) {
        return;
      }
      if (error != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error)));
        return;
      }
    }

    _serverManager.startServer(server);
  }

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    }
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '$bytes B';
  }

  @override
  void dispose() {
    _staggerController.dispose();
    _serverManager
      ..removeListener(_refresh)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;

    return Scaffold(
      body: _serverManager.isLoadingServers
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(
              slivers: <Widget>[
                // ── Hero AppBar ─────────────────────────────────
                SliverAppBar(
                  pinned: true,
                  floating: true,
                  title: Text(
                    'Bifrost',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: colors.onSurface,
                      letterSpacing: -0.5,
                    ),
                  ),
                  actions: <Widget>[
                    IconButton(
                      onPressed: _openSettingsPage,
                      icon: const Icon(Icons.settings_rounded),
                      tooltip: 'Settings',
                    ),
                  ],
                ),

                // ── Content ─────────────────────────────────────
                if (_serverManager.servers.isEmpty &&
                    !_serverManager.isCreatingServer)
                  SliverFillRemaining(
                    child: _EmptyState(colors: colors, theme: theme),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                    sliver: SliverList.list(
                      children: <Widget>[
                        // Download card
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 400),
                          transitionBuilder: (Widget child,
                              Animation<double> animation) {
                            return FadeTransition(
                              opacity: animation,
                              child: SizeTransition(
                                sizeFactor: animation,
                                child: child,
                              ),
                            );
                          },
                          child: _serverManager.isCreatingServer
                              ? Padding(
                                  key: const ValueKey<String>('download'),
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: ServerDownloadCard(
                                    serverName:
                                        _serverManager.activeDownloadServerName ??
                                            'Preparing server files...',
                                    fileName:
                                        _serverManager.activeDownloadFileName,
                                    progress: _serverManager.downloadProgress,
                                    progressLabel:
                                        _serverManager.totalDownloadBytes ==
                                                null
                                            ? _formatBytes(
                                                _serverManager.downloadedBytes)
                                            : '${_formatBytes(_serverManager.downloadedBytes)} / ${_formatBytes(_serverManager.totalDownloadBytes!)}',
                                    onCancel: _serverManager.cancelCreateServer,
                                  ),
                                )
                              : const SizedBox.shrink(
                                  key: ValueKey<String>('no-download')),
                        ),

                        // Server cards with stagger
                        ..._serverManager.servers.asMap().entries.map(
                              (MapEntry<int, BifrostServer> entry) {
                            final int index = entry.key;
                            final BifrostServer server = entry.value;
                            final int count = _serverManager.servers.length;
                            final double start = math.min(
                                index / math.max(count, 1), 0.8);
                            final double end = math.min(start + 0.4, 1.0);

                            return AnimatedBuilder(
                              animation: _staggerController,
                              builder: (BuildContext context, Widget? child) {
                                final double t = Interval(
                                  start,
                                  end,
                                  curve: Curves.easeOutCubic,
                                ).transform(_staggerController.value);
                                return Opacity(
                                  opacity: t,
                                  child: Transform.translate(
                                    offset: Offset(0, 30 * (1 - t)),
                                    child: child,
                                  ),
                                );
                              },
                              child: Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: ServerCard(
                                  name: server.name,
                                  version: server.version,
                                  serverType: server.type,
                                  statusLabel: server.status,
                                  memoryLabel: server.memoryLabel,
                                  serverPath: server.path,
                                  isOnline: server.isOnline,
                                  isBusy: _serverManager.isCreatingServer ||
                                      server.isBusy,
                                  consoleLabel: server.consoleLabel,
                                  runtimeMessage: server.runtimeMessage,
                                  onStartServer:
                                      _serverManager.isCreatingServer
                                          ? null
                                          : () {
                                              _startServer(server);
                                            },
                                  onStopServer: _serverManager.isCreatingServer
                                      ? null
                                      : () {
                                          _serverManager.stopServer(server);
                                        },
                                  onDelete: _serverManager.isCreatingServer
                                      ? null
                                      : () {
                                          _deleteServer(server);
                                        },
                                  onOpenDashboard: () {
                                    _openServerPage(server);
                                  },
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
              ],
            ),
      floatingActionButton: _serverManager.isCreatingServer
          ? null
          : BifrostContainerTransform<AddServerResult>(
              onClosed: (AddServerResult? newServer) async {
                if (newServer == null) {
                  return;
                }
                if (!context.mounted) {
                  return;
                }

                final String? message = await _serverManager.createServer(newServer);
                if (!context.mounted) {
                  return;
                }
                if (message == null) {
                  return;
                }

                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(message)));
              },
              closedBuilder: (BuildContext context, VoidCallback openContainer) {
                return FloatingActionButton.extended(
                  heroTag: null,
                  onPressed: openContainer,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('New Server'),
                );
              },
              openBuilder: (BuildContext context, VoidCallback closeContainer) {
                return const AddServerWindow();
              },
              openMockBuilder: (BuildContext context) {
                return const AddServerFlightShuttleMock();
              },
              openLayoutWrapper: (BuildContext context, Widget child) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                    child: child,
                  ),
                );
              },
            ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.colors, required this.theme});

  final ColorScheme colors;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: colors.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.dns_rounded,
                size: 40,
                color: colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'No servers yet',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap the button below to create your first Minecraft server.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
