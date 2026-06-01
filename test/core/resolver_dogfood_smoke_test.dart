// test/core/resolver_dogfood_smoke_test.dart
//
// Resuelve el grafo sobre un subárbol real y pub-resuelto de dart_source_graph
// (lib/src) y verifica que la resolución efectivamente hizo algo: existen aristas
// de references y ningún tipo de dart:core se filtró como referencia.
import 'dart:io';

import 'package:dart_source_graph/src/config/source_graph_config.dart';
import 'package:dart_source_graph/src/contracts/code_graph.dart';
import 'package:dart_source_graph/src/core/builder.dart';
import 'package:dart_source_graph/src/core/resolver.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('dogfood: resolver sobre lib/src enriquece el grafo', () async {
    // Raíz del repo dart_source_graph (pub-resuelto)
    final projectRoot = Directory.current.path;
    final srcDir = p.join(projectRoot, 'lib', 'src');
    final files = Directory(srcDir)
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .map((f) => p.normalize(f.absolute.path))
        .toList();
    expect(files, isNotEmpty);

    // Config por defecto — sin YAML externo
    const config = SourceGraphConfig();

    final base = CodeGraphBuilder().build(
      projectRoot: projectRoot,
      filePaths: files,
      config: config,
      packageName: 'dart_source_graph',
    );
    final resolver = CodeGraphResolver();
    final graph = await resolver.resolve(
      base,
      projectRoot: projectRoot,
      filePaths: files,
      config: config,
    );

    // La resolución procesó al menos un archivo
    expect(resolver.resolvedFiles, greaterThan(0));

    // Debe existir al menos una arista de tipo references
    expect(
      graph.edges.where((e) => e.relation == GraphRelation.references).length,
      greaterThan(0),
    );

    // Ninguna arista references apunta a un tipo de dart:core (se excluyen)
    expect(
      graph.edges.any(
        (e) =>
            e.relation == GraphRelation.references &&
            (e.target == GraphNodeId.external('String') ||
                e.target == GraphNodeId.external('int') ||
                e.target == GraphNodeId.external('bool')),
      ),
      isFalse,
    );

    // No deben quedar nodos externos sin aristas incidentes después del GC de resolución
    final referenced = <String>{};
    for (final e in graph.edges) {
      referenced.add(e.source);
      referenced.add(e.target);
    }
    expect(
      graph.nodes.any(
        (n) => n.kind == GraphNodeKind.external && !referenced.contains(n.id),
      ),
      isFalse,
      reason:
          'ningún nodo externo sin aristas debe sobrevivir tras la resolución',
    );
  });
}
