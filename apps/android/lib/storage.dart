import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'camera.dart';

class CameraStore {
  final FlutterSecureStorage storage;
  const CameraStore({
    this.storage = const FlutterSecureStorage(
      iOptions: IOSOptions(
        accessibility: KeychainAccessibility.first_unlock_this_device,
      ),
    ),
  });
  Future<CameraConfig?> load() async {
    final value = await storage.read(key: 'camera.v1');
    if (value == null) return null;
    final config = CameraConfig.fromJson(
      jsonDecode(value) as Map<String, dynamic>,
    );
    if (config.validate() != null) {
      throw const FormatException('Configuração inválida');
    }
    return config;
  }

  Future<void> save(CameraConfig config) =>
      storage.write(key: 'camera.v1', value: jsonEncode(config.toJson()));
  Future<void> clear() async {
    await storage.delete(key: 'camera.v1');
    await storage.delete(key: 'control.v1');
    await storage.delete(key: 'control_ui.v1');
  }
}
