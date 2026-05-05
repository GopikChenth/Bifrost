import 'package:bifrost/Services/file_manager_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class ServerCard extends StatelessWidget {
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

  static const FileManagerService _fileManagerService = FileManagerService();

  Future<void> _openServerFolder(BuildContext context) async {
    final String? path = serverPath;
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
          content: Text('Unable to open the server folder in the file manager.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final Color accent = isOnline ? colors.primary : colors.outline;
    final Color badgeBackground = isOnline
        ? colors.primaryContainer
        : colors.surfaceContainerHighest;
    final Color badgeForeground = isOnline
        ? colors.onPrimaryContainer
        : colors.onSurfaceVariant;

    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: InkWell(
        onTap: onOpenDashboard,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: colors.outlineVariant),
            borderRadius: BorderRadius.circular(20),
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.storage_rounded, size: 20, color: accent),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        name,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$serverType • $version',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: badgeBackground,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    statusLabel,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: badgeForeground,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: serverPath == null
                      ? null
                      : () {
                          _openServerFolder(context);
                        },
                  tooltip: 'Open Folder',
                  icon: const Icon(Icons.folder_open_rounded),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: isBusy ? null : onDelete,
                  tooltip: 'Delete Server',
                  icon: Icon(Icons.delete_outline_rounded, color: colors.error),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: _ServerMetric(
                    icon: Icons.memory_rounded,
                    label: 'Allocated RAM',
                    value: memoryLabel,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _ServerMetric(
                    icon: Icons.terminal_rounded,
                    label: 'Console',
                    value: consoleLabel,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                FilledButton.tonalIcon(
                  onPressed: isBusy || isOnline ? null : onStartServer,
                  icon: const Icon(Icons.rocket_launch_rounded),
                  label: const Text('Start Server'),
                ),
                FilledButton.tonalIcon(
                  onPressed: isOnline ? onStopServer : null,
                  icon: const Icon(Icons.stop_circle_rounded),
                  label: const Text('Stop Server'),
                  style: FilledButton.styleFrom(
                    foregroundColor: colors.onErrorContainer,
                    backgroundColor: colors.errorContainer,
                  ),
                ),
              ],
            ),
            if (runtimeMessage != null && runtimeMessage!.trim().isNotEmpty) ...<
              Widget
            >[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  runtimeMessage!,
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
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          border: Border.all(color: colors.outlineVariant),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Downloading Server',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
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
            const SizedBox(height: 14),
            LinearProgressIndicator(value: progress),
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
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 16, color: colors.primary),
          const SizedBox(width: 8),
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
                const SizedBox(height: 1),
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
