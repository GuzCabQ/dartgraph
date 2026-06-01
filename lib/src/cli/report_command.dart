// lib/src/cli/report_command.dart
//
// Subcomando `report`: lee graph.json y genera GRAPH_REPORT.md.
// El archivo de salida queda en el mismo directorio que el JSON de entrada,
// siguiendo el mismo patrón que `view` (todos los artefactos juntos).

import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import '../contracts/code_graph.dart';
import '../core/query.dart';
import '../core/reporter.dart';

class ReportCommand extends Command<int> {
  ReportCommand() {
    argParser
      ..addOption(
        'input',
        abbr: 'i',
        defaultsTo: 'graph.json',
        help: 'Path al graph.json a leer.',
        valueHelp: 'graph.json',
      )
      ..addOption(
        'output',
        abbr: 'o',
        help:
            'Path de salida. Por defecto: mismo dir que --input. '
            'Usa "-" para stdout.',
        valueHelp: 'GRAPH_REPORT.md',
      )
      ..addOption(
        'god-limit',
        defaultsTo: '20',
        help: 'Top-N god nodes a mostrar.',
        valueHelp: 'N',
      );
  }

  @override
  String get name => 'report';

  @override
  String get description =>
      'Genera GRAPH_REPORT.md desde un graph.json existente.';

  @override
  Future<int> run() async {
    final res = argResults!;
    final inputPath = res['input'] as String;
    final outputPath = res['output'] as String?;
    final godLimit = int.tryParse(res['god-limit'] as String) ?? 20;

    // Mismo dir que el JSON de entrada, igual que `view` coloca el HTML.
    final resolvedOutput =
        outputPath ??
        p.join(p.dirname(p.canonicalize(inputPath)), 'GRAPH_REPORT.md');

    final inputFile = File(inputPath);
    if (!inputFile.existsSync()) {
      stderr.writeln('Error: archivo no encontrado: $inputPath');
      return 66;
    }

    final Map<String, Object?> doc;
    try {
      doc = jsonDecode(inputFile.readAsStringSync()) as Map<String, Object?>;
    } on FormatException catch (e) {
      stderr.writeln('Error: JSON inválido en $inputPath: $e');
      return 65;
    }

    final graph = CodeGraph.fromJson(doc);
    final meta = CodeGraphMeta.fromJson(doc);

    final report = generateReport(graph, meta, godLimit: godLimit);

    if (resolvedOutput == '-') {
      stdout.writeln(report);
      return 0;
    }

    File(resolvedOutput).writeAsStringSync(report);

    final clusterCount = CodeGraphQuery(graph).structure().clusters.length;
    stderr.writeln(
      'Escrito: $resolvedOutput (${graph.nodes.length} nodos, $clusterCount clusters)',
    );
    return 0;
  }
}
