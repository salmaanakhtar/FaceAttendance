import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';

import '../config.dart';
import '../device/secure_store.dart';

class UpdateInfo {
  final bool upToDate;
  final String? latest;
  final int? assetId;
  final String? assetName;
  final int? assetSize;

  UpdateInfo({
    required this.upToDate,
    this.latest,
    this.assetId,
    this.assetName,
    this.assetSize,
  });

  factory UpdateInfo.fromJson(Map<String, dynamic> j) => UpdateInfo(
        upToDate: j['upToDate'] as bool? ?? true,
        latest: j['latest'] as String?,
        assetId: (j['asset'] as Map<String, dynamic>?)?['id'] as int?,
        assetName: (j['asset'] as Map<String, dynamic>?)?['name'] as String?,
        assetSize: (j['asset'] as Map<String, dynamic>?)?['size'] as int?,
      );
}

/// GitHub-backed auto-update. Checks on launch; downloads the new APK
/// through the backend proxy and hands it to the system installer.
class UpdateChecker {
  UpdateChecker._();
  static final UpdateChecker instance = UpdateChecker._();

  static const _channel = MethodChannel('faceattendance/installer');
  final _dio = Dio(BaseOptions(
    baseUrl: kApiBaseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 60),
  ));

  Future<UpdateInfo?> check() async {
    final token = await SecureStore.instance.getDeviceToken();
    if (token == null) return null;
    try {
      final res = await _dio.get(
        '/api/v1/device/update',
        queryParameters: {'currentTag': kAppVersion},
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      return UpdateInfo.fromJson(res.data as Map<String, dynamic>);
    } catch (_) {
      return null; // offline or unreachable — never block the kiosk
    }
  }

  /// Download the APK to cache. Returns the local file path.
  Future<String> download(int assetId, void Function(double fraction)? onProgress) async {
    final token = await SecureStore.instance.getDeviceToken();
    if (token == null) throw StateError('not provisioned');
    final dir = Directory.systemTemp.createTempSync('faceatt-update');
    final file = File('${dir.path}/update.apk');
    await _dio.download(
      '/api/v1/device/update/download',
      file.path,
      queryParameters: {'assetId': assetId},
      options: Options(headers: {'Authorization': 'Bearer $token'}),
      onReceiveProgress: onProgress == null
          ? null
          : (received, total) => onProgress(total <= 0 ? 0 : received / total),
    );
    return file.path;
  }

  /// Launch the Android package installer for the downloaded APK.
  Future<bool> install(String path) async {
    final ok = await _channel.invokeMethod<bool>('installApk', {'path': path});
    return ok ?? false;
  }
}
