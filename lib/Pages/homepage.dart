import 'dart:async';

import 'package:flutter/material.dart';
import 'package:bifrost/Components/add_server_window.dart';
import 'package:bifrost/Components/server_card.dart';
import 'package:bifrost/Pages/setingspage.dart';
import 'package:bifrost/Service/official_server_download_service.dart';
import 'package:bifrost/Service/server_storage_service.dart';
import 'package:bifrost/Services/local_runtime_service.dart';
import 'package:bifrost/Utils/local_runtime_models.dart';

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
  final LocalRuntimeService _localRuntimeService =
      const LocalRuntimeService();
  bool _isCreatingServer = false;
  String? _activeDownloadServerName;
  String? _activeDownloadFileName;
  int _downloadedBytes = 0;
  int? _totalDownloadBytes;
  final Map<String, bool> _runtimeTestBusyByServer = <String, bool>{};
  final Map<String, String> _runtimeMessageByServer = <String, String>{};
  final Map<String, String> _consoleLabelByServer = <String, String>{};
  final Map<String, String> _serverStatusLabelByServer = <String, String>{};
  Timer? _serverStatusPollTimer;

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
        if (serverPath != null) {
          _runtimeTestBusyByServer.remove(serverPath);
          _runtimeMessageByServer.remove(serverPath);
          _consoleLabelByServer.remove(serverPath);
        }
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

  Future<void> _testRuntimeForServer(Map<String, Object> server) async {
    final String? serverPath = server['path'] as String?;
    if (serverPath == null || serverPath.trim().isEmpty) {
      return;
    }

    setState(() {
      _runtimeTestBusyByServer[serverPath] = true;
      _consoleLabelByServer[serverPath] = 'Testing JVM';
          _runtimeMessageByServer[serverPath] =
          'Preparing bundled runtime and running java -version using the local JVM launch model.';
    });

    try {
      final LocalRuntimeStatus preparedStatus =
          await _localRuntimeService.prepareBundledRuntimeHome();
      final LocalRuntimeTestResult testResult = await _localRuntimeService
          .runJavaVersion(workingDirectory: serverPath);

      if (!mounted) {
        return;
      }

      final bool passed = testResult.exitCode == 0;
      setState(() {
        _consoleLabelByServer[serverPath] = passed ? 'Runtime OK' : 'Runtime Failed';
        _runtimeMessageByServer[serverPath] =
            'Local runtime test exit=${testResult.exitCode}. '
            'home=${testResult.status.runtimeHomeExists}, '
            'release=${testResult.status.releaseExists}, '
            'libjli=${testResult.status.libjliExists}, '
            'libjvm=${testResult.status.libjvmExists}, '
            'modules=${testResult.status.modulesExists}. '
            'Prepared home: ${preparedStatus.runtimeHome}.';
      });
    } on LocalRuntimeServiceException catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _consoleLabelByServer[serverPath] = 'Runtime Error';
        _runtimeMessageByServer[serverPath] = error.message;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _consoleLabelByServer[serverPath] = 'Runtime Error';
        _runtimeMessageByServer[serverPath] =
            'Unable to complete the local runtime test.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _runtimeTestBusyByServer[serverPath] = false;
        });
      }
    }
  }

  Future<void> _startServer(Map<String, Object> server) async {
    final String? serverPath = server['path'] as String?;
    final String? memoryLabel = server['memory'] as String?;

    if (serverPath == null || memoryLabel == null) {
      return;
    }

    setState(() {
      _runtimeTestBusyByServer[serverPath] = true;
      _serverStatusLabelByServer[serverPath] = 'Starting';
      _consoleLabelByServer[serverPath] = 'Bootstrapping';
      _runtimeMessageByServer[serverPath] =
          'Preparing eula.txt, resolving the downloaded jar, and launching the local JVM.';
    });

    try {
      final ServerLaunchConfig launchConfig = await _serverStorageService
          .prepareServerLaunch(serverPath: serverPath, memoryLabel: memoryLabel);

      final LocalServerStatus status = await _localRuntimeService.startServer(
        serverPath: launchConfig.serverDirectory.path,
        jarPath: launchConfig.jarFilePath,
        maxRamMb: launchConfig.maxRamMb,
      );

      if (!mounted) {
        return;
      }

      _applyServerStatus(
        serverPath: serverPath,
        status: status,
        fallbackMessage:
            'Launching ${launchConfig.jarFilePath} with ${launchConfig.maxRamMb} MB.',
      );
      _startServerStatusPolling();
    } on ServerStorageException catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _runtimeTestBusyByServer[serverPath] = false;
        _serverStatusLabelByServer[serverPath] = 'Error';
        _consoleLabelByServer[serverPath] = 'Launch Failed';
        _runtimeMessageByServer[serverPath] = error.message;
      });
    } on LocalRuntimeServiceException catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _runtimeTestBusyByServer[serverPath] = false;
        _serverStatusLabelByServer[serverPath] = 'Error';
        _consoleLabelByServer[serverPath] = 'Launch Failed';
        _runtimeMessageByServer[serverPath] = error.message;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _runtimeTestBusyByServer[serverPath] = false;
        _serverStatusLabelByServer[serverPath] = 'Error';
        _consoleLabelByServer[serverPath] = 'Launch Failed';
        _runtimeMessageByServer[serverPath] =
            'Unable to start the local server runtime.';
      });
    }
  }

  void _startServerStatusPolling() {
    _serverStatusPollTimer?.cancel();
    _serverStatusPollTimer = Timer.periodic(
      const Duration(seconds: 2),
      (Timer timer) async {
        try {
          final LocalServerStatus status =
              await _localRuntimeService.getServerStatus();
          if (!mounted) {
            timer.cancel();
            return;
          }

          final String? activeServerPath = status.activeServerPath;
          if (activeServerPath != null) {
            _applyServerStatus(serverPath: activeServerPath, status: status);
          }

          if (!status.isBusy) {
            timer.cancel();
          }
        } catch (_) {
          if (!mounted) {
            timer.cancel();
          }
        }
      },
    );
  }

  void _applyServerStatus({
    required String serverPath,
    required LocalServerStatus status,
    String? fallbackMessage,
  }) {
    final String statusLabel = switch (status.state) {
      'starting' => 'Starting',
      'running' => 'Running',
      'stopped' => 'Stopped',
      'error' => 'Error',
      _ => 'Offline',
    };

    final String consoleLabel = switch (status.state) {
      'starting' => 'Bootstrapping',
      'running' => 'Live',
      'stopped' => 'Stopped',
      'error' => 'Crashed',
      _ => 'Ready',
    };

    setState(() {
      _serverStatusLabelByServer[serverPath] = statusLabel;
      _consoleLabelByServer[serverPath] = consoleLabel;
      _runtimeMessageByServer[serverPath] =
          status.lastMessage ??
          fallbackMessage ??
          _runtimeMessageByServer[serverPath] ??
          '';
      _runtimeTestBusyByServer[serverPath] = status.isBusy;
    });
  }

  @override
  void dispose() {
    _serverStatusPollTimer?.cancel();
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
        final String? serverPath = server['path'] as String?;
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: ServerCard(
            name: server['name']! as String,
            version: server['version']! as String,
            serverType: server['type']! as String,
            statusLabel:
                serverPath == null
                    ? 'Offline'
                    : (_serverStatusLabelByServer[serverPath] ?? 'Offline'),
            memoryLabel: server['memory']! as String,
            serverPath: serverPath,
            isOnline:
                serverPath != null &&
                (_serverStatusLabelByServer[serverPath] == 'Running'),
            isBusy:
                _isCreatingServer ||
                (serverPath != null &&
                    (_runtimeTestBusyByServer[serverPath] ?? false)),
            consoleLabel:
                serverPath == null
                    ? 'Ready'
                    : (_consoleLabelByServer[serverPath] ?? 'Ready'),
            runtimeMessage:
                serverPath == null ? null : _runtimeMessageByServer[serverPath],
            onStartServer:
                serverPath == null || _isCreatingServer
                    ? null
                    : () {
                        _startServer(server);
                      },
            onTestRuntime:
                serverPath == null || _isCreatingServer
                    ? null
                    : () {
                        _testRuntimeForServer(server);
                      },
            onDelete: _isCreatingServer
                ? null
                : () {
                    _deleteServer(server);
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
