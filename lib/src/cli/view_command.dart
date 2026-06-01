// lib/src/cli/view_command.dart
//
// Subcomando `view`: genera graph.html desde un graph.json existente.
// No re-analiza el proyecto — solo regenera el visor HTML.

import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import '../viewer/html_exporter.dart';

class ViewCommand extends Command<int> {
  ViewCommand() {
    argParser
      ..addOption(
        'graph',
        abbr: 'g',
        mandatory: true,
        help: 'Ruta al graph.json de entrada.',
        valueHelp: 'graph.json',
      )
      ..addOption(
        'output',
        abbr: 'o',
        help:
            'Ruta del graph.html de salida. '
            'Por defecto: mismo directorio que --graph.',
        valueHelp: 'graph.html',
      );
  }

  @override
  String get name => 'view';

  @override
  String get description =>
      'Genera un visor HTML desde un graph.json existente.';

  @override
  Future<int> run() async {
    final res = argResults!;
    final graphPath = res['graph'] as String;
    final outputPath = res['output'] as String?;

    final graphFile = File(graphPath);
    if (!graphFile.existsSync()) {
      stderr.writeln('Error: archivo no encontrado: $graphPath');
      return 2;
    }

    final String jsonString;
    try {
      jsonString = graphFile.readAsStringSync();
    } on FileSystemException catch (e) {
      stderr.writeln('Error al leer $graphPath: $e');
      return 2;
    }

    // Lee summary para el mensaje de confirmación; no reconstruye CodeGraph.
    var nodeCount = '?';
    var edgeCount = '?';
    try {
      final doc = jsonDecode(jsonString) as Map<String, Object?>;
      final summary = doc['summary'] as Map<String, Object?>?;
      nodeCount = '${summary?['nodes'] ?? '?'}';
      edgeCount = '${summary?['edges'] ?? '?'}';
    } catch (_) {
      // JSON inválido — el visor lo mostrará internamente.
    }

    final canonicalGraph = p.canonicalize(graphPath);
    final outputDir = outputPath != null
        ? p.dirname(p.canonicalize(outputPath))
        : p.dirname(canonicalGraph);
    final fileName =
        outputPath != null ? p.basename(outputPath) : 'graph.html';

    try {
      final htmlPath = writeHtmlViewerFromJson(
        jsonString: jsonString,
        outputDir: outputDir,
        fileName: fileName,
      );
      stdout.writeln(
        'Visor generado: $htmlPath  ($nodeCount nodos · $edgeCount aristas)',
      );
      return 0;
    } on StateError catch (e) {
      stderr.writeln('Error al generar el visor: $e');
      return 2;
    } on FileSystemException catch (e) {
      stderr.writeln('Error al escribir el visor: $e');
      return 2;
    }
  }
}
