// test/core/dogfood_smoke_test.dart
//
// Construye el grafo sobre un subárbol real de dart_source_graph mismo (lib/src)
// para validar el esquema en código real. Aserciones estructurales holgadas —
// sin conteos exactos frágiles.
import 'dart:io';

import 'package:dart_source_graph/src/config/source_graph_config.dart';
import 'package:dart_source_graph/src/contracts/code_graph.dart';
import 'package:dart_source_graph/src/core/builder.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('dogfood: construye un grafo sano sobre lib/src sin fallar', () {
    // Raíz del repo dart_source_graph (el test se corre desde ahí)
    final projectRoot = Directory.current.path;
    final srcDir = p.join(projectRoot, 'lib', 'src');
    final files = Directory(srcDir)
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .map((f) => p.normalize(f.absolute.path))
        .toList();

    expect(files, isNotEmpty, reason: 'lib/src debe tener archivos .dart');

    // Config por defecto — sin YAML externo, sin DI específico del proyecto
    const config = SourceGraphConfig();

    final builder = CodeGraphBuilder();
    final graph = builder.build(
      projectRoot: projectRoot,
      filePaths: files,
      config: config,
      packageName: 'dart_source_graph',
    );

    // El grafo debe tener nodos de archivo suficientes
    expect(
      graph.nodes.where((n) => n.kind == GraphNodeKind.file).length,
      greaterThan(3),
    );
    // El grafo debe tener nodos de clase suficientes
    expect(
      graph.nodes.where((n) => n.kind == GraphNodeKind.class_).length,
      greaterThan(3),
    );
    // Debe haber aristas de imports
    expect(
      graph.edges.where((e) => e.relation == GraphRelation.imports).length,
      greaterThan(0),
    );
    // Debe haber aristas de contains (archivos que contienen declaraciones)
    expect(
      graph.edges.where((e) => e.relation == GraphRelation.contains).length,
      greaterThan(0),
    );
    // Ningún archivo debe haber sido omitido
    expect(builder.skippedFiles, 0);

    // El fingerprint debe comenzar con el prefijo estándar sha256
    final fp = CodeGraphBuilder.inputsFingerprint(projectRoot, files);
    expect(fp, startsWith('sha256:'));
  });
}
