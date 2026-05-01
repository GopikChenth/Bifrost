import 'dart:async';

import 'package:flutter/material.dart';
import 'package:bifrost/Components/add_server_window.dart';
import 'package:bifrost/Components/server_card.dart';
import 'package:bifrost/Pages/setingspage.dart';
import 'package:bifrost/Service/official_server_download_service.dart';
import 'package:bifrost/Service/server_storage_service.dart';
import 'package:bifrost/Utils/server_process_manager.dart';
import 'package:bifrost/Utils/server_state.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final List<Map<String, Object>> _servers = <Map<String, Object>>[];
  final OfficialServerDownloadService _officialServerDownloadService =
      const OfficialServerDownloadService();
  final ServerStorageService _serverStorageService =
      const ServerStorageService();
  final ServerProcessManager _serverProcessManager = ServerProcessManager();
  bool _isCreatingServer = false;
  String? _activeDownloadServerName;
  String? _activeDownloadFileName;
  int _downloadedBytes = 0;
  int? _totalDownloadBytes;

  void _openSettingsPage() {
    Navigator.of(context).push(
      MaterialPageRoute<SettingsPage>(
        builder: (BuildContext context) => const SettingsPage(),
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

    if (newServer == null) {
      return;
    }

    setState(() {
      _isCreatingServer = true;
      _activeDownloadServerName = newServer.name;
      _activeDownloadFileName = null;
      _downloadedBytes = 0;
      _totalDownloadBytes = null;
    });

    try {
      final ServerStorageResult storageResult = await _serverStorageService
          .createServerStructure(newServer);
      final OfficialServerArtifact artifact =
          await _officialServerDownloadService.resolveArtifact(newServer);

      if (mounted) {
        setState(() {
          _activeDownloadFileName = artifact.fileName;
        });
      }

      final OfficialServerDownloadResult downloadResult =
          await _officialServerDownloadService.downloadResolvedArtifact(
            artifact: artifact,
            storage: storageResult,
            onProgress: (int receivedBytes, int? totalBytes) {
              if (!mounted) {
                return;
              }

              setState(() {
                _downloadedBytes = receivedBytes;
                _totalDownloadBytes = totalBytes;
              });
            },
          );

      await _serverStorageService.writeDownloadMetadata(
        storage: storageResult,
        downloadMetadata: <String, Object?>{
          'project': downloadResult.artifact.projectName,
          'minecraftVersion': downloadResult.artifact.minecraftVersion,
          'fileName': downloadResult.artifact.fileName,
          'downloadUrl': downloadResult.artifact.downloadUrl.toString(),
          'sha1': downloadResult.artifact.sha1,
          'buildId': downloadResult.artifact.buildId,
          'channel': downloadResult.artifact.channel,
          'path': downloadResult.destinationFile.path,
        },
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _servers.add(<String, Object>{
          'name': newServer.name,
          'version': newServer.version,
          'type': newServer.serverType,
          'status': 'Offline',
          'memory': newServer.memoryLabel,
          'isOnline': false,
          'path': storageResult.serverDirectory.path,
        });
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Created ${newServer.name} and downloaded ${downloadResult.artifact.fileName}',
          ),
        ),
      );
    } on OfficialServerDownloadException catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } on ServerStorageException catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (_) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to create the selected server.')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isCreatingServer = false;
          _activeDownloadServerName = null;
          _activeDownloadFileName = null;
          _downloadedBytes = 0;
          _totalDownloadBytes = null;
        });
      }
    }
  }

  double? get _downloadProgress {
    final int? total = _totalDownloadBytes;
    if (total == null || total <= 0) {
      return null;
    }

    return (_downloadedBytes / total).clamp(0, 1);
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

  Future<void> _deleteServer(Map<String, Object> server) async {
    final bool? shouldDelete = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Delete Server'),
          content: Text(
            'Delete ${server['name'] as String}? This removes the server card and its local files.',
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

    if (shouldDelete != true) {
      return;
    }

    final String? serverPath = server['path'] as String?;

    try {
      if (serverPath != null && serverPath.trim().isNotEmpty) {
        await _serverStorageService.deleteServerDirectory(serverPath);
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _servers.remove(server);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Deleted ${server['name'] as String}')),
      );
    } on ServerStorageException catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _startServer(Map<String, Object> server) async {
    final String serverName = server['name']! as String;
    final String serverPath = server['path']! as String;

    await _serverProcessManager.startServer(
      serverName: serverName,
      serverPath: serverPath,
    );

    if (!mounted) {
      return;
    }

    final ServerRuntimeState state =
        _serverProcessManager
            .stateFor(serverName: serverName, serverPath: serverPath)
            .value;

    if (state.message != null && state.message!.isNotEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(state.message!)));
    }
  }

  Future<void> _stopServer(Map<String, Object> server) async {
    final String serverName = server['name']! as String;
    final String serverPath = server['path']! as String;

    try {
      await _serverProcessManager.stopServer(
        serverName: serverName,
        serverPath: serverPath,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
      return;
    }

    if (!mounted) {
      return;
    }

    final ServerRuntimeState state =
        _serverProcessManager
            .stateFor(serverName: serverName, serverPath: serverPath)
            .value;

    if (state.message != null && state.message!.isNotEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(state.message!)));
    }
  }

  String _statusLabelFor(ServerRuntimeState state) {
    switch (state.status) {
      case ServerRuntimeStatus.idle:
        return 'Offline';
      case ServerRuntimeStatus.starting:
        return 'Starting';
      case ServerRuntimeStatus.running:
        return 'Running';
      case ServerRuntimeStatus.stopping:
        return 'Stopping';
      case ServerRuntimeStatus.error:
        return 'Error';
    }
  }

  @override
  void dispose() {
    unawaited(_serverProcessManager.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> content = <Widget>[
      if (_isCreatingServer)
        ServerDownloadCard(
          serverName: _activeDownloadServerName ?? 'Preparing server files...',
          fileName: _activeDownloadFileName,
          progress: _downloadProgress,
          progressLabel: _totalDownloadBytes == null
              ? _formatBytes(_downloadedBytes)
              : '${_formatBytes(_downloadedBytes)} / ${_formatBytes(_totalDownloadBytes!)}',
        ),
      if (_isCreatingServer && _servers.isNotEmpty) const SizedBox(height: 12),
      ..._servers.map((Map<String, Object> server) {
        final String serverName = server['name']! as String;
        final String serverPath = server['path']! as String;

        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: ValueListenableBuilder<ServerRuntimeState>(
            valueListenable: _serverProcessManager.stateFor(
              serverName: serverName,
              serverPath: serverPath,
            ),
            builder: (
              BuildContext context,
              ServerRuntimeState runtimeState,
              Widget? child,
            ) {
              final bool isRunning =
                  runtimeState.status == ServerRuntimeStatus.running;
              final bool isBusy = runtimeState.isBusy;

              return ServerCard(
                name: serverName,
                version: server['version']! as String,
                serverType: server['type']! as String,
                statusLabel: _statusLabelFor(runtimeState),
                memoryLabel: server['memory']! as String,
                runtimeMessage: runtimeState.message,
                serverPath: server['path'] as String?,
                isOnline: isRunning,
                isBusy: isBusy || _isCreatingServer,
                onDelete: _isCreatingServer || isRunning || isBusy
                    ? null
                    : () {
                        _deleteServer(server);
                      },
                onStart: _isCreatingServer || isRunning || isBusy
                    ? null
                    : () {
                        _startServer(server);
                      },
                onStop: _isCreatingServer || !isRunning || isBusy
                    ? null
                    : () {
                        _stopServer(server);
                      },
              );
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
      body: content.isEmpty
          ? const SizedBox.shrink()
          : ListView(padding: const EdgeInsets.all(16), children: content),
      floatingActionButton: FloatingActionButton(
        onPressed: _isCreatingServer ? null : _openAddServerWindow,
        child: const Icon(Icons.add),
      ),
    );
  }
}
