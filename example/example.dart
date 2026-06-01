// example/example.dart
//
// Uso básico de dart_source_graph.
// Analiza el proyecto actual y genera un grafo de código fuente.

import 'package:dart_source_graph/dart_source_graph.dart';
import 'package:dart_source_graph/viewer.dart';

Future<void> main() async {
  // Análisis mínimo — sin config, cero dependencias externas.
  final graph = await SourceGraphAnalyzer().analyze('.');
  print('Nodes: ${graph.nodes.length}, Edges: ${graph.edges.length}');

  // Con capas arquitectónicas y resolución semántica.
  final graphWithLayers = await SourceGraphAnalyzer(
    config: SourceGraphConfig(
      layers: [
        LayerConfig(name: 'core', paths: ['lib/src/core/']),
        LayerConfig(name: 'adapters', paths: ['lib/src/adapters/']),
      ],
    ),
  ).analyze('.', resolve: true);

  // Generar reporte Markdown.
  final meta = CodeGraphMeta(
    schemaVersion: '1.0.0',
    package: 'my_app',
    generatedAt: DateTime.now().toUtc().toIso8601String(),
    inputsFingerprint: 'sha256:example',
    root: '.',
  );
  final report = generateReport(graphWithLayers, meta);
  print(report.substring(0, 200));

  // Generar visor HTML autocontenido.
  final htmlPath = writeHtmlViewer(
    graph: graphWithLayers,
    meta: meta,
    outputDir: '.',
  );
  print('Viewer: $htmlPath');
}
