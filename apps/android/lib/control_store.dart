import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'camera.dart';
import 'onvif.dart';

/// Only routing preferences live here; credentials remain in CameraStore.
class ControlPreference {
  final String host, username, deviceUrl, token;
  final Uri endpoint;
  final bool minimal, zeroStop;
  const ControlPreference({
    required this.host,
    required this.username,
    required this.deviceUrl,
    required this.token,
    required this.endpoint,
    required this.minimal,
    required this.zeroStop,
  });

  bool matches(CameraConfig config) =>
      host == config.host &&
      username == config.username &&
      deviceUrl == config.onvifUrl;

  PtzProfile get profile => PtzProfile(
    token,
    'Controle salvo',
    endpoint,
    VelocitySpace('', -1, 1, -1, 1, fraction: .1),
    null,
    capabilitySource: 'compatibilidade_yoosee_manual',
  );

  Map<String, dynamic> toJson() => {
    'schema': 1,
    'host': host,
    'username': username,
    'deviceUrl': deviceUrl,
    'token': token,
    'endpoint': endpoint.toString(),
    'minimal': minimal,
    'zeroStop': zeroStop,
  };

  static ControlPreference? parse(
    Map<String, dynamic> json,
    CameraConfig config,
  ) {
    final uri = Uri.tryParse(
      json['endpoint'] is String ? json['endpoint'] as String : '',
    );
    if (json['schema'] != 1 ||
        json['host'] != config.host ||
        json['username'] != config.username ||
        json['deviceUrl'] != config.onvifUrl ||
        json['token'] is! String ||
        (json['token'] as String).isEmpty ||
        (json['token'] as String).length > 1024 ||
        json['minimal'] is! bool ||
        json['zeroStop'] is! bool ||
        uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host != config.host ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.port < 1 ||
        uri.port > 65535) {
      return null;
    }
    return ControlPreference(
      host: config.host,
      username: config.username,
      deviceUrl: config.onvifUrl,
      token: json['token'] as String,
      endpoint: uri,
      minimal: json['minimal'] as bool,
      zeroStop: json['zeroStop'] as bool,
    );
  }
}

class ControlStore {
  final FlutterSecureStorage storage;
  const ControlStore({
    this.storage = const FlutterSecureStorage(
      iOptions: IOSOptions(
        accessibility: KeychainAccessibility.first_unlock_this_device,
      ),
    ),
  });
  Future<ControlPreference?> load(CameraConfig config) async {
    final raw = await storage.read(key: 'control.v1');
    if (raw == null) return null;
    try {
      return ControlPreference.parse(
        jsonDecode(raw) as Map<String, dynamic>,
        config,
      );
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  Future<bool> loadJoystick() async =>
      await storage.read(key: 'control_ui.v1') == 'joystick';
  Future<void> saveJoystick(bool joystick) => storage.write(
    key: 'control_ui.v1',
    value: joystick ? 'joystick' : 'arrows',
  );

  Future<void> save(ControlPreference preference) =>
      storage.write(key: 'control.v1', value: jsonEncode(preference.toJson()));
}
