// lib/src/cli/query_command.dart
//
// Subcomando `query`: consultas read-only sobre un graph.json preexistente.
// Subcomandos: impact, neighbors, god-nodes.

import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import '../config/source_graph_config.dart';
import '../contracts/code_graph.dart';
import '../core/builder.dart';
import '../core/files.dart';
import '../core/query.dart';

class QueryCommand extends Command<int> {
  QueryCommand() {
    addSubcommand(_ImpactSubcommand());
    addSubcommand(_NeighborsSubcommand());
    addSubcommand(_GodNodesSubcommand());
  }

  @override
  String get name => 'query';

  @override
  String get description =>
      'Consulta un graph.json preexistente: impact, neighbors, god-nodes.';
}

void _addCommonOptions(ArgParser parser) {
  parser
    ..addOption(
      'input',
      abbr: 'i',
      defaultsTo: 'graph.json',
      help: 'Ruta al graph.json.',
    )
    ..addOption(
      'project-root',
      abbr: 'r',
      defaultsTo: '.',
      help: 'Raíz del proyecto (para verificación de frescura).',
    )
    ..addOption(
      'format',
      defaultsTo: 'text',
      allowed: ['text', 'json'],
      help: 'Formato de salida.',
    );
}

/// Carga el grafo y advierte si está desactualizado (sin config externa).
CodeGraph? _loadGraph(ArgResults res) {
  final projectRoot = p.canonicalize(res['project-root'] as String);
  final rawInput = res['input'] as String;
  final inputPath = p.isAbsolute(rawInput)
      ? rawInput
      : p.join(projectRoot, rawInput);
  final file = File(inputPath);
  if (!file.existsSync()) {
    stderr.writeln('Error: archivo no encontrado: $inputPath');
    return null;
  }
  final Map<String, Object?> doc;
  try {
    doc = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
  } catch (e) {
    stderr.writeln('Error: no se pudo parsear $inputPath: $e');
    return null;
  }
  // Verificación de frescura — opcional, falla silenciosa.
  try {
    final files = collectDartFiles(projectRoot, const SourceGraphConfig());
    final current = CodeGraphBuilder.inputsFingerprint(projectRoot, files);
    final stored = doc['inputs_fingerprint'] as String?;
    if (stored != null && stored != current) {
      stderr.writeln(
        'Aviso: grafo desactualizado — re-ejecuta `dart_source_graph build`.',
      );
    }
  } catch (_) {
    // Verificación opcional; no interrumpe la consulta.
  }
  try {
    return CodeGraph.fromJson(doc);
  } catch (e) {
    stderr.writeln('Error: $inputPath no es un grafo válido: $e');
    return null;
  }
}

/// Resuelve [nameOrId] a un único id de nodo.
/// Imprime error y retorna null en caso de ambigüedad o sin coincidencia.
String? _resolveOne(CodeGraphQuery q, String nameOrId) {
  final matches = q.resolveNodes(nameOrId);
  if (matches.isEmpty) {
    stderr.writeln('Error: ningún nodo coincide con "$nameOrId".');
    return null;
  }
  if (matches.length > 1) {
    stderr.writeln('Error: "$nameOrId" es ambiguo; usa un id completo:');
    for (final n in matches) {
      stderr.writeln('  ${n.id}');
    }
    return null;
  }
  return matches.single.id;
}

class _ImpactSubcommand extends Command<int> {
  _ImpactSubcommand() {
    _addCommonOptions(argParser);
  }

  @override
  String get name => 'impact';

  @override
  String get description => 'Qué depende transitivamente de un nodo.';

  @override
  Future<int> run() async {
    final res = argResults!;
    if (res.rest.isEmpty) {
      stderr.writeln('Uso: dart_source_graph query impact <nombre|id>');
      return 64;
    }
    final graph = _loadGraph(res);
    if (graph == null) return 2;
    final q = CodeGraphQuery(graph);
    final id = _resolveOne(q, res.rest.first);
    if (id == null) return 1;
    final impacted = q.impact(id).toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    if (res['format'] == 'json') {
      stdout.writeln(
        const JsonEncoder.withIndent('  ').convert({
          'target': id,
          'impacted': [for (final n in impacted) n.id],
        }),
      );
    } else {
      stdout.writeln(
        'Impacto de $id — ${impacted.length} nodo(s) dependen de él:',
      );
      for (final n in impacted) {
        stdout.writeln('  ${n.id}${n.file != null ? '  (${n.file})' : ''}');
      }
    }
    return 0;
  }
}

class _NeighborsSubcommand extends Command<int> {
  _NeighborsSubcommand() {
    _addCommonOptions(argParser);
  }

  @override
  String get name => 'neighbors';

  @override
  String get description => 'Aristas directas (entrada + salida) de un nodo.';

  @override
  Future<int> run() async {
    final res = argResults!;
    if (res.rest.isEmpty) {
      stderr.writeln('Uso: dart_source_graph query neighbors <nombre|id>');
      return 64;
    }
    final graph = _loadGraph(res);
    if (graph == null) return 2;
    final q = CodeGraphQuery(graph);
    final id = _resolveOne(q, res.rest.first);
    if (id == null) return 1;
    final n = q.neighbors(id);
    if (res['format'] == 'json') {
      stdout.writeln(
        const JsonEncoder.withIndent('  ').convert({
          'node': id,
          'incoming': [for (final e in n.incoming) e.toJson()],
          'outgoing': [for (final e in n.outgoing) e.toJson()],
        }),
      );
    } else {
      stdout.writeln('Vecinos de $id:');
      stdout.writeln('  entrantes (${n.incoming.length}):');
      for (final e in n.incoming) {
        stdout.writeln(
          '    ${e.source}  --${graphRelationToJson(e.relation)}-->',
        );
      }
      stdout.writeln('  salientes (${n.outgoing.length}):');
      for (final e in n.outgoing) {
        stdout.writeln(
          '    --${graphRelationToJson(e.relation)}-->  ${e.target}',
        );
      }
    }
    return 0;
  }
}

class _GodNodesSubcommand extends Command<int> {
  _GodNodesSubcommand() {
    _addCommonOptions(argParser);
    argParser.addOption(
      'limit',
      defaultsTo: '20',
      help: 'Cuántos hubs mostrar.',
    );
  }

  @override
  String get name => 'god-nodes';

  @override
  String get description =>
      'Nodos internos con más conexiones (hubs arquitectónicos).';

  @override
  Future<int> run() async {
    final res = argResults!;
    final limit = int.tryParse(res['limit'] as String) ?? 20;
    final graph = _loadGraph(res);
    if (graph == null) return 2;
    final top = CodeGraphQuery(graph).godNodes(limit: limit);
    if (res['format'] == 'json') {
      stdout.writeln(
        const JsonEncoder.withIndent('  ').convert([
          for (final r in top)
            {'id': r.node.id, 'degree': r.degree, 'file': r.node.file},
        ]),
      );
    } else {
      stdout.writeln('Top $limit hubs por grado:');
      for (final r in top) {
        stdout.writeln(
          '  ${r.degree.toString().padLeft(4)}  ${r.node.id}${r.node.file != null ? '  (${r.node.file})' : ''}',
        );
      }
    }
    return 0;
  }
}
