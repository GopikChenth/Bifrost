import 'package:bifrost/Components/add_server_window.dart';
import 'package:bifrost/Components/server_card.dart';
import 'package:bifrost/Models/bifrost_server.dart';
import 'package:bifrost/Pages/serverpage.dart';
import 'package:bifrost/Pages/settingspage.dart';
import 'package:bifrost/Services/server_manager_service.dart';
import 'package:flutter/material.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final ServerManagerService _serverManager;

  @override
  void initState() {
    super.initState();
    _serverManager = ServerManagerService()..addListener(_refresh);
    _serverManager.loadStoredServers();
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

  Future<void> _openAddServerWindow() async {
    final AddServerResult? newServer = await showDialog<AddServerResult>(
      context: context,
      builder: (BuildContext dialogContext) {
        return const AddServerWindow();
      },
    );

    if (newServer == null || !mounted) {
      return;
    }

    final String? message = await _serverManager.createServer(newServer);
    if (!mounted || message == null) {
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _deleteServer(BifrostServer server) async {
    final bool? shouldDelete = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Delete Server'),
          content: Text(
            'Delete ${server.name}? This removes the server card and its local files.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
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
    _serverManager
      ..removeListener(_refresh)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> content = <Widget>[
      if (_serverManager.isCreatingServer)
        ServerDownloadCard(
          serverName:
              _serverManager.activeDownloadServerName ??
              'Preparing server files...',
          fileName: _serverManager.activeDownloadFileName,
          progress: _serverManager.downloadProgress,
          progressLabel: _serverManager.totalDownloadBytes == null
              ? _formatBytes(_serverManager.downloadedBytes)
              : '${_formatBytes(_serverManager.downloadedBytes)} / ${_formatBytes(_serverManager.totalDownloadBytes!)}',
        ),
      if (_serverManager.isCreatingServer && _serverManager.servers.isNotEmpty)
        const SizedBox(height: 12),
      ..._serverManager.servers.map((BifrostServer server) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: ServerCard(
            name: server.name,
            version: server.version,
            serverType: server.type,
            statusLabel: server.status,
            memoryLabel: server.memoryLabel,
            serverPath: server.path,
            isOnline: server.isOnline,
            isBusy: _serverManager.isCreatingServer || server.isBusy,
            consoleLabel: server.consoleLabel,
            runtimeMessage: server.runtimeMessage,
            onStartServer: _serverManager.isCreatingServer
                ? null
                : () {
                    _serverManager.startServer(server);
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
        );
      }),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bifrost Servers'),
        actions: <Widget>[
          IconButton(
            onPressed: _openSettingsPage,
            icon: const Icon(Icons.settings_rounded),
            tooltip: 'Settings',
          ),
        ],
      ),
      body: _serverManager.isLoadingServers
          ? const Center(child: CircularProgressIndicator())
          : content.isEmpty
          ? const Center(child: Text('No servers found yet.'))
          : ListView(padding: const EdgeInsets.all(16), children: content),
      floatingActionButton: FloatingActionButton(
        onPressed: _serverManager.isCreatingServer
            ? null
            : _openAddServerWindow,
        child: const Icon(Icons.add),
      ),
    );
  }
}
