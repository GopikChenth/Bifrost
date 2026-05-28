import 'package:bifrost/Services/battery_optimization_service.dart';
import 'package:bifrost/Services/server_storage_service.dart';
import 'package:bifrost/Utils/settings_repository.dart';
import 'package:flutter/material.dart';

class OnboardingBottomSheet extends StatefulWidget {
  const OnboardingBottomSheet({super.key});

  static Future<void> showIfNeeded(BuildContext context) async {
    final SettingsRepository settingsRepo = const SettingsRepository();
    final ServerStorageService storageService = const ServerStorageService();
    final BatteryOptimizationService batteryService = const BatteryOptimizationService();

    final bool completed = await settingsRepo.loadOnboardingCompleted();
    final bool hasStorage = await storageService.hasAllFilesAccess();
    final bool hasBattery = await batteryService.isIgnoringBatteryOptimizations();

    // Show if onboarding is not completed OR if permissions are missing
    if (!completed || !hasStorage || !hasBattery) {
      if (!context.mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        isDismissible: completed, // Only dismissible if they already did onboarding once
        enableDrag: completed,
        builder: (BuildContext context) => const OnboardingBottomSheet(),
      );
    }
  }

  @override
  State<OnboardingBottomSheet> createState() => _OnboardingBottomSheetState();
}

class _OnboardingBottomSheetState extends State<OnboardingBottomSheet>
    with WidgetsBindingObserver {
  final ServerStorageService _serverStorageService = const ServerStorageService();
  final BatteryOptimizationService _batteryOptimizationService = const BatteryOptimizationService();
  final SettingsRepository _settingsRepository = const SettingsRepository();

  bool _hasStorageAccess = false;
  bool _isBatteryExempt = false;
  bool _isAggressiveOem = false;
  String _deviceManufacturer = '';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPermissions();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPermissions();
    }
  }

  Future<void> _checkPermissions() async {
    final bool storage = await _serverStorageService.hasAllFilesAccess();
    final bool battery = await _batteryOptimizationService.isIgnoringBatteryOptimizations();
    final String manufacturer = await _batteryOptimizationService.getDeviceManufacturer();
    final String lowerMan = manufacturer.toLowerCase();
    final bool isAggressive = lowerMan.contains('oneplus') ||
        lowerMan.contains('oppo') ||
        lowerMan.contains('realme') ||
        lowerMan.contains('xiaomi') ||
        lowerMan.contains('redmi') ||
        lowerMan.contains('poco') ||
        lowerMan.contains('huawei') ||
        lowerMan.contains('honor') ||
        lowerMan.contains('vivo');

    if (mounted) {
      setState(() {
        _hasStorageAccess = storage;
        _isBatteryExempt = battery;
        _deviceManufacturer = manufacturer;
        _isAggressiveOem = isAggressive;
        _isLoading = false;
      });
    }
  }

  Future<void> _requestStorage() async {
    try {
      await _serverStorageService.requestAllFilesAccess();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> _requestBattery() async {
    try {
      await _batteryOptimizationService.requestIgnoreBatteryOptimizations();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> _finishOnboarding() async {
    await _settingsRepository.saveOnboardingCompleted(true);
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;

    if (_isLoading) {
      return const SizedBox(
        height: 300,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return PopScope(
      canPop: _hasStorageAccess, // Prevent closing if storage permission is not granted yet
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const SizedBox(height: 8),
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colors.primaryContainer,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      Icons.dns_rounded,
                      color: colors.onPrimaryContainer,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Welcome to Bifrost',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Host Minecraft servers on your phone',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text(
                'To run local servers reliably, please configure the following settings:',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 20),

              // Step 1: Storage Permission Card
              _buildPermissionCard(
                title: 'Storage Access',
                description: 'Required to create server directories, worlds, properties, and configurations.',
                isGranted: _hasStorageAccess,
                icon: Icons.folder_open_rounded,
                buttonText: 'Grant Storage',
                onPressed: _requestStorage,
                colors: colors,
                theme: theme,
              ),
              const SizedBox(height: 12),

              // Step 2: Battery Optimization Card
              _buildPermissionCard(
                title: 'Unrestricted Battery',
                description: 'Exempts Bifrost from battery limits so the server is not killed and does not disconnect when the phone is locked or in sleep mode.',
                isGranted: _isBatteryExempt,
                icon: Icons.battery_saver_rounded,
                buttonText: 'Allow Background',
                onPressed: _requestBattery,
                colors: colors,
                theme: theme,
              ),
              if (_isAggressiveOem) ...[
                const SizedBox(height: 8),
                Card(
                  elevation: 0,
                  color: colors.errorContainer.withValues(alpha: 0.15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: colors.error.withValues(alpha: 0.3),
                      width: 1.0,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Icon(
                              Icons.warning_rounded,
                              color: colors.error,
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '$_deviceManufacturer Device: Manual Action Required',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: colors.error,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '$_deviceManufacturer devices aggressively restrict background processes in sleep. To prevent server disconnection:\n'
                          '1. Tap "Go to App Info" below, go to "Battery" -> "Battery usage", and choose "Unrestricted" (or enable "Allow background activity").\n'
                          '2. In phone settings, go to "Battery" -> "More/Advanced settings" -> disable "Sleep standby optimization".',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onErrorContainer,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 10),
                        FilledButton.tonalIcon(
                          onPressed: () async {
                            try {
                              await _batteryOptimizationService.openAppDetailsSettings();
                            } catch (e) {
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Error: ${e.toString()}')),
                              );
                            }
                          },
                          icon: const Icon(Icons.info_outline_rounded, size: 16),
                          label: const Text('Go to App Info'),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 28),

              // Finish Button
              FilledButton.icon(
                onPressed: _hasStorageAccess ? _finishOnboarding : null,
                icon: const Icon(Icons.rocket_launch_rounded),
                label: const Text('Start Bifrost'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPermissionCard({
    required String title,
    required String description,
    required bool isGranted,
    required IconData icon,
    required String buttonText,
    required VoidCallback onPressed,
    required ColorScheme colors,
    required ThemeData theme,
  }) {
    return Card(
      elevation: 0,
      color: isGranted ? colors.primaryContainer.withValues(alpha: 0.15) : colors.surfaceContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: isGranted ? colors.primary.withValues(alpha: 0.4) : colors.outlineVariant.withValues(alpha: 0.5),
          width: 1.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(
              isGranted ? Icons.check_circle_rounded : icon,
              color: isGranted ? colors.primary : colors.error,
              size: 24,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: isGranted ? colors.primary : null,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                      height: 1.3,
                    ),
                  ),
                  if (!isGranted) ...[
                    const SizedBox(height: 12),
                    FilledButton.tonal(
                      onPressed: onPressed,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        minimumSize: Size.zero,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(buttonText),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
