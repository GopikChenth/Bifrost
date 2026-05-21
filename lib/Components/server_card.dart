import 'package:bifrost/Components/material_expressive_button.dart';
import 'package:bifrost/Services/file_manager_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class ServerCard extends StatefulWidget {
  const ServerCard({
    super.key,
    required this.name,
    required this.version,
    required this.serverType,
    required this.statusLabel,
    required this.memoryLabel,
    this.serverPath,
    this.onDelete,
    this.onStartServer,
    this.onStopServer,
    this.onOpenDashboard,
    this.isBusy = false,
    this.isOnline = false,
    this.consoleLabel = 'Ready',
    this.runtimeMessage,
  });

  final String name;
  final String version;
  final String serverType;
  final String statusLabel;
  final String memoryLabel;
  final String? serverPath;
  final VoidCallback? onDelete;
  final VoidCallback? onStartServer;
  final VoidCallback? onStopServer;
  final VoidCallback? onOpenDashboard;
  final bool isBusy;
  final bool isOnline;
  final String consoleLabel;
  final String? runtimeMessage;

  @override
  State<ServerCard> createState() => _ServerCardState();
}

class _ServerCardState extends State<ServerCard> {
  static const FileManagerService _fileManagerService = FileManagerService();
  double _scale = 1.0;
  int? _pressedButtonIndex;

  Future<void> _openServerFolder(BuildContext context) async {
    final String? path = widget.serverPath;
    if (path == null || path.trim().isEmpty) {
      return;
    }

    try {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        await _fileManagerService.openFolder(path);
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Opening folders is currently configured for Android.'),
        ),
      );
    } on FileManagerServiceException catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Unable to open the server folder in the file manager.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;

    return AnimatedScale(
      scale: _scale,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutBack,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.onOpenDashboard,
          onTapDown: (_) => setState(() => _scale = 0.97),
          onTapUp: (_) => setState(() => _scale = 1.0),
          onTapCancel: () => setState(() => _scale = 1.0),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: widget.isOnline
                            ? colors.primaryContainer
                            : colors.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        Icons.storage_rounded,
                        size: 22,
                        color: widget.isOnline
                            ? colors.onPrimaryContainer
                            : colors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            widget.name,
                            style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${widget.serverType} • ${widget.version}',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _StatusBadge(
                      label: widget.statusLabel,
                      isOnline: widget.isOnline,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _ServerMetric(
                        icon: Icons.memory_rounded,
                        label: 'RAM',
                        value: widget.memoryLabel,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _ServerMetric(
                        icon: Icons.terminal_rounded,
                        label: 'Console',
                        value: widget.consoleLabel,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: MaterialExpressiveButton(
                        onPressed: widget.isBusy || widget.isOnline
                            ? null
                            : widget.onStartServer,
                        icon: const Icon(Icons.rocket_launch_rounded),
                        label: const Text('Start'),
                        backgroundColor: colors.primary,
                        foregroundColor: colors.onPrimary,
                        pressedBackgroundColor: colors.primaryContainer,
                        pressedForegroundColor: colors.onPrimaryContainer,
                        expanded: true,
                        isActive: widget.isBusy && !widget.isOnline,
                        siblingDirection: _pressedButtonIndex == null || _pressedButtonIndex == 0 ? 0.0 : (0 < _pressedButtonIndex! ? -1.0 : 1.0),
                        onPressStateChanged: (bool isPressed) {
                          setState(() {
                            _pressedButtonIndex = isPressed ? 0 : null;
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: MaterialExpressiveButton(
                        onPressed: widget.isOnline ? widget.onStopServer : null,
                        icon: const Icon(Icons.stop_circle_rounded),
                        label: const Text('Stop'),
                        backgroundColor: colors.errorContainer,
                        foregroundColor: colors.onErrorContainer,
                        pressedBackgroundColor: colors.error,
                        pressedForegroundColor: colors.onError,
                        expanded: true,
                        isActive: widget.isOnline,
                        siblingDirection: _pressedButtonIndex == null || _pressedButtonIndex == 1 ? 0.0 : (1 < _pressedButtonIndex! ? -1.0 : 1.0),
                        onPressStateChanged: (bool isPressed) {
                          setState(() {
                            _pressedButtonIndex = isPressed ? 1 : null;
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    MaterialExpressiveButton(
                      onPressed: widget.serverPath == null
                          ? null
                          : () => _openServerFolder(context),
                      tooltip: 'Open Folder',
                      icon: const Icon(Icons.folder_open_rounded),
                      backgroundColor: colors.secondaryContainer,
                      foregroundColor: colors.onSecondaryContainer,
                      pressedBackgroundColor: colors.secondary,
                      pressedForegroundColor: colors.onSecondary,
                      isActive: false,
                      siblingDirection: _pressedButtonIndex == null || _pressedButtonIndex == 2 ? 0.0 : (2 < _pressedButtonIndex! ? -1.0 : 1.0),
                      onPressStateChanged: (bool isPressed) {
                        setState(() {
                          _pressedButtonIndex = isPressed ? 2 : null;
                        });
                      },
                    ),
                    const SizedBox(width: 8),
                    MaterialExpressiveButton(
                      onPressed: widget.isBusy ? null : widget.onDelete,
                      tooltip: 'Delete',
                      icon: const Icon(Icons.delete_outline_rounded),
                      backgroundColor: colors.surfaceContainerHighest,
                      foregroundColor: colors.error,
                      pressedBackgroundColor: colors.errorContainer,
                      pressedForegroundColor: colors.onErrorContainer,
                      isActive: false,
                      siblingDirection: _pressedButtonIndex == null || _pressedButtonIndex == 3 ? 0.0 : (3 < _pressedButtonIndex! ? -1.0 : 1.0),
                      onPressStateChanged: (bool isPressed) {
                        setState(() {
                          _pressedButtonIndex = isPressed ? 3 : null;
                        });
                      },
                    ),
                  ],
                ),
                if (widget.runtimeMessage != null &&
                    widget.runtimeMessage!.trim().isNotEmpty) ...<Widget>[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      widget.runtimeMessage!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatefulWidget {
  const _StatusBadge({
    required this.label,
    required this.isOnline,
  });

  final String label;
  final bool isOnline;

  @override
  State<_StatusBadge> createState() => _StatusBadgeState();
}

class _StatusBadgeState extends State<_StatusBadge>
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
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.6).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    if (widget.isOnline) {
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(_StatusBadge oldWidget) {
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: widget.isOnline
            ? colors.primaryContainer
            : colors.surfaceContainerHighest,
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

class ServerDownloadCard extends StatelessWidget {
  const ServerDownloadCard({
    super.key,
    required this.serverName,
    required this.progressLabel,
    this.fileName,
    this.progress,
  });

  final String serverName;
  final String progressLabel;
  final String? fileName;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.cloud_download_rounded, color: colors.primary),
                const SizedBox(width: 10),
                Text(
                  'Downloading Server',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(serverName, style: theme.textTheme.bodyMedium),
            if (fileName != null) ...<Widget>[
              const SizedBox(height: 4),
              Text(
                fileName!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(value: progress, minHeight: 6),
            ),
            const SizedBox(height: 10),
            Text(
              progressLabel,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ServerMetric extends StatelessWidget {
  const _ServerMetric({
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
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 18, color: colors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
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


