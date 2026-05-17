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
    return AlertDialog(
      title: const Text('Accept Minecraft EULA'),
      content: const Text(
        'You must accept the Minecraft server EULA before this server can start. Bifrost will only write eula=true after you accept.',
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () {
            Navigator.of(context).pop(false);
          },
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(context).pop(true);
          },
          child: const Text('Accept'),
        ),
      ],
    );
  }
}
