import 'package:bifrost/Utils/tunnel_models.dart';
import 'package:flutter/services.dart';

class TunnelServiceException implements Exception {
  const TunnelServiceException(this.message);

  final String message;
}

class TunnelService {
  const TunnelService();

  static const MethodChannel _channel = MethodChannel('bifrost/tunnel');

  Future<TunnelStatus> startTunnel({required int localPort}) async {
    try {
      final Map<Object?, Object?>? result = await _channel
          .invokeMapMethod<Object?, Object?>('startTunnel', <String, Object?>{
            'localPort': localPort,
          });
      return TunnelStatus.fromMap(result ?? <Object?, Object?>{});
    } on PlatformException catch (error) {
      throw TunnelServiceException(
        error.message ?? 'Unable to start the bore tunnel.',
      );
    }
  }

  Future<TunnelStatus> stopTunnel() async {
    try {
      final Map<Object?, Object?>? result =
          await _channel.invokeMapMethod<Object?, Object?>('stopTunnel');
      return TunnelStatus.fromMap(result ?? <Object?, Object?>{});
    } on PlatformException catch (error) {
      throw TunnelServiceException(
        error.message ?? 'Unable to stop the bore tunnel.',
      );
    }
  }

  Future<TunnelStatus> getTunnelStatus() async {
    try {
      final Map<Object?, Object?>? result =
          await _channel.invokeMapMethod<Object?, Object?>('getTunnelStatus');
      return TunnelStatus.fromMap(result ?? <Object?, Object?>{});
    } on PlatformException catch (error) {
      throw TunnelServiceException(
        error.message ?? 'Unable to get the tunnel status.',
      );
    }
  }
}
