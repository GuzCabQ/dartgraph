// bin/dart_source_graph.dart
//
// Entry point del ejecutable CLI.
// Uso: dart_source_graph <build|query|view|report> [opciones]

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dart_source_graph/src/cli/build_command.dart';
import 'package:dart_source_graph/src/cli/query_command.dart';
import 'package:dart_source_graph/src/cli/report_command.dart';
import 'package:dart_source_graph/src/cli/view_command.dart';

Future<void> main(List<String> args) async {
  final runner =
      CommandRunner<int>(
          'dart_source_graph',
          'Genera y consulta el grafo de código fuente de un proyecto Dart/Flutter.',
        )
        ..addCommand(BuildCommand())
        ..addCommand(QueryCommand())
        ..addCommand(ViewCommand())
        ..addCommand(ReportCommand());

  try {
    final code = await runner.run(args) ?? 0;
    exit(code);
  } on UsageException catch (e) {
    stderr.writeln(e.message);
    exit(64);
  }
}
