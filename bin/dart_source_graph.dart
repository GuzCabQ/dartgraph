// bin/dart_source_graph.dart
//
// Entry point del ejecutable CLI.
// Uso: dart_source_graph <build|query|view|report> [opciones]

import 'dart:io';
import 'dart:isolate';

import 'package:args/command_runner.dart';
import 'package:dart_source_graph/src/cli/build_command.dart';
import 'package:dart_source_graph/src/cli/query_command.dart';
import 'package:dart_source_graph/src/cli/report_command.dart';
import 'package:dart_source_graph/src/cli/view_command.dart';
import 'package:yaml/yaml.dart';

Future<void> main(List<String> args) async {
  final runner =
      CommandRunner<int>(
          'dart_source_graph',
          'Genera y consulta el grafo de código fuente de un proyecto Dart/Flutter.',
        )
        ..argParser.addFlag(
          'version',
          abbr: 'v',
          negatable: false,
          help: 'Muestra la versión instalada y termina.',
        )
        ..addCommand(BuildCommand())
        ..addCommand(QueryCommand())
        ..addCommand(ViewCommand())
        ..addCommand(ReportCommand());

  // Atajo de nivel superior: `dart_source_graph --version` / `-v`.
  if (args.isNotEmpty && (args.first == '--version' || args.first == '-v')) {
    stdout.writeln('dart_source_graph ${await _packageVersion()}');
    exit(0);
  }

  try {
    final code = await runner.run(args) ?? 0;
    exit(code);
  } on UsageException catch (e) {
    stderr.writeln(e.message);
    exit(64);
  }
}

/// Lee la versión del `pubspec.yaml` del propio package.
///
/// Resuelve la ubicación real del package vía el package config, de modo que
/// funcione tanto corriendo desde el repo como instalado globalmente por path.
/// Si algo falla, devuelve `desconocida` en lugar de romper.
Future<String> _packageVersion() async {
  try {
    final libUri = await Isolate.resolvePackageUri(
      Uri.parse('package:dart_source_graph/dart_source_graph.dart'),
    );
    if (libUri == null) return 'desconocida';
    // libUri -> <root>/lib/dart_source_graph.dart ; subimos a <root>.
    final pubspec = File.fromUri(libUri.resolve('../pubspec.yaml'));
    if (!pubspec.existsSync()) return 'desconocida';
    final yaml = loadYaml(await pubspec.readAsString());
    return (yaml is Map && yaml['version'] != null)
        ? yaml['version'].toString()
        : 'desconocida';
  } catch (_) {
    return 'desconocida';
  }
}
