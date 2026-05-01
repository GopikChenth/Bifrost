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
    this.runtimeMessage,
    this.serverPath,
    this.onDelete,
    this.onStart,
    this.onStop,
    this.isBusy = false,
    this.isOnline = false,
  });

  final String name;
  final String version;
  final String serverType;
  final String statusLabel;
  final String memoryLabel;
  final String? runtimeMessage;
  final String? serverPath;
  final VoidCallback? onDelete;
  final VoidCallback? onStart;
  final VoidCallback? onStop;
  final bool isBusy;
  final bool isOnline;

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
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: colors.outlineVariant),
          borderRadius: BorderRadius.circular(24),
        ),
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(Icons.storage_rounded, color: accent),
                ),
                const SizedBox(width: 12),
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
                      const SizedBox(height: 4),
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
                    horizontal: 10,
                    vertical: 6,
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
                const SizedBox(width: 8),
                IconButton(
                  onPressed: serverPath == null
                      ? null
                      : () {
                          _openServerFolder(context);
                        },
                  tooltip: 'Open Folder',
                  icon: const Icon(Icons.folder_open_rounded),
                ),
                IconButton(
                  onPressed: isBusy ? null : onDelete,
                  tooltip: 'Delete Server',
                  icon: Icon(Icons.delete_outline_rounded, color: colors.error),
                ),
              ],
            ),
            if (runtimeMessage != null && runtimeMessage!.trim().isNotEmpty) ...<Widget>[
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colors.errorContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  runtimeMessage!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onErrorContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 18),
            Row(
              children: <Widget>[
                Expanded(
                  child: _ServerMetric(
                    icon: Icons.memory_rounded,
                    label: 'Allocated RAM',
                    value: memoryLabel,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ServerMetric(
                    icon: Icons.terminal_rounded,
                    label: 'Console',
                    value: 'Ready',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              children: <Widget>[
                Expanded(
                  child: FilledButton.icon(
                    onPressed: isBusy ? null : onStart,
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Start'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: isBusy ? null : onStop,
                    icon: const Icon(Icons.stop_rounded),
                    label: const Text('Stop'),
                  ),
                ),
              ],
            ),
          ],
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
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
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
