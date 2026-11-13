import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:jortan_viewer/remote_access.dart';
import 'package:jortan_viewer/design.dart';

void main() {
  test(
    'Endereço remoto aceita HTTPS sem credenciais e recusa formatos inseguros',
    () {
      expect(
        remoteAddress('https://viewer.example.test')?.host,
        'viewer.example.test',
      );
      for (final value in [
        'http://viewer.test',
        'https://user:secret@viewer.test',
        'https://viewer.test/?token=x',
        'https://viewer.test/#secret',
        'javascript:alert(1)',
        'https://viewer.test/path',
      ]) {
        expect(remoteAddress(value), isNull);
      }
    },
  );
  testWidgets(
    'Acesso remoto guarda endereço e abre visualizador sem senha local',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      String? launched;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: RemoteAccess(launcher: (url) async => launched = url),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Acesso de longe'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField),
        'https://viewer.example.test',
      );
      await tester.tap(find.text('Abrir câmera remota'));
      await tester.pumpAndSettle();
      expect(launched, 'https://viewer.example.test');
      expect(
        await const FlutterSecureStorage().read(key: 'remote_url.v1'),
        launched,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('URL inválida não abre atividade nem salva senha em endereço', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: RemoteAccess(
              launcher: (_) async {
                calls++;
              },
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Acesso de longe'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField),
      'https://user:secret@viewer.test',
    );
    await tester.tap(find.text('Abrir câmera remota'));
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(find.textContaining('sem senha na URL'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
