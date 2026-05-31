import 'dart:io';
import 'dart:async';
import 'dart:math' as math;

import 'package:bifrost/Components/eulawindow.dart';
import 'package:bifrost/Components/server_navigation_drawer.dart';
import 'package:bifrost/Components/material_expressive_button.dart';
import 'package:bifrost/Models/bifrost_server.dart';
import 'package:bifrost/Pages/server_settings_page.dart';
import 'package:bifrost/Pages/server_terminal_page.dart';
import 'package:bifrost/Pages/server_players_page.dart';
import 'package:bifrost/Pages/server_world_page.dart';
import 'package:bifrost/Services/server_manager_service.dart';
import 'package:bifrost/Services/google_drive_sync_service.dart';
import 'package:bifrost/Utils/settings_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:googleapis/drive/v3.dart' as drive;

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

class _ServerPageState extends State<ServerPage>
    with SingleTickerProviderStateMixin {
  String? _localIpAddress;
  bool _isLoadingLocalIp = true;
  late final AnimationController _entranceController;
  int? _pressedButtonIndex;
  late final List<double> _activeProgresses;
  Timer? _refreshTimer;

  bool _isShared = false;
  bool _isReceived = false;
  String? _fileId;
  String? _ownerEmail;
  bool _isLocalSyncing = false;
  late final List<double> _activeSyncProgresses;
  String? _activeSyncMode;

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

  Future<void> _checkSharedWorldStatus() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final BifrostServer? server = widget.serverManager.serverByPath(widget.serverPath);
    if (server == null) return;

    final String? fileId = prefs.getString('gdrive_file_id_${server.path}');
    final String? lastSync = prefs.getString('gdrive_last_sync_${server.path}');
    final bool? isReceived = prefs.getBool('gdrive_is_received_${server.path}');
    final String? ownerEmail = prefs.getString('gdrive_owner_email_${server.path}');

    if (fileId != null || lastSync != null) {
      if (mounted) {
        setState(() {
          _isShared = true;
          _isReceived = isReceived ?? false;
          _fileId = fileId;
          _ownerEmail = ownerEmail;
        });
      }
    }

    var googleSignInUser = GoogleDriveSyncService.instance.currentUser;
    if (googleSignInUser == null) {
      try {
        googleSignInUser = await GoogleDriveSyncService.instance.signInSilently();
      } catch (_) {}
    }

    if (googleSignInUser != null) {
      try {
        final List<drive.File> files = await GoogleDriveSyncService.instance.listAvailableWorldSyncFiles();
        final String expectedName = 'bifrost_sync_${server.name.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_')}.zip';
        
        drive.File? matchedFile;
        for (final drive.File file in files) {
          if (file.name == expectedName) {
            matchedFile = file;
            break;
          }
        }

        if (matchedFile != null) {
          final bool isOwnedByMe = matchedFile.owners?.any(
            (owner) => owner.emailAddress?.toLowerCase() == googleSignInUser!.email.toLowerCase(),
          ) ?? false;

          final String owner = matchedFile.owners?.first.emailAddress ?? 'Unknown';

          await prefs.setString('gdrive_file_id_${server.path}', matchedFile.id!);
          await prefs.setBool('gdrive_is_received_${server.path}', !isOwnedByMe);
          await prefs.setString('gdrive_owner_email_${server.path}', owner);

          if (mounted) {
            setState(() {
              _isShared = true;
              _isReceived = !isOwnedByMe;
              _fileId = matchedFile?.id;
              _ownerEmail = owner;
            });
          }
        }
      } catch (e) {
        debugPrint('Error verifying sync status: $e');
      }
    }
  }

  Future<void> _syncPull(BifrostServer server) async {
    if (_isLocalSyncing || widget.serverManager.isSyncing) return;

    final String? fileId = _fileId;
    if (fileId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot sync pull: Google Drive file ID is missing.')),
      );
      return;
    }

    final bool confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Sync world from cloud?'),
          content: Text(
            _isReceived
                ? 'This will download and overwrite your current local world with the version shared by ${_ownerEmail ?? 'your friend'}.\n\n'
                  'A local backup of your current world will be saved automatically.'
                : 'This will download and overwrite your local world with your latest backup from Google Drive.\n\n'
                  'A local backup of your current world will be saved automatically.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Download & Sync'),
            ),
          ],
        );
      },
    ) ?? false;

    if (!confirm) return;

    setState(() {
      _isLocalSyncing = true;
      _activeSyncMode = 'pull';
      _activeSyncProgresses[0] = 1.0;
      _activeSyncProgresses[1] = 0.0;
    });

    final String? result = await widget.serverManager.downloadAndSyncWorldFromGoogleDrive(server, fileId);

    if (mounted) {
      setState(() {
        _isLocalSyncing = false;
        _activeSyncMode = null;
        _activeSyncProgresses[0] = 0.0;
        _activeSyncProgresses[1] = 0.0;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result ?? 'Sync completed.')),
      );
    }
  }

  Future<void> _syncPush(BifrostServer server) async {
    if (_isLocalSyncing || widget.serverManager.isSyncing) return;

    setState(() {
      _isLocalSyncing = true;
      _activeSyncMode = 'push';
      _activeSyncProgresses[0] = 0.0;
      _activeSyncProgresses[1] = 1.0;
    });

    final String? result = await widget.serverManager.syncWorldToGoogleDrive(server);

    if (mounted) {
      setState(() {
        _isLocalSyncing = false;
        _activeSyncMode = null;
        _activeSyncProgresses[0] = 0.0;
        _activeSyncProgresses[1] = 0.0;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result ?? 'Sync completed.')),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    final BifrostServer? server = widget.serverManager.serverByPath(widget.serverPath);
    _activeProgresses = <double>[
      server != null && server.isBusy && !server.isOnline ? 1.0 : 0.0,
      server != null && server.isOnline ? 1.0 : 0.0,
      0.0,
    ];
    _activeSyncProgresses = <double>[
      0.0,
      0.0,
    ];
    widget.serverManager.addListener(_refresh);
    _loadLocalIpAddress();
    _checkSharedWorldStatus();
    _refreshTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      final BifrostServer? s = widget.serverManager.serverByPath(widget.serverPath);
      if (s != null && (s.isOnline || s.isBusy)) {
        widget.serverManager.refreshServerStatusFor(widget.serverPath);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (AppSettings.disableAnimations) {
        _entranceController.value = 1.0;
      } else {
        _entranceController.forward();
      }
    });
  }

  @override
  void didUpdateWidget(ServerPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.serverPath != widget.serverPath || oldWidget.serverManager != widget.serverManager) {
      oldWidget.serverManager.removeListener(_refresh);
      widget.serverManager.addListener(_refresh);
      _refresh();
    }
  }

  void _refresh() {
    if (mounted) {
      final BifrostServer? server = widget.serverManager.serverByPath(widget.serverPath);
      if (server != null) {
        _activeProgresses[0] = server.isBusy && !server.isOnline ? 1.0 : 0.0;
        _activeProgresses[1] = server.isOnline ? 1.0 : 0.0;
      }
      _activeSyncProgresses[0] = _activeSyncMode == 'pull' ? 1.0 : 0.0;
      _activeSyncProgresses[1] = _activeSyncMode == 'push' ? 1.0 : 0.0;
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
    _refreshTimer?.cancel();
    _entranceController.dispose();
    widget.serverManager.removeListener(_refresh);
    super.dispose();
  }

  Widget _staggeredChild(int index, int total, Widget child) {
    final double start = math.min(index / math.max(total, 1), 0.7);
    final double end = math.min(start + 0.5, 1.0);
    return AnimatedBuilder(
      animation: _entranceController,
      builder: (BuildContext context, Widget? c) {
        final double t = Interval(start, end, curve: Curves.easeOutCubic)
            .transform(_entranceController.value);
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, 24 * (1 - t)),
            child: c,
          ),
        );
      },
      child: child,
    );
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

    final int totalSections = _isShared ? 6 : 5;

    return Scaffold(
      endDrawer: ServerNavigationDrawer(
        server: server,
        selectedIndex: ServerDrawerIndex.dashboard,
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
          _staggeredChild(0, totalSections, _HeroPanel(server: server)),
          const SizedBox(height: 12),
          _staggeredChild(
            1,
            totalSections,
            ExpressiveButtonRow(
              weights: <double>[
                1.5 + (1.5 * _activeProgresses[0]),
                1.5 + (1.5 * _activeProgresses[1]),
                1.5 + (1.5 * _activeProgresses[2]),
              ],
              children: <Widget>[
                MaterialExpressiveButton(
                  onPressed: canStart
                      ? () {
                          _startServer(server);
                        }
                      : null,
                  icon: const Icon(Icons.rocket_launch_rounded),
                  label: const Text('Start'),
                  backgroundColor: colors.primary,
                  foregroundColor: colors.onPrimary,
                  pressedBackgroundColor: colors.primaryContainer,
                  pressedForegroundColor: colors.onPrimaryContainer,
                  expanded: true,
                  isActive: server.isBusy && !server.isOnline,
                  siblingDirection: _pressedButtonIndex == null || _pressedButtonIndex == 0 ? 0.0 : (0 < _pressedButtonIndex! ? -1.0 : 1.0),
                  hideLabelWhenInactive: true,
                  onPressStateChanged: (bool isPressed) {
                    setState(() {
                      _pressedButtonIndex = isPressed ? 0 : null;
                    });
                  },
                  onActiveProgressChanged: (double progress) {
                    setState(() {
                      _activeProgresses[0] = progress;
                    });
                  },
                ),
                MaterialExpressiveButton(
                  onPressed: canStop
                      ? () {
                          widget.serverManager.stopServer(server);
                        }
                      : null,
                  icon: const Icon(Icons.stop_circle_rounded),
                  label: const Text('Stop'),
                  backgroundColor: colors.errorContainer,
                  foregroundColor: colors.onErrorContainer,
                  pressedBackgroundColor: colors.error,
                  pressedForegroundColor: colors.onError,
                  expanded: true,
                  isActive: server.isOnline,
                  siblingDirection: _pressedButtonIndex == null || _pressedButtonIndex == 1 ? 0.0 : (1 < _pressedButtonIndex! ? -1.0 : 1.0),
                  hideLabelWhenInactive: true,
                  onPressStateChanged: (bool isPressed) {
                    setState(() {
                      _pressedButtonIndex = isPressed ? 1 : null;
                    });
                  },
                  onActiveProgressChanged: (double progress) {
                    setState(() {
                      _activeProgresses[1] = progress;
                    });
                  },
                ),
                MaterialExpressiveButton(
                  onPressed: canRestart
                      ? () {
                          widget.serverManager.restartServer(server);
                        }
                      : null,
                  icon: const Icon(Icons.restart_alt_rounded),
                  label: const Text('Restart'),
                  backgroundColor: colors.secondaryContainer,
                  foregroundColor: colors.onSecondaryContainer,
                  pressedBackgroundColor: colors.secondary,
                  pressedForegroundColor: colors.onSecondary,
                  expanded: true,
                  isActive: server.status == 'Restarting',
                  siblingDirection: _pressedButtonIndex == null || _pressedButtonIndex == 2 ? 0.0 : (2 < _pressedButtonIndex! ? -1.0 : 1.0),
                  hideLabelWhenInactive: true,
                  onPressStateChanged: (bool isPressed) {
                    setState(() {
                      _pressedButtonIndex = isPressed ? 2 : null;
                    });
                  },
                  onActiveProgressChanged: (double progress) {
                    setState(() {
                      _activeProgresses[2] = progress;
                    });
                  },
                ),
              ],
            ),
          ),
          if (_isShared) ...[
            const SizedBox(height: 12),
            _staggeredChild(
              2,
              totalSections,
              _CloudSyncPanel(
                server: server,
                isReceived: _isReceived,
                ownerEmail: _ownerEmail,
                lastSyncTime: widget.serverManager.lastSyncTimeFor(server.path),
                isSyncing: _isLocalSyncing || widget.serverManager.isSyncing,
                activeSyncMode: _activeSyncMode,
                activeSyncProgresses: _activeSyncProgresses,
                onPullPressed: () => _syncPull(server),
                onPushPressed: () => _syncPush(server),
              ),
            ),
          ],
          const SizedBox(height: 12),
          _staggeredChild(
            _isShared ? 3 : 2,
            totalSections,
            _LocalNetworkPanel(
              isLoading: _isLoadingLocalIp,
              ipAddress: _localIpAddress,
            ),
          ),
          const SizedBox(height: 12),
          _staggeredChild(
            _isShared ? 4 : 3,
            totalSections,
            _ServerDetailsPanel(
              server: server,
              serverManager: widget.serverManager,
            ),
          ),
          const SizedBox(height: 12),
          _staggeredChild(
            _isShared ? 5 : 4,
            totalSections,
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Runtime Message',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
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

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 3000),
      builder: (BuildContext context, double value, Widget? child) {
        return Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: <Color>[
                colors.primaryContainer,
                colors.tertiaryContainer,
              ],
              begin: Alignment(-1.0 + value * 0.4, -1.0),
              end: Alignment(1.0 - value * 0.4, 1.0),
            ),
            borderRadius: BorderRadius.circular(28),
          ),
          child: child,
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            Icons.storage_rounded,
            size: 32,
            color: colors.onPrimaryContainer,
          ),
          const SizedBox(height: 10),
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
              color: colors.onPrimaryContainer.withValues(alpha: 0.78),
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
    final String? address =
        ipAddress == null ? null : '${ipAddress!}:$_minecraftPort';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
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
                    color: colors.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                SelectableText(
                  isLoading
                      ? 'Finding device IP...'
                      : address ?? 'No LAN IP found. Connect to Wi-Fi.',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: address == null ? colors.onSurfaceVariant : null,
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

class _ServerDetailsPanel extends StatelessWidget {
  const _ServerDetailsPanel({
    required this.server,
    required this.serverManager,
  });

  final BifrostServer server;
  final ServerManagerService serverManager;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;

    final int memoryMb = serverManager.memoryUsageFor(server.path);
    final String ramText = server.isOnline
        ? (memoryMb > 0 ? '$memoryMb MB' : 'Querying...')
        : 'Offline';

    final List<String> onlinePlayers = serverManager.onlinePlayersFor(server.path);
    final String playersText = server.isOnline
        ? (onlinePlayers.isEmpty
            ? '0 online'
            : '${onlinePlayers.length} online (${onlinePlayers.join(", ")})')
        : 'Offline';

    Widget buildItem(IconData icon, String label, String value) {
      return Row(
        children: <Widget>[
          Icon(icon, size: 18, color: colors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.onSurfaceVariant,
                    fontSize: 10,
                  ),
                ),
                Text(
                  value,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      );
    }

    final bool isWide = MediaQuery.sizeOf(context).width > 600;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (isWide)
            Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    children: <Widget>[
                      buildItem(Icons.dns_rounded, 'Server Type', server.type),
                      const SizedBox(height: 10),
                      buildItem(Icons.groups_rounded, 'Players Online', playersText),
                      const SizedBox(height: 10),
                      buildItem(Icons.speed_rounded, 'RAM Usage', ramText),
                      const SizedBox(height: 10),
                      buildItem(Icons.power_settings_new_rounded, 'Runtime State', server.status),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    children: <Widget>[
                      buildItem(Icons.new_releases_rounded, 'Version', server.version),
                      const SizedBox(height: 10),
                      buildItem(Icons.memory_rounded, 'Allocated RAM', server.memoryLabel),
                      const SizedBox(height: 10),
                      buildItem(Icons.terminal_rounded, 'Console', server.consoleLabel),
                      const SizedBox(height: 10),
                      const SizedBox(height: 28), // Spacer to align bottom row
                    ],
                  ),
                ),
              ],
            )
          else
            Column(
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(child: buildItem(Icons.dns_rounded, 'Type', server.type)),
                    const SizedBox(width: 10),
                    Expanded(child: buildItem(Icons.new_releases_rounded, 'Version', server.version)),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    Expanded(child: buildItem(Icons.groups_rounded, 'Players', playersText)),
                    const SizedBox(width: 10),
                    Expanded(child: buildItem(Icons.memory_rounded, 'Allocated RAM', server.memoryLabel)),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    Expanded(child: buildItem(Icons.speed_rounded, 'RAM Usage', ramText)),
                    const SizedBox(width: 10),
                    Expanded(child: buildItem(Icons.terminal_rounded, 'Console', server.consoleLabel)),
                  ],
                ),
                const SizedBox(height: 12),
                buildItem(Icons.power_settings_new_rounded, 'Runtime State', server.status),
              ],
            ),
          const Divider(height: 20),
          Row(
            children: <Widget>[
              Icon(Icons.folder_rounded, size: 18, color: colors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Path',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colors.onSurfaceVariant,
                        fontSize: 10,
                      ),
                    ),
                    SelectableText(
                      server.path,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        fontSize: 11,
                      ),
                    ),
                  ],
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

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        color:
            isOnline ? colors.primaryContainer : colors.surfaceContainerHigh,
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

