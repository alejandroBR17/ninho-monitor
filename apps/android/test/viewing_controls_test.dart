import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jortan_viewer/camera.dart';
import 'package:jortan_viewer/design.dart';
import 'package:jortan_viewer/viewing_controls.dart';
import 'package:jortan_viewer/playback_options.dart';

void main() {
  test('Preferência de fluxo preserva acesso, transporte e endpoint ONVIF', () {
    const original = CameraConfig(
      host: '192.168.1.20',
      port: 8554,
      username: 'viewer',
      password: 'fixture@only',
      onvifUrl: 'http://192.168.1.20:5000/onvif/device_service',
      transport: Transport.tcp,
    );
    final fluid = original.withPreset(ViewingPreset.fluid);
    expect(fluid.path, '/onvif2');
    expect(fluid.tuning, PlaybackTuning.responsive);
    expect(fluid.host, original.host);
    expect(fluid.uri.userInfo, original.uri.userInfo);
    expect(fluid.onvifUrl, original.onvifUrl);
    expect(fluid.transport, original.transport);
    expect(
      CameraConfig.fromJson(fluid.toJson()).tuning,
      PlaybackTuning.responsive,
    );
    expect(fluid.withPreset(ViewingPreset.details).path, '/onvif1');
  });
  test(
    'Configuração antiga e caminho personalizado não são trocados silenciosamente',
    () {
      final json = const CameraConfig(path: '/vendor/live').toJson()
        ..remove('tuning');
      final camera = CameraConfig.fromJson(json);
      expect(camera.path, '/vendor/live');
      expect(camera.preset, isNull);
      expect(camera.tuning, PlaybackTuning.compatible);
      expect(
        camera.copyWith(tuning: PlaybackTuning.responsive).path,
        '/vendor/live',
      );
    },
  );
  test(
    'Menor atraso mantém análise HEVC, áudio inicialmente desativado e não descarta SPS/PPS',
    () {
      final options = playbackOptions(
        const CameraConfig(tuning: PlaybackTuning.responsive),
        Transport.tcp,
      );
      expect(options['aid'], 'no');
      expect(options['demuxer-lavf-o'], contains('analyzeduration=10000000'));
      expect(options.values.join(), isNot(contains('nobuffer')));
      expect(options['demuxer-readahead-secs'], '0');
    },
  );
  testWidgets(
    'Fluxo alternativo é escolha explícita e resolução não é anunciada antes de chegar',
    (tester) async {
      ViewingPreset? chosen;
      var refreshes = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: ViewingControls(
              config: const CameraConfig(),
              changing: false,
              live: false,
              onPreset: (p) => chosen = p,
              onRefresh: () => refreshes++,
            ),
          ),
        ),
      );
      expect(find.textContaining('Full HD'), findsNothing);
      await tester.tap(find.text('Mais fluido'));
      await tester.pump();
      expect(chosen, ViewingPreset.fluid);
      expect(refreshes, 0);
    },
  );
  testWidgets(
    'Exibe apenas a resolução recebida e permite atualizar transmissão',
    (tester) async {
      var refreshes = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: ViewingControls(
              config: const CameraConfig(),
              changing: false,
              live: true,
              width: 1920,
              height: 1080,
              onPreset: (_) {},
              onRefresh: () => refreshes++,
            ),
          ),
        ),
      );
      expect(find.text('Recebido: 1920 × 1080 · Full HD'), findsOneWidget);
      await tester.tap(find.text('Atualizar transmissão'));
      expect(refreshes, 1);
    },
  );
  testWidgets('Controles de imagem cabem no celular com texto ampliado', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.5)),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: ViewingControls(
                config: const CameraConfig(),
                changing: false,
                live: true,
                width: 640,
                height: 360,
                onPreset: (_) {},
                onRefresh: () {},
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
