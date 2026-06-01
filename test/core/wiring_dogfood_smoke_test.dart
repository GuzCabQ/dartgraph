// test/core/wiring_dogfood_smoke_test.dart
//
// dart_source_graph no declara arquitectura DI propia, por lo que addWiringEdges
// debe ser un no-op sobre su propio árbol (verifica el camino no-op en código real).
import 'dart:io';

import 'package:dart_source_graph/src/config/source_graph_config.dart';
import 'package:dart_source_graph/src/contracts/code_graph.dart';
import 'package:dart_source_graph/src/core/builder.dart';
import 'package:dart_source_graph/src/core/wiring.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test(
    'dogfood: addWiringEdges es no-op para dart_source_graph (sin config de wiring)',
    () {
      final projectRoot = Directory.current.path;
      // Config por defecto: wiring == null → no-op garantizado
      const config = SourceGraphConfig();

      final files = Directory(p.join(projectRoot, 'lib', 'src'))
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .map((f) => p.normalize(f.absolute.path))
          .toList();

      final base = CodeGraphBuilder().build(
        projectRoot: projectRoot,
        filePaths: files,
        config: config,
        packageName: 'dart_source_graph',
      );

      // addWiringEdges debe devolver la misma instancia sin agregar aristas de wiring
      final wired = addWiringEdges(
        base,
        projectRoot: projectRoot,
        config: config,
      );

      // No debe haber aristas de tipo wiring
      expect(
        wired.edges.any((e) => e.relation == GraphRelation.wiring),
        isFalse,
      );
      // El no-op devuelve la misma instancia exacta
      expect(identical(wired, base), isTrue);
    },
  );
}
