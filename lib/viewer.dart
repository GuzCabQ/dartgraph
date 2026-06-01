// lib/viewer.dart
//
// API pública del visor HTML de dart_source_graph.
// Usar para escribir graph.html desde código Dart:
//
//   import 'package:dart_source_graph/viewer.dart';
//   writeHtmlViewer(graph: graph, meta: meta, outputDir: '.');

export 'src/viewer/html_exporter.dart'
    show writeHtmlViewer, writeHtmlViewerFromJson;
