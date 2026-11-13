import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';
import 'package:jortan_viewer/camera.dart';
import 'package:jortan_viewer/onvif.dart';
import 'onvif_compatibility_test.dart' show envelope, operation;

const ptz = 'http://www.onvif.org/ver20/ptz/wsdl';
const legacy = 'http://schemas.xmlsoap.org/ws/2004/08/addressing';
const current = 'http://www.w3.org/2005/08/addressing';
XmlElement? field(XmlDocument doc, String name) => doc.descendants
    .whereType<XmlElement>()
    .where((e) => e.name.local == name)
    .firstOrNull;
PtzProfile manual(Uri uri) => PtzProfile(
  'fixture-profile',
  'Fixture',
  uri,
  VelocitySpace('', -1, 1, -1, 1, fraction: .1),
  null,
  capabilitySource: 'compatibilidade_yoosee_manual',
);

void main() {
  for (final isManual in [false, true]) {
    test(
      'Roteamento SOAP é enviado com Action/To/MessageID: manual=$isManual',
      () async {
        final ids = <String>[];
        final server = await HttpServer.bind('127.0.0.1', 0);
        final uri = Uri.parse(
          'http://127.0.0.1:${server.port}/onvif/custom_ptz',
        );
        var connectionsWithoutRouting = 0;
        server.listen((request) async {
          final body = await utf8.decoder.bind(request).join();
          final doc = XmlDocument.parse(body);
          final action = field(doc, 'Action');
          if (action == null) {
            connectionsWithoutRouting++;
            final socket = await request.response.detachSocket(
              writeHeaders: false,
            );
            socket.destroy();
            return;
          }
          final op = operation(body);
          expect(action.namespaceUri, isManual ? legacy : current);
          expect(action.innerText, '$ptz/$op');
          expect(field(doc, 'To')?.innerText, uri.toString());
          final id = field(doc, 'MessageID')!.innerText;
          expect(
            id,
            matches(
              RegExp(
                r'^urn:uuid:[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
              ),
            ),
          );
          ids.add(id);
          if (isManual) {
            expect(field(doc, 'Security'), isNull);
            expect(request.headers.value('SOAPAction'), isNull);
          } else {
            expect(field(doc, 'Security'), isNotNull);
            expect(request.headers.value('SOAPAction'), '"$ptz/$op"');
          }
          expect(body, isNot(contains('fixture-private')));
          expect(request.contentLength, utf8.encode(body).length);
          request.response.write(envelope('<t:${op}Response/>'));
          await request.response.close();
        });
        final oldRequest = HttpClient();
        final request = await oldRequest.postUrl(uri);
        request.write(envelope('<t:Stop/>'));
        await expectLater(request.close(), throwsA(isA<HttpException>()));
        oldRequest.close(force: true);
        final events = <Map<String, dynamic>>[];
        final client = OnvifClient(
          const CameraConfig(host: '127.0.0.1', password: 'fixture-private'),
          onEvent: events.add,
        );
        addTearDown(() async {
          client.close();
          await server.close(force: true);
        });
        if (isManual) {
          final p = manual(uri);
          await client.prepareManual(p);
          await client.move(p, 1, 0, 0);
          await client.stop(p);
        } else {
          for (final op in ['GetNodes', 'Stop', 'ContinuousMove']) {
            await client.call(
              uri,
              ptz,
              op,
              '<t:ProfileToken>fixture-profile</t:ProfileToken>',
            );
          }
        }
        expect(connectionsWithoutRouting, 1);
        expect(ids.length, 3);
        expect(ids.toSet().length, 3);
        final report = jsonEncode(events);
        expect(report, isNot(contains('fixture-private')));
        expect(report, isNot(contains('urn:uuid:')));
      },
    );
  }
  test(
    'Conexão encerrada preserva formato de roteamento, sem habilitar teste',
    () async {
      final server = await HttpServer.bind('127.0.0.1', 0);
      server.listen((request) async {
        await request.drain<void>();
        final socket = await request.response.detachSocket(writeHeaders: false);
        socket.destroy();
      });
      final events = <Map<String, dynamic>>[];
      final client = OnvifClient(
        const CameraConfig(host: '127.0.0.1'),
        onEvent: events.add,
      );
      addTearDown(() async {
        client.close();
        await server.close(force: true);
      });
      final p = manual(Uri.parse('http://127.0.0.1:${server.port}/ptz'));
      await expectLater(
        client.prepareManual(p),
        throwsA(
          isA<OnvifFailure>().having(
            (e) => e.code,
            'code',
            'parada_previa_falhou',
          ),
        ),
      );
      final errors = events
          .where((e) => e['codigo'] == 'http_conexao_encerrada')
          .toList();
      expect(errors.map((e) => e['enderecamentoSoap']), [
        legacy,
        current,
        current,
        legacy,
      ]);
      expect(errors.map((e) => e['actionSoap']), [
        '$ptz/Stop',
        '$ptz/Stop',
        '$ptz/ContinuousMove',
        '$ptz/ContinuousMove',
      ]);
      await expectLater(
        client.move(p, 1, 0, 0),
        throwsA(
          isA<OnvifFailure>().having(
            (e) => e.code,
            'code',
            'teste_nao_ativado',
          ),
        ),
      );
    },
  );
}
