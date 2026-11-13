import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:jortan_viewer/camera.dart';
import 'package:jortan_viewer/control_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const config = CameraConfig(password: 'fixture-private');
  final record = ControlPreference(
    host: config.host,
    username: config.username,
    deviceUrl: '',
    token: 'received-token',
    endpoint: Uri.parse('http://${config.host}:5000/onvif/deviceio_service'),
    minimal: false,
    zeroStop: true,
  );
  test(
    'Preferência protegida migra sem alterar câmera e permite trocar fluxo',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        'camera.v1': jsonEncode(config.toJson()),
      });
      const store = ControlStore();
      expect(await store.load(config), isNull);
      await store.save(record);
      expect(await store.loadJoystick(), false);
      await store.saveJoystick(true);
      expect(await store.loadJoystick(), true);
      expect(
        (await store.load(config.withPreset(ViewingPreset.fluid)))?.token,
        'received-token',
      );
      expect(jsonEncode(record.toJson()), isNot(contains(config.password)));
      expect(
        (await const FlutterSecureStorage().read(key: 'camera.v1')),
        jsonEncode(config.toJson()),
      );
    },
  );
  test(
    'Preferência recusa destino diferente, credenciais na URL e identidade trocada',
    () {
      for (final endpoint in [
        'http://192.168.1.17:5000/ptz',
        'http://admin:secret@192.168.1.100:5000/ptz',
        'http://192.168.1.100:5000/ptz?q=secret',
        'file:///ptz',
      ]) {
        expect(
          ControlPreference.parse({
            ...record.toJson(),
            'endpoint': endpoint,
          }, config),
          isNull,
        );
      }
      expect(
        ControlPreference.parse(
          record.toJson(),
          const CameraConfig(host: '192.168.1.17'),
        ),
        isNull,
      );
      expect(
        ControlPreference.parse(
          record.toJson(),
          const CameraConfig(username: 'other'),
        ),
        isNull,
      );
      expect(
        ControlPreference.parse({...record.toJson(), 'schema': 99}, config),
        isNull,
      );
    },
  );
}
