import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jortan_viewer/discovery.dart';
import 'package:jortan_viewer/discovery_screen.dart';

class FakeDiscovery extends CameraDiscovery {
  @override
  Future<DiscoveryReport> search(
    DiscoveryRange range, {
    List<int> ports = const [554, 8554],
    void Function(DiscoveryReport)? onUpdate,
    bool onvif = true,
  }) async {
    final report = DiscoveryReport(range.toString(), ports)
      ..total = 4
      ..completed = 4;
    report.devices['192.168.1.100'] = const DiscoveryDevice(
      '192.168.1.100',
      rtspStatuses: {554: 401},
    );
    report.ended = DateTime.now().toUtc();
    onUpdate?.call(report);
    return report;
  }
}

void main() {
  testWidgets(
    'Busca apresenta resultado RTSP e devolve IP e porta escolhidos',
    (tester) async {
      DiscoveryDevice? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  selected = await Navigator.of(context).push<DiscoveryDevice>(
                    MaterialPageRoute(
                      builder: (_) => DiscoveryScreen(
                        initialHost: '192.168.1.100',
                        factory: FakeDiscovery.new,
                        rangeLoader: () async => ['192.168.1.0/24'],
                      ),
                    ),
                  );
                },
                child: const Text('Abrir busca'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Abrir busca'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Buscar agora'));
      await tester.pumpAndSettle();
      final device = find.text('Dispositivo RTSP');
      await tester.scrollUntilVisible(
        device,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(device);
      await tester.pumpAndSettle();
      expect(selected?.host, '192.168.1.100');
      expect(selected?.port, 554);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Interface iPhone explica permissão local e rejeita faixa pública',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.iOS),
          home: DiscoveryScreen(
            initialHost: '192.168.1.100',
            factory: FakeDiscovery.new,
            rangeLoader: () async => ['192.168.1.0/24'],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Permita'), findsNothing);
      expect(
        find.textContaining('permita o acesso à Rede Local'),
        findsOneWidget,
      );
      await tester.enterText(find.byType(TextField), '8.8.8.0/24');
      await tester.tap(find.text('Buscar agora'));
      await tester.pumpAndSettle();
      expect(find.textContaining('apenas sua rede privada'), findsOneWidget);
    },
  );
}
