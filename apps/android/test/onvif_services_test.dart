import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:jortan_viewer/camera.dart';
import 'package:jortan_viewer/onvif.dart';
import 'package:xml/xml.dart';
import 'onvif_compatibility_test.dart'
    show spaces, profile, operation, reply, fault;

class FailedPortsClient extends OnvifClient {
  FailedPortsClient() : super(const CameraConfig(), onEvent: (_) {});
  @override
  Future<XmlDocument> call(
    Uri uri,
    String ns,
    String operation,
    String body, {
    bool authenticated = true,
  }) async {
    throw OnvifFailure(
      uri.port == 5000 ? 'timeout' : 'tcp_recusado',
      'fixture',
    );
  }
}

void main() {
  test(
    'Regressão: endpoints trocados em GetCapabilities são comparados por namespace em GetServices',
    () async {
      final server = await HttpServer.bind('127.0.0.1', 0);
      final base = 'http://127.0.0.1:${server.port}';
      final events = <Map<String, dynamic>>[];
      final calls = <String>[];
      server.listen((request) async {
        final op = operation(await utf8.decoder.bind(request).join());
        calls.add('$op ${request.uri.path}');
        switch (op) {
          case 'GetCapabilities':
            await reply(
              request,
              '<t:GetCapabilitiesResponse><t:Media XAddr="$base/onvif/ptz_service"/><t:PTZ><t:XAddr>$base/onvif/deviceio_service</t:XAddr></t:PTZ></t:GetCapabilitiesResponse>',
            );
          case 'GetSystemDateAndTime':
            await reply(request, '<t:GetSystemDateAndTimeResponse/>');
          case 'GetServices':
            await reply(
              request,
              '<t:GetServicesResponse>'
              '<t:Service><t:Namespace>http://www.onvif.org/ver10/media/wsdl</t:Namespace><t:XAddr>$base/onvif/media_service</t:XAddr></t:Service>'
              '<t:Service><t:Namespace>http://www.onvif.org/ver10/deviceIO/wsdl</t:Namespace><t:XAddr>$base/onvif/ptz_service</t:XAddr></t:Service>'
              '<t:Service><t:Namespace>http://www.onvif.org/ver20/ptz/wsdl</t:Namespace><t:XAddr>$base/onvif/actual_ptz</t:XAddr></t:Service>'
              '</t:GetServicesResponse>',
            );
          case 'GetProfiles':
            expect(request.uri.path, '/onvif/media_service');
            await reply(request, profile('n1'));
          case 'GetConfigurationOptions':
            expect(request.uri.path, '/onvif/actual_ptz');
            await reply(
              request,
              '<t:GetConfigurationOptionsResponse><t:Spaces>$spaces</t:Spaces></t:GetConfigurationOptionsResponse>',
            );
          default:
            fail('Unexpected $op');
        }
      });
      final client = OnvifClient(
        CameraConfig(host: '127.0.0.1', onvifUrl: '$base/onvif/device_service'),
        onEvent: events.add,
      );
      addTearDown(() async {
        client.close();
        await server.close(force: true);
      });
      final profiles = await client.inspect();
      expect(profiles.single.endpoint.path, '/onvif/actual_ptz');
      expect(profiles.single.panTilt, isNotNull);
      expect(calls.where((c) => c.startsWith('ContinuousMove')), isEmpty);
      expect(
        events
            .where((e) => e['operacao'] == 'servicos_anunciados')
            .single['servicosPorNamespace'],
        isA<Map>(),
      );
    },
  );

  test(
    'Sem GetServices, consulta PTZ também testa ptz_service que respondeu como mídia',
    () async {
      final server = await HttpServer.bind('127.0.0.1', 0);
      final base = 'http://127.0.0.1:${server.port}';
      final calls = <String>[];
      server.listen((request) async {
        final op = operation(await utf8.decoder.bind(request).join());
        calls.add(op);
        switch (op) {
          case 'GetCapabilities':
            await reply(
              request,
              '<t:GetCapabilitiesResponse><t:Media><t:XAddr>$base/onvif/ptz_service</t:XAddr></t:Media><t:PTZ><t:XAddr>$base/onvif/deviceio_service</t:XAddr></t:PTZ></t:GetCapabilitiesResponse>',
            );
          case 'GetProfiles':
            await reply(request, profile('n1'));
          case 'GetSystemDateAndTime':
            await reply(request, '<t:GetSystemDateAndTimeResponse/>');
          case 'GetServices':
            request.response.statusCode = 500;
            await reply(request, fault);
          case 'GetConfigurationOptions':
            if (request.uri.path == '/onvif/ptz_service') {
              await reply(
                request,
                '<t:GetConfigurationOptionsResponse><t:Spaces>$spaces</t:Spaces></t:GetConfigurationOptionsResponse>',
              );
            } else {
              final socket = await request.response.detachSocket(
                writeHeaders: false,
              );
              socket.destroy();
            }
          default:
            fail('Unexpected $op');
        }
      });
      final client = OnvifClient(
        CameraConfig(host: '127.0.0.1', onvifUrl: '$base/onvif/device_service'),
        onEvent: (_) {},
      );
      addTearDown(() async {
        client.close();
        await server.close(force: true);
      });
      final result = await client.inspect();
      expect(result.single.endpoint.path, '/onvif/ptz_service');
      expect(result.single.supported, true);
      expect(calls.where((c) => c == 'ContinuousMove'), isEmpty);
    },
  );

  test(
    'Erro final preserva timeout na porta 5000 em vez da primeira porta recusada',
    () async {
      final client = FailedPortsClient();
      addTearDown(client.close);
      await expectLater(
        client.inspect(),
        throwsA(isA<OnvifFailure>().having((e) => e.code, 'code', 'timeout')),
      );
    },
  );

  test(
    'GetNodes e GetNode com mesma consulta falha não são repetidos em cada perfil',
    () async {
      final server = await HttpServer.bind('127.0.0.1', 0);
      final base = 'http://127.0.0.1:${server.port}';
      final nodeCalls = <String, int>{};
      server.listen((request) async {
        final body = await utf8.decoder.bind(request).join();
        final op = operation(body);
        switch (op) {
          case 'GetCapabilities':
            await reply(
              request,
              '<t:GetCapabilitiesResponse><t:Media><t:XAddr>$base/device</t:XAddr></t:Media><t:PTZ><t:XAddr>$base/device</t:XAddr></t:PTZ></t:GetCapabilitiesResponse>',
            );
          case 'GetProfiles':
            await reply(
              request,
              profile('n1').replaceFirst(
                '</t:GetProfilesResponse>',
                '<t:Profiles token="secondary"><t:PTZConfiguration token="config2"><t:NodeToken>n1</t:NodeToken></t:PTZConfiguration></t:Profiles></t:GetProfilesResponse>',
              ),
            );
          case 'GetSystemDateAndTime':
            await reply(request, '<t:GetSystemDateAndTimeResponse/>');
          case 'GetServices':
            await reply(request, '<t:GetServicesResponse/>');
          default:
            if (['GetNodes', 'GetNode'].contains(op)) {
              final method = XmlDocument.parse(body).descendants
                  .whereType<XmlElement>()
                  .firstWhere((e) => e.name.local == 'Body')
                  .childElements
                  .single;
              final key =
                  '$op ${request.uri.path} ${method.name.prefix ?? 'default'}';
              nodeCalls[key] = (nodeCalls[key] ?? 0) + 1;
            }
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
      expect(nodeCalls, isNotEmpty);
      expect(nodeCalls.values.every((count) => count == 1), true);
    },
  );

  test('Endereço GetServices fora do IP não recebe credenciais', () async {
    final foreign = await HttpServer.bind('127.0.0.2', 0);
    var received = 0;
    foreign.listen((request) async {
      received++;
      await request.drain<void>();
      await request.response.close();
    });
    final server = await HttpServer.bind('127.0.0.1', 0);
    final base = 'http://127.0.0.1:${server.port}';
    server.listen((request) async {
      final op = operation(await utf8.decoder.bind(request).join());
      switch (op) {
        case 'GetCapabilities':
          await reply(
            request,
            '<t:GetCapabilitiesResponse><t:Media><t:XAddr>$base/media</t:XAddr></t:Media></t:GetCapabilitiesResponse>',
          );
        case 'GetSystemDateAndTime':
          await reply(request, '<t:GetSystemDateAndTimeResponse/>');
        case 'GetServices':
          await reply(
            request,
            '<t:GetServicesResponse><t:Service><t:Namespace>http://www.onvif.org/ver20/ptz/wsdl</t:Namespace><t:XAddr>http://127.0.0.2:${foreign.port}/ptz</t:XAddr></t:Service></t:GetServicesResponse>',
          );
        default:
          fail('Unexpected $op');
      }
    });
    final client = OnvifClient(
      CameraConfig(
        host: '127.0.0.1',
        password: 'fixture-only',
        onvifUrl: '$base/device',
      ),
      onEvent: (_) {},
    );
    addTearDown(() async {
      client.close();
      await server.close(force: true);
      await foreign.close(force: true);
    });
    await expectLater(
      client.inspect(),
      throwsA(
        isA<OnvifFailure>().having((e) => e.code, 'code', 'ptz_nao_anunciado'),
      ),
    );
    expect(received, 0);
  });
}
