import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:jortan_viewer/camera.dart';
import 'package:jortan_viewer/onvif.dart';
import 'package:xml/xml.dart';

String envelope(String body) =>
    '<s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope" xmlns:t="urn:test"><s:Body>$body</s:Body></s:Envelope>';
const spaces =
    '<t:ContinuousPanTiltVelocitySpace><t:URI>urn:pan</t:URI><t:XRange><t:Min>-1</t:Min><t:Max>1</t:Max></t:XRange><t:YRange><t:Min>-1</t:Min><t:Max>1</t:Max></t:YRange></t:ContinuousPanTiltVelocitySpace>';
String profile(String node) =>
    '<t:GetProfilesResponse><t:Profiles token="main"><t:Name>Main</t:Name><t:PTZConfiguration token="config"><t:NodeToken>$node</t:NodeToken></t:PTZConfiguration></t:Profiles></t:GetProfilesResponse>';
const fault =
    '<s:Fault><s:Code><s:Subcode><s:Value>ter:ActionNotSupported</s:Value></s:Subcode></s:Code></s:Fault>';
Future<void> reply(HttpRequest request, String body) async {
  request.response.write(envelope(body));
  await request.response.close();
}

String operation(String body) => XmlDocument.parse(body).descendants
    .whereType<XmlElement>()
    .firstWhere((e) => e.name.local == 'Body')
    .childElements
    .first
    .name
    .local;

