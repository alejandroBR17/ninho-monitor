import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:jortan_viewer/camera.dart';
import 'package:jortan_viewer/storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('URI RTSP preserva credenciais com caracteres reservados', () {
    const camera = CameraConfig(
      username: 'a:b@c',
      password: 's:/?#%&',
      path: '/onvif1?channel=1',
    );
    final uri = camera.uri;
    expect(uri.host, '192.168.1.100');
    expect(uri.port, 554);
    expect(uri.path, '/onvif1');
    expect(uri.queryParameters['channel'], '1');
    final parts = uri.userInfo.split(':');
    expect(Uri.decodeComponent(parts[0]), camera.username);
    expect(Uri.decodeComponent(parts[1]), camera.password);
  });
  test('Valida porta, host e caminho, aceita caminho personalizado', () {
    expect(const CameraConfig(port: 0).validate(), isNotNull);
    expect(const CameraConfig(port: 65536).validate(), isNotNull);
    expect(const CameraConfig(host: '192.168.1.100:554').validate(), isNotNull);
    expect(
      const CameraConfig(path: '//outro-host/video').validate(),
      isNotNull,
    );
    expect(
      const CameraConfig(path: '/live/ch1?quality=low').validate(),
      isNull,
    );
  });
  test('Sanitização remove URL e cabeçalho mesmo sem senha cadastrada', () {
    final output = Redactor().clean(
      'Opening rtsp://admin:secret@192.168.1.100/onvif1\nAuthorization: Digest password',
    );
    expect(output, isNot(contains('secret')));
    expect(output, isNot(contains('Digest password')));
  });
  test('Mensagens distinguem evidências sem afirmar firewall', () {
    expect(explainFailure('404 Not Found'), contains('caminho'));
    expect(explainFailure('Connection refused'), contains('recusada'));
    expect(explainFailure('No route to host'), contains('Wi-Fi'));
    expect(explainFailure('Timeout'), contains('não comprova'));
  });
  test(
    'Salva, recupera e remove configuração no armazenamento protegido',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      const store = CameraStore();
      expect(await store.load(), isNull);
      const camera = CameraConfig(
        password: 'local-only',
        transport: Transport.udp,
      );
      await store.save(camera);
      final loaded = await store.load();
      expect(loaded!.password, 'local-only');
      expect(loaded.transport, Transport.udp);
      await store.clear();
      expect(await store.load(), isNull);
    },
  );
}
