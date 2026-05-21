import 'package:flutter/material.dart';

Future<bool?> showEulaWindow(BuildContext context) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext context) {
      return const EulaWindow();
    },
  );
}

class EulaWindow extends StatelessWidget {
  const EulaWindow({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;

    return AlertDialog(
      icon: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: colors.primaryContainer,
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.gavel_rounded,
          color: colors.onPrimaryContainer,
          size: 28,
        ),
      ),
      title: const Text('Minecraft EULA'),
      content: Text(
        'You must accept the Minecraft End User License Agreement before this server can start.\n\n'
        'By accepting, Bifrost will write eula=true to eula.txt in your server directory.',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: colors.onSurfaceVariant,
        ),
      ),
      actions: <Widget>[
        OutlinedButton(
          onPressed: () {
            Navigator.of(context).pop(false);
          },
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: () {
            Navigator.of(context).pop(true);
          },
          icon: const Icon(Icons.check_rounded, size: 18),
          label: const Text('Accept EULA'),
        ),
      ],
    );
  }
}
