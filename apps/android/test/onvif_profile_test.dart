import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:jortan_viewer/camera.dart';
import 'package:jortan_viewer/onvif.dart';
import 'onvif_compatibility_test.dart'
    show spaces, profile, operation, reply, fault;

const generic =
    'http://www.onvif.org/ver10/tptz/PanTiltSpaces/VelocityGenericSpace';

void main() {
  for (final declared in [true, false]) {
    test(
      declared
          ? 'Espaço genérico explicitamente declarado permite apenas perfil de teste manual'
          : 'Espaço vendor desconhecido não habilita capacidades por suposição',
      () async {
        final server = await HttpServer.bind('127.0.0.1', 0);
        final base = 'http://127.0.0.1:${server.port}';
        var moves = 0;
        server.listen((request) async {
          final body = await utf8.decoder.bind(request).join();
          final op = operation(body);
          switch (op) {
            case 'GetCapabilities':
              await reply(
                request,
                '<t:GetCapabilitiesResponse><t:Media><t:XAddr>$base/device</t:XAddr></t:Media><t:PTZ><t:XAddr>$base/ptz</t:XAddr></t:PTZ></t:GetCapabilitiesResponse>',
              );
            case 'GetSystemDateAndTime':
              await reply(request, '<t:GetSystemDateAndTimeResponse/>');
            case 'GetServices':
              await reply(request, '<t:GetServicesResponse/>');
            case 'GetProfiles':
              await reply(
                request,
                profile('node1').replaceFirst(
                  '</t:PTZConfiguration>',
                  '<t:DefaultContinuousPanTiltVelocitySpace>${declared ? generic : 'urn:vendor:unknown'}</t:DefaultContinuousPanTiltVelocitySpace></t:PTZConfiguration>',
                ),
              );
            case 'ContinuousMove':
              moves++;
              expect(body, contains('<tptz:ContinuousMove>'));
              expect(body, contains('x="0.1"'));
              await reply(request, '<t:ContinuousMoveResponse/>');
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
        if (declared) {
          final result = await client.inspect();
          expect(result.single.requiresTest, true);
          expect(result.single.zoom, isNull);
          expect(moves, 0);
          await client.move(result.single, 1, 0, 0);
          expect(moves, 1);
        } else {
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
          expect(moves, 0);
        }
      },
    );
  }
  test(
    'GetServices com contêiner alternativo/atributos é resumido sem SOAP ou senha',
    () async {
      final server = await HttpServer.bind('127.0.0.1', 0);
      final base = 'http://127.0.0.1:${server.port}';
      final events = <Map<String, dynamic>>[];
      server.listen((request) async {
        final op = operation(await utf8.decoder.bind(request).join());
        switch (op) {
          case 'GetCapabilities':
            await reply(
              request,
              '<t:GetCapabilitiesResponse><t:Media XAddr="$base/media"/><t:PTZ XAddr="$base/wrong"/></t:GetCapabilitiesResponse>',
            );
          case 'GetSystemDateAndTime':
            await reply(request, '<t:GetSystemDateAndTimeResponse/>');
          case 'GetServices':
            await reply(
              request,
              '<t:GetServicesResponse><t:Services><t:Entry Namespace="http://www.onvif.org/ver20/ptz/wsdl/" XAddr="$base/actual"/><t:Entry Namespace="http://vendor.test/fixture-secret" XAddr="$base/vendor"/></t:Services></t:GetServicesResponse>',
            );
          case 'GetProfiles':
            await reply(request, profile('node1'));
          case 'GetConfigurationOptions':
            expect(request.uri.path, '/actual');
            await reply(
              request,
              '<t:GetConfigurationOptionsResponse>$spaces</t:GetConfigurationOptionsResponse>',
            );
          default:
            fail('Unexpected $op');
        }
      });
      final client = OnvifClient(
        CameraConfig(
          host: '127.0.0.1',
          password: 'fixture-secret',
          onvifUrl: '$base/device',
        ),
        onEvent: events.add,
      );
      addTearDown(() async {
        client.close();
        await server.close(force: true);
      });
      final result = await client.inspect();
      expect(result.single.endpoint.path, '/actual');
      expect(
        events
            .where((e) => e['operacao'] == 'estrutura_GetServices')
            .single['reconhecidos'],
        1,
      );
      expect(jsonEncode(events), isNot(contains('fixture-secret')));
    },
  );
}