void main() {
  for (final acceptedPrefix in ['ptz', '']) {
    test(
      'Consulta PTZ tenta XML equivalente e conserva formato aceito ($acceptedPrefix)',
      () async {
        const ns = 'http://www.onvif.org/ver20/ptz/wsdl';
        final prefixes = <String>[];
        final calls = <String>[];
        final server = await HttpServer.bind('127.0.0.1', 0);
        server.listen((request) async {
          final body = await utf8.decoder.bind(request).join();
          final doc = XmlDocument.parse(body);
          final op = doc.descendants
              .whereType<XmlElement>()
              .firstWhere((e) => e.name.local == 'Body')
              .childElements
              .single;
          calls.add(op.name.local);
          prefixes.add(op.name.prefix ?? '');
          expect(op.namespaceUri, ns);
          for (final child in op.childElements) {
            expect(child.namespaceUri, ns);
          }
          if ((op.name.prefix ?? '') != acceptedPrefix) {
            await reply(
              request,
              '<s:Fault><s:Code><s:Value>s:Sender</s:Value></s:Code>'
              '<s:Reason><s:Text>Method not implemented: method name or namespace not recognized</s:Text></s:Reason></s:Fault>',
            );
          } else if (op.name.local == 'ContinuousMove') {
            // A rejected write MUST NOT be retried, even after compatibility discovery.
            await reply(request, fault);
          } else {
            await reply(request, '<t:${op.name.local}Response/>');
          }
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
        final uri = Uri.parse('http://127.0.0.1:${server.port}/ptz');
        await client.call(
          uri,
          ns,
          'GetConfigurationOptions',
          '<t:ConfigurationToken>fixture</t:ConfigurationToken>',
        );
        expect(
          prefixes,
          acceptedPrefix.isEmpty ? ['tptz', 'ptz', ''] : ['tptz', 'ptz'],
        );
        await client.call(uri, ns, 'GetNodes', '');
        expect(prefixes.last, acceptedPrefix);
        await expectLater(
          client.call(
            uri,
            ns,
            'ContinuousMove',
            '<t:ProfileToken>fixture</t:ProfileToken>',
          ),
          throwsA(isA<OnvifFailure>()),
        );
        expect(calls.where((op) => op == 'ContinuousMove').length, 1);
        expect(prefixes.last, acceptedPrefix);
        expect(
          events
              .where(
                (e) =>
                    e['compatibilidade'] ==
                    'leitura_com_serializacao_xml_equivalente',
              )
              .length,
          acceptedPrefix.isEmpty ? 2 : 1,
        );
      },
    );
  }

  test(
    'HTTP embarcado recebe tamanho UTF-8 explícito, sem chunked e sem keep-alive',
    () async {
      final server = await HttpServer.bind('127.0.0.1', 0);
      var checked = false;
      server.listen((request) async {
        final bytes = await request.fold<List<int>>(
          [],
          (all, part) => all..addAll(part),
        );
        expect(request.contentLength, bytes.length);
        expect(request.headers.value('transfer-encoding'), isNull);
        expect(request.persistentConnection, false);
        expect(
          request.headers.value('soapaction'),
          '"urn:test/GetCapabilities"',
        );
        expect(utf8.decode(bytes), contains('usuário'));
        checked = true;
        await reply(request, '<t:GetCapabilitiesResponse/>');
      });
      final client = OnvifClient(
        const CameraConfig(host: '127.0.0.1', username: 'usuário'),
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
      expect(checked, true);
    },
  );

  test(
    'GetConfigurationOptions encerrado pelo firmware usa GetNode correlacionado, sem mover',
    () async {
      final server = await HttpServer.bind('127.0.0.1', 0);
      final base = 'http://127.0.0.1:${server.port}';
      final events = <Map<String, dynamic>>[];
      final operations = <String>[];
      server.listen((request) async {
        final op = operation(await utf8.decoder.bind(request).join());
        operations.add(op);
        switch (op) {
          case 'GetCapabilities':
            await reply(
              request,
              '<t:GetCapabilitiesResponse><t:Media><t:XAddr>$base/media</t:XAddr></t:Media><t:PTZ><t:XAddr>$base/ptz</t:XAddr></t:PTZ></t:GetCapabilitiesResponse>',
            );
          case 'GetProfiles':
            await reply(request, profile('node1'));
          case 'GetServices':
            await reply(request, '<t:GetServicesResponse/>');
          case 'GetSystemDateAndTime':
            await reply(request, '<t:GetSystemDateAndTimeResponse/>');
          case 'GetConfigurationOptions':
            final socket = await request.response.detachSocket(
              writeHeaders: false,
            );
            socket.destroy();
          case 'GetNode':
            await reply(
              request,
              '<t:GetNodeResponse><t:PTZNode token="node1"><t:SupportedPTZSpaces>$spaces</t:SupportedPTZSpaces></t:PTZNode></t:GetNodeResponse>',
            );
          default:
            fail('Não deveria executar $op');
        }
      });
      final client = OnvifClient(
        CameraConfig(host: '127.0.0.1', onvifUrl: '$base/device'),
        onEvent: events.add,
      );
      addTearDown(() async {
        client.close();
        await server.close(force: true);
      });
      final result = await client.inspect();
      expect(result.single.panTilt, isNotNull);
      expect(result.single.zoom, isNull);
      expect(result.single.capabilitySource, 'PTZNode');
      expect(operations, isNot(contains('ContinuousMove')));
      final errors = events.where(
        (e) =>
            e['codigo'] == 'http_conexao_encerrada' &&
            e['operacao'] == 'GetConfigurationOptions',
      );
      expect(errors, isNotEmpty);
      expect(
        errors.every(
          (e) =>
              e['porta'] == server.port &&
              e['caminho'] != null &&
              e['etapa'] != null,
        ),
        true,
      );
    },
  );

  test(
    'Porta PTZ anunciada errada é comparada com a porta ONVIF confirmada',
    () async {
      final dead = await ServerSocket.bind('127.0.0.1', 0);
      final deadPort = dead.port;
      await dead.close();
      final server = await HttpServer.bind('127.0.0.1', 0);
      final base = 'http://127.0.0.1:${server.port}';
      final events = <Map<String, dynamic>>[];
      server.listen((request) async {
        final op = operation(await utf8.decoder.bind(request).join());
        switch (op) {
          case 'GetCapabilities':
            await reply(
              request,
              '<t:GetCapabilitiesResponse><t:Media><t:XAddr>$base/media</t:XAddr></t:Media><t:PTZ><t:XAddr>http://127.0.0.1:$deadPort/ptz</t:XAddr></t:PTZ></t:GetCapabilitiesResponse>',
            );
          case 'GetProfiles':
            await reply(request, profile('node1'));
          case 'GetServices':
            await reply(request, '<t:GetServicesResponse/>');
          case 'GetSystemDateAndTime':
            await reply(request, '<t:GetSystemDateAndTimeResponse/>');
          case 'GetConfigurationOptions':
            await reply(
              request,
              '<t:GetConfigurationOptionsResponse><t:Spaces>$spaces</t:Spaces></t:GetConfigurationOptionsResponse>',
            );
          default:
            fail('Unexpected $op');
        }
      });
      final client = OnvifClient(
        CameraConfig(host: '127.0.0.1', onvifUrl: '$base/device'),
        onEvent: events.add,
      );
      addTearDown(() async {
        client.close();
        await server.close(force: true);
      });
      final profiles = await client.inspect();
      expect(profiles.single.endpoint.port, server.port);
      expect(profiles.single.endpoint.path, '/ptz');
      expect(
        events.where((e) => e['codigo'] == 'tcp_recusado').single['porta'],
        deadPort,
      );
    },
  );

  test(
    'Perfis recebidos com consultas falhas ficam indeterminados, não sem PTZ',
    () async {
      final server = await HttpServer.bind('127.0.0.1', 0);
      final base = 'http://127.0.0.1:${server.port}';
      server.listen((request) async {
        final op = operation(await utf8.decoder.bind(request).join());
        switch (op) {
          case 'GetCapabilities':
            await reply(
              request,
              '<t:GetCapabilitiesResponse><t:Media><t:XAddr>$base/device</t:XAddr></t:Media><t:PTZ><t:XAddr>$base/device</t:XAddr></t:PTZ></t:GetCapabilitiesResponse>',
            );
          case 'GetProfiles':
            await reply(request, profile('node1'));
          case 'GetServices':
            await reply(request, '<t:GetServicesResponse/>');
          case 'GetSystemDateAndTime':
            await reply(request, '<t:GetSystemDateAndTimeResponse/>');
          default:
            request.response.statusCode = 500;
            await reply(request, fault);
        }
      });
      final client = OnvifClient(
        CameraConfig(host: '127.0.0.1', onvifUrl: '$base/device'),
        onEvent: (_) {},
      );
      addTearDown(() async {
        client.close();
        await server.close(force: true);
      });
      await expectLater(
        client.inspect(),
        throwsA(
          isA<OnvifFailure>().having(
            (e) => e.code,
            'code',
            'ptz_capacidades_indeterminadas',
          ),
        ),
      );
    },
  );

  test(
    'Capacidades de outro nó não habilitam controle no perfil selecionado',
    () async {
      final server = await HttpServer.bind('127.0.0.1', 0);
      final base = 'http://127.0.0.1:${server.port}';
      server.listen((request) async {
        final op = operation(await utf8.decoder.bind(request).join());
        switch (op) {
          case 'GetCapabilities':
            await reply(
              request,
              '<t:GetCapabilitiesResponse><t:Media><t:XAddr>$base/device</t:XAddr></t:Media><t:PTZ><t:XAddr>$base/device</t:XAddr></t:PTZ></t:GetCapabilitiesResponse>',
            );
          case 'GetProfiles':
            await reply(request, profile('node2'));
          case 'GetServices':
            await reply(request, '<t:GetServicesResponse/>');
          case 'GetSystemDateAndTime':
            await reply(request, '<t:GetSystemDateAndTimeResponse/>');
          case 'GetNodes':
            await reply(
              request,
              '<t:GetNodesResponse><t:PTZNodes token="node1">$spaces</t:PTZNodes><t:PTZNodes token="node2"/></t:GetNodesResponse>',
            );
          default:
            request.response.statusCode = 500;
            await reply(request, fault);
        }
      });
      final client = OnvifClient(
        CameraConfig(host: '127.0.0.1', onvifUrl: '$base/device'),
        onEvent: (_) {},
      );
      addTearDown(() async {
        client.close();
        await server.close(force: true);
      });
      final result = await client.inspect();
      expect(result.single.supported, false);
    },
  );

  test(
    'Falha de rede em ContinuousMove não é repetida automaticamente',
    () async {
      var moves = 0;
      final server = await HttpServer.bind('127.0.0.1', 0);
      server.listen((request) async {
        await request.drain<void>();
        moves++;
        final socket = await request.response.detachSocket(writeHeaders: false);
        socket.destroy();
      });
      final client = OnvifClient(
        const CameraConfig(host: '127.0.0.1'),
        onEvent: (_) {},
      );
      addTearDown(() async {
        client.close();
        await server.close(force: true);
      });
      final uri = Uri.parse('http://127.0.0.1:${server.port}/ptz');
      await expectLater(
        client.move(
          PtzProfile(
            'main',
            'Main',
            uri,
            VelocitySpace('urn:pan', -1, 1, -1, 1),
            null,
          ),
          1,
          0,
          0,
        ),
        throwsA(isA<OnvifFailure>()),
      );
      expect(moves, 1);
    },
  );
}
