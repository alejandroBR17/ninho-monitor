import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jortan_viewer/camera.dart';
import 'package:jortan_viewer/onvif.dart';
import 'package:jortan_viewer/rtsp_probe.dart';
import 'package:xml/xml.dart';

String soap(String body) =>
    '<s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope" xmlns:t="urn:test"><s:Body>$body</s:Body></s:Envelope>';
String? text(XmlNode document, String name) => document.descendants
    .whereType<XmlElement>()
    .where((e) => e.name.local == name)
    .firstOrNull
    ?.innerText;
void main() {
  test(
    'Descobre capacidades/perfis reais, autentica WSSE, usa os limites e para',
    () async {
      final server = await HttpServer.bind('127.0.0.1', 0);
      final events = <Map<String, dynamic>>[];
      final operations = <String>[];
      String? velocity, moveTimeout;
      var wsseValidated = false;
      final base = 'http://127.0.0.1:${server.port}';
      server.listen((request) async {
        final body = XmlDocument.parse(await utf8.decoder.bind(request).join());
        final operation = body.descendants
            .whereType<XmlElement>()
            .firstWhere((e) => e.name.local == 'Body')
            .childElements
            .first
            .name
            .local;
        operations.add(operation);
        if (operation != 'GetSystemDateAndTime') {
          expect(text(body, 'Username'), 'admin');
          final nonce = base64Decode(text(body, 'Nonce')!);
          final created = text(body, 'Created')!;
          expect(
            text(body, 'Password'),
            base64Encode(
              sha1.convert([
                ...nonce,
                ...utf8.encode(created),
                ...utf8.encode('fixture@secret'),
              ]).bytes,
            ),
          );
          wsseValidated = true;
        }
        String response;
        switch (operation) {
          case 'GetCapabilities':
            response =
                '<t:GetCapabilitiesResponse><t:Capabilities><t:Media><t:XAddr>$base/media</t:XAddr></t:Media><t:PTZ><t:XAddr>$base/ptz</t:XAddr></t:PTZ></t:Capabilities></t:GetCapabilitiesResponse>';
          case 'GetServices':
            response = '<t:GetServicesResponse/>';
          case 'GetSystemDateAndTime':
            response = '<t:GetSystemDateAndTimeResponse/>';
          case 'GetProfiles':
            response =
                '<t:GetProfilesResponse><t:Profiles token="main&amp;profile"><t:Name>Main</t:Name><t:PTZConfiguration token="configuration1"/></t:Profiles></t:GetProfilesResponse>';
          case 'GetConfigurationOptions':
            response =
                '<t:GetConfigurationOptionsResponse><t:PTZConfigurationOptions><t:Spaces>'
                '<t:ContinuousPanTiltVelocitySpace><t:URI>urn:pan</t:URI><t:XRange><t:Min>-2</t:Min><t:Max>2</t:Max></t:XRange><t:YRange><t:Min>-1</t:Min><t:Max>1</t:Max></t:YRange></t:ContinuousPanTiltVelocitySpace>'
                '<t:ContinuousZoomVelocitySpace><t:URI>urn:zoom</t:URI><t:XRange><t:Min>-1</t:Min><t:Max>1</t:Max></t:XRange></t:ContinuousZoomVelocitySpace>'
                '</t:Spaces></t:PTZConfigurationOptions></t:GetConfigurationOptionsResponse>';
          case 'ContinuousMove':
            expect(text(body, 'ProfileToken'), 'main&profile');
            velocity = body.descendants
                .whereType<XmlElement>()
                .firstWhere((e) => e.name.local == 'PanTilt')
                .getAttribute('x');
            moveTimeout = text(body, 'Timeout');
            response = '<t:ContinuousMoveResponse/>';
          case 'Stop':
            expect(text(body, 'PanTilt'), 'true');
            expect(text(body, 'Zoom'), 'true');
            response = '<t:StopResponse/>';
          default:
            throw StateError('Unexpected $operation');
        }
        request.response.headers.contentType = ContentType(
          'application',
          'soap+xml',
        );
        request.response.write(soap(response));
        await request.response.close();
      });
      final client = OnvifClient(
        CameraConfig(
          host: '127.0.0.1',
          password: 'fixture@secret',
          onvifUrl: '$base/device',
        ),
        onEvent: events.add,
      );
      addTearDown(() async {
        client.close();
        await server.close(force: true);
      });
      final profiles = await client.inspect();
      expect(profiles, hasLength(1));
      expect(profiles.single.supported, true);
      await client.move(profiles.single, -1, 0, 0);
      await client.stop(profiles.single);
      expect(velocity, '-0.7');
      expect(moveTimeout, 'PT0.6S');
      expect(wsseValidated, true);
      expect(operations.last, 'Stop');
      final report = jsonEncode(events);
      for (final secret in [
        'fixture@secret',
        'Authorization',
        'Nonce',
        'PasswordDigest',
      ]) {
        expect(report, isNot(contains(secret)));
      }
    },
  );

  test(
    'HTTP Digest usa POST e caminho HTTP, não DESCRIBE nem URL RTSP',
    () async {
      final server = await HttpServer.bind('127.0.0.1', 0);
      var authenticated = false;
      server.listen((request) async {
        await request.drain<void>();
        final header = request.headers.value('authorization');
        if (header == null) {
          request.response.statusCode = 401;
          request.response.headers.set(
            'WWW-Authenticate',
            'Digest realm="fixture", nonce="nonce-fixture", qop="auth"',
          );
        } else {
          final fields = parseChallenge(header);
          expect(fields['uri'], '/device');
          String hash(String s) => md5.convert(utf8.encode(s)).toString();
          expect(
            fields['response'],
            hash(
              '${hash('admin:fixture:test-only')}:nonce-fixture:00000001:${fields['cnonce']}:auth:${hash('POST:/device')}',
            ),
          );
          authenticated = true;
          request.response.write(soap('<t:GetCapabilitiesResponse/>'));
        }
        await request.response.close();
      });
      final client = OnvifClient(
        const CameraConfig(host: '127.0.0.1', password: 'test-only'),
        onEvent: (_) {},
      );
      addTearDown(() async {
        client.close();
        await server.close(force: true);
      });
      await client.call(
        Uri.parse('http://127.0.0.1:${server.port}/device'),
        'urn:test',
        'GetCapabilities',
        '',
      );
      expect(authenticated, true);
    },
  );

  test('Recusa XAddr externo e URL com senha antes de fazer requisição', () {
    final client = OnvifClient(
      const CameraConfig(host: '192.168.1.100'),
      onEvent: (_) {},
    );
    addTearDown(client.close);
    for (final uri in [
      'http://192.168.1.20/onvif',
      'http://admin:password@192.168.1.100/onvif',
      'file:///etc/passwd',
    ]) {
      expect(
        () => client.endpoint(uri),
        throwsA(
          isA<OnvifFailure>().having(
            (e) => e.code,
            'code',
            'endpoint_recusado',
          ),
        ),
      );
    }
  });

  test(
    'SOAP 1.2 NotAuthorized preserva motivo com senha configurada removida',
    () async {
      final events = <Map<String, dynamic>>[];
      final server = await HttpServer.bind('127.0.0.1', 0);
      server.listen((request) async {
        await request.drain<void>();
        request.response.statusCode = 500;
        request.response.write(
          soap(
            '<s:Fault><s:Code><s:Subcode><s:Value>ter:NotAuthorized</s:Value></s:Subcode></s:Code><s:Reason><s:Text>secret-camera-password</s:Text></s:Reason></s:Fault>',
          ),
        );
        await request.response.close();
      });
      final client = OnvifClient(
        const CameraConfig(
          host: '127.0.0.1',
          password: 'secret-camera-password',
        ),
        onEvent: events.add,
      );
      addTearDown(() async {
        client.close();
        await server.close(force: true);
      });
      await expectLater(
        client.call(
          Uri.parse('http://127.0.0.1:${server.port}/'),
          'urn:test',
          'Stop',
          '',
        ),
        throwsA(
          isA<OnvifFailure>().having((e) => e.code, 'code', 'NotAuthorized'),
        ),
      );
      expect(jsonEncode(events), isNot(contains('secret-camera-password')));
      final fault = events.firstWhere((e) => e.containsKey('falhaSoap'));
      expect(fault['formatoFalha'], 'SOAP_1_2');
      expect(fault['motivos'], ['[omitido]']);
    },
  );

  for (final code in ['ter:ActionNotSupported', 's:Server']) {
    test('SOAP 1.1 mantém código e motivo útil: $code', () async {
      final events = <Map<String, dynamic>>[];
      final server = await HttpServer.bind('127.0.0.1', 0);
      server.listen((request) async {
        await request.drain<void>();
        request.response.statusCode =
            200; // Broken firmware reports faults as 200.
        request.response.write(
          soap(
            '<s:Fault><faultcode>$code</faultcode>'
            '<faultstring>Operation GetConfigurationOptions is not supported</faultstring>'
            '<detail><Password>unrelated-secret</Password></detail></s:Fault>',
          ),
        );
        await request.response.close();
      });
      final client = OnvifClient(
        const CameraConfig(host: '127.0.0.1'),
        onEvent: events.add,
      );
      addTearDown(() async {
        client.close();
        await server.close(force: true);
      });
      await expectLater(
        client.call(
          Uri.parse('http://127.0.0.1:${server.port}/'),
          'urn:test',
          'GetConfigurationOptions',
          '',
        ),
        throwsA(
          isA<OnvifFailure>().having(
            (e) => e.code,
            'code',
            code.endsWith('ActionNotSupported')
                ? 'ActionNotSupported'
                : 'SOAPFault',
          ),
        ),
      );
      final fault = events.firstWhere((e) => e.containsKey('falhaSoap'));
      expect(fault['formatoFalha'], 'SOAP_1_1');
      expect(fault['codigosRecebidos'], [code]);
      expect(fault['motivos'], [
        'Operation GetConfigurationOptions is not supported',
      ]);
      expect(jsonEncode(events), isNot(contains('unrelated-secret')));
    });
  }

  test(
    'Porta sem resposta tem prazo limitado e não se confunde com ausência de PTZ',
    () async {
      final server = await HttpServer.bind('127.0.0.1', 0);
      server.listen((request) async {
        await request.drain<void>();
      });
      final client = OnvifClient(
        const CameraConfig(host: '127.0.0.1'),
        onEvent: (_) {},
        timeout: const Duration(milliseconds: 80),
      );
      addTearDown(() async {
        client.close();
        await server.close(force: true);
      });
      await expectLater(
        client.call(
          Uri.parse('http://127.0.0.1:${server.port}/'),
          'urn:test',
          'GetCapabilities',
          '',
        ),
        throwsA(isA<OnvifFailure>().having((e) => e.code, 'code', 'timeout')),
      );
    },
  );

  test(
    'Configuração antiga migra sem URL ONVIF e URL ONVIF externa é rejeitada',
    () {
      final json = const CameraConfig().toJson()..remove('onvifUrl');
      expect(CameraConfig.fromJson(json).onvifUrl, '');
      expect(
        const CameraConfig(onvifUrl: 'http://192.168.1.17/device').validate(),
        isNotNull,
      );
    },
  );
}
