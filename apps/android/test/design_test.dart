import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jortan_viewer/design.dart';

double contrast(Color a, Color b) {
  final first = a.computeLuminance(), second = b.computeLuminance();
  return ((first > second ? first : second) + .05) /
      ((first > second ? second : first) + .05);
}

void main() {
  test(
    'Paleta de texto atende ao contraste pedido em todas as superfícies',
    () {
      for (final text in [
        textPrimary,
        textSecondary,
        accent,
        const Color(0xFFFFBCAD),
      ]) {
        for (final surface in [appBackground, panel, inputSurface]) {
          expect(contrast(text, surface), greaterThanOrEqualTo(4.5));
        }
      }
      expect(contrast(onAccent, accent), greaterThanOrEqualTo(4.5));
    },
  );
  test('Tema usa dois pesos e botões com altura mínima de 48', () {
    final theme = buildAppTheme();
    expect(theme.filledButtonTheme.style!.minimumSize!.resolve({})!.height, 48);
    expect(
      theme.outlinedButtonTheme.style!.minimumSize!.resolve({})!.height,
      48,
    );
    expect(theme.textButtonTheme.style!.minimumSize!.resolve({})!.height, 48);
    expect(theme.iconButtonTheme.style!.minimumSize!.resolve({})!.height, 48);
    final text = theme.textTheme;
    final weights = [
      text.bodyLarge,
      text.bodyMedium,
      text.bodySmall,
      text.titleLarge,
      text.titleMedium,
      text.titleSmall,
      text.labelLarge,
      text.labelMedium,
      text.labelSmall,
      text.headlineLarge,
      text.headlineMedium,
      text.headlineSmall,
      text.displayLarge,
      text.displayMedium,
      text.displaySmall,
    ].map((s) => s!.fontWeight).toSet();
    expect(weights, {FontWeight.w400, FontWeight.w600});
    expect(theme.chipTheme.side, BorderSide.none);
  });
}
