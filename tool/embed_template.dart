// tool/embed_template.dart
//
// Genera lib/src/viewer/_template.dart desde tool/graph.html.
// Ejecutar tras cualquier edición al template HTML:
//   dart tool/embed_template.dart

import 'dart:io';

void main() {
  const sourcePath = 'tool/graph.html';
  const targetPath = 'lib/src/viewer/_template.dart';
  const placeholder = '/* GRAPH_JSON_PLACEHOLDER */';

  final source = File(sourcePath);
  if (!source.existsSync()) {
    stderr.writeln(
      'Error: $sourcePath no existe. Ejecutar desde la raíz del repo.',
    );
    exit(1);
  }

  final content = source.readAsStringSync();
  final lineCount = '\n'.allMatches(content).length + 1;

  // Cuenta solo ocurrencias "bare" del placeholder: líneas cuyo contenido
  // recortado es exactamente el placeholder (excluyendo referencias en
  // comentarios HTML o literales de cadena de la documentación).
  final bareOccurrences = content
      .split('\n')
      .where((line) => line.trim() == placeholder)
      .length;

  if (bareOccurrences != 1) {
    stderr.writeln(
      'Error: el placeholder "$placeholder" aparece $bareOccurrences veces '
      'como línea independiente en $sourcePath (se espera exactamente 1).',
    );
    exit(1);
  }

  final tripleQuoteIdx = content.indexOf("'''");
  if (tripleQuoteIdx != -1) {
    final line =
        '\n'.allMatches(content.substring(0, tripleQuoteIdx)).length + 1;
    stderr.writeln(
      "Error: $sourcePath contiene ''' en la línea $line — rompería el "
      'raw string de Dart.',
    );
    exit(1);
  }

  final sb = StringBuffer()
    ..writeln('// GENERATED — no editar directamente.')
    ..writeln('// Fuente: $sourcePath')
    ..writeln('// Para regenerar: dart tool/embed_template.dart')
    ..writeln('//')
    ..writeln('// ignore_for_file: lines_longer_than_80_chars')
    ..writeln()
    ..write("const String kGraphHtmlTemplate = r'''")
    ..writeln()
    ..write(content)
    ..writeln()
    ..writeln("''';");

  Directory('lib/src/viewer').createSync(recursive: true);
  File(targetPath).writeAsStringSync(sb.toString());
  stdout.writeln('Template embebido: $lineCount líneas → $targetPath');
}
