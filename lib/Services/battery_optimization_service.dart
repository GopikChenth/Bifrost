import 'package:flutter/services.dart';

class BatteryOptimizationException implements Exception {
  const BatteryOptimizationException(this.message);

  final String message;

  @override
  String toString() => 'BatteryOptimizationException: $message';
}

/// Thin wrapper over the `bifrost/battery_optimization` method channel.
class BatteryOptimizationService {
  const BatteryOptimizationService();

  static const MethodChannel _channel = MethodChannel(
    'bifrost/battery_optimization',
  );

  /// Returns `true` when the app is exempt from battery optimizations.
  Future<bool> isIgnoringBatteryOptimizations() async {
    try {
      return await _channel.invokeMethod<bool>('isIgnoringBatteryOptimizations') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Opens the system settings or prompt page to exempt the app from battery optimizations.
  Future<void> requestIgnoreBatteryOptimizations() async {
    try {
      await _channel.invokeMethod<void>('requestIgnoreBatteryOptimizations');
    } on PlatformException catch (error) {
      throw BatteryOptimizationException(
        error.message ?? 'Unable to request battery optimization settings.',
      );
    } on MissingPluginException {
      throw const BatteryOptimizationException(
        'Android battery bridge is not available.',
      );
    }
  }

  /// Returns the device manufacturer name.
  Future<String> getDeviceManufacturer() async {
    try {
      return await _channel.invokeMethod<String>('getDeviceManufacturer') ?? '';
    } on PlatformException {
      return '';
    } on MissingPluginException {
      return '';
    }
  }

  /// Opens the App Info settings page.
  Future<void> openAppDetailsSettings() async {
    try {
      await _channel.invokeMethod<void>('openAppDetailsSettings');
    } on PlatformException catch (error) {
      throw BatteryOptimizationException(
        error.message ?? 'Unable to open app details settings.',
      );
    } on MissingPluginException {
      throw const BatteryOptimizationException(
        'Android battery bridge is not available.',
      );
    }
  }
}
