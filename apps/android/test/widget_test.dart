import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:jortan_viewer/app.dart';
import 'package:jortan_viewer/camera.dart';

void main() {
  testWidgets('Primeiro uso no celular abre configuração sem iniciar conexão', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const JortanApp());
    await tester.pumpAndSettle();
    expect(find.text('Configurar minha câmera'), findsOneWidget);
    await tester.tap(find.text('Configurar minha câmera'));
    await tester.pumpAndSettle();
    expect(find.text('Encontre sua câmera.'), findsOneWidget);
    expect(find.text('192.168.1.100'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Formulário rejeita porta inválida e mantém senha oculta', (
    tester,
  ) async {
    CameraConfig? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CameraSettings(
            initial: const CameraConfig(),
            onSave: (camera, _) async => saved = camera,
          ),
        ),
      ),
    );
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(1), '70000');
    final password = tester.widget<TextField>(
      find.descendant(of: fields.at(3), matching: find.byType(TextField)),
    );
    expect(password.obscureText, isTrue);
    final save = find.text('Salvar para depois');
    await tester.scrollUntilVisible(
      save,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(saved, isNull);
    expect(find.text('A porta deve estar entre 1 e 65535.'), findsOneWidget);
  });
  testWidgets('Layout suporta orientação horizontal sem overflow', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});
    tester.view.physicalSize = const Size(844, 390);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const JortanApp());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets('Navegação remota cabe em tela estreita sem iniciar a câmera', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const JortanApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remoto'));
    await tester.pumpAndSettle();
    expect(find.text('Abrir câmera remota'), findsOneWidget);
    expect(find.text('Endereço HTTPS da ponte'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Ao vivo'));
    await tester.pumpAndSettle();
    expect(find.text('Configurar minha câmera'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