class _CloudSyncPanel extends StatefulWidget {
  const _CloudSyncPanel({
    required this.server,
    required this.isReceived,
    required this.ownerEmail,
    required this.lastSyncTime,
    required this.isSyncing,
    required this.activeSyncMode,
    required this.activeSyncProgresses,
    required this.onPullPressed,
    required this.onPushPressed,
  });

  final BifrostServer server;
  final bool isReceived;
  final String? ownerEmail;
  final DateTime? lastSyncTime;
  final bool isSyncing;
  final String? activeSyncMode;
  final List<double> activeSyncProgresses;
  final VoidCallback onPullPressed;
  final VoidCallback onPushPressed;

  @override
  State<_CloudSyncPanel> createState() => _CloudSyncPanelState();
}

class _CloudSyncPanelState extends State<_CloudSyncPanel> {
  int? _pressedButtonIndex;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;

    final String formattedSyncTime = widget.lastSyncTime != null
        ? _formatDateTime(widget.lastSyncTime!)
        : 'Never';

    final IconData statusIcon = widget.isSyncing
        ? Icons.cloud_sync_rounded
        : (widget.isReceived ? Icons.cloud_download_rounded : Icons.cloud_done_rounded);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
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
            child: Icon(
              statusIcon,
              color: colors.onPrimaryContainer,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Shared World',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: colors.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Last Synced: $formattedSyncTime',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 180,
            child: ExpressiveButtonRow(
              spacing: 3.0,
              weights: <double>[
                1.5 + (1.5 * widget.activeSyncProgresses[0]),
                1.5 + (1.5 * widget.activeSyncProgresses[1]),
              ],
              children: <Widget>[
                MaterialExpressiveButton(
                  onPressed: widget.isSyncing ? null : widget.onPullPressed,
                  icon: const Icon(Icons.download_rounded),
                  label: const Text('Pull'),
                  backgroundColor: colors.secondaryContainer,
                  foregroundColor: colors.onSecondaryContainer,
                  pressedBackgroundColor: colors.secondary,
                  pressedForegroundColor: colors.onSecondary,
                  expanded: true,
                  isActive: widget.activeSyncMode == 'pull',
                  siblingDirection: _pressedButtonIndex == null || _pressedButtonIndex == 0
                      ? 0.0
                      : (0 < _pressedButtonIndex! ? -1.0 : 1.0),
                  hideLabelWhenInactive: widget.isSyncing,
                  onPressStateChanged: (bool isPressed) {
                    setState(() {
                      _pressedButtonIndex = isPressed ? 0 : null;
                    });
                  },
                  borderRadiusBuilder: (double radius) {
                    return BorderRadius.only(
                      topLeft: Radius.circular(radius),
                      bottomLeft: Radius.circular(radius),
                      topRight: Radius.circular(radius * 0.3),
                      bottomRight: Radius.circular(radius * 0.3),
                    );
                  },
                ),
                MaterialExpressiveButton(
                  onPressed: widget.isSyncing ? null : widget.onPushPressed,
                  icon: const Icon(Icons.upload_rounded),
                  label: const Text('Push'),
                  backgroundColor: colors.tertiaryContainer,
                  foregroundColor: colors.onTertiaryContainer,
                  pressedBackgroundColor: colors.tertiary,
                  pressedForegroundColor: colors.onTertiary,
                  expanded: true,
                  isActive: widget.activeSyncMode == 'push',
                  siblingDirection: _pressedButtonIndex == null || _pressedButtonIndex == 1
                      ? 0.0
                      : (1 < _pressedButtonIndex! ? -1.0 : 1.0),
                  hideLabelWhenInactive: widget.isSyncing,
                  onPressStateChanged: (bool isPressed) {
                    setState(() {
                      _pressedButtonIndex = isPressed ? 1 : null;
                    });
                  },
                  borderRadiusBuilder: (double radius) {
                    return BorderRadius.only(
                      topLeft: Radius.circular(radius * 0.3),
                      bottomLeft: Radius.circular(radius * 0.3),
                      topRight: Radius.circular(radius),
                      bottomRight: Radius.circular(radius),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    final DateTime local = dateTime.toLocal();
    return '${local.month}/${local.day}/${local.year} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
}

