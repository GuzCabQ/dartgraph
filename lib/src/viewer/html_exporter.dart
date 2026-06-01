// lib/src/viewer/html_exporter.dart
//
// API de escritura del visor HTML autocontenido.
// El template HTML está embebido como const String en _template.dart.
// No importar directamente — usar lib/viewer.dart.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../contracts/code_graph.dart';
import '_template.dart';

// El placeholder real está en la línea de contenido del <script id="graph-payload">.
// Usamos el contexto completo para no colisionar con las menciones del placeholder
// que aparecen en los comentarios HTML de documentación del propio template.
const String _placeholder = '/* GRAPH_JSON_PLACEHOLDER */';

/// Serializa [graph] + [meta] y escribe el visor HTML en [outputDir]/[fileName].
/// Devuelve la ruta absoluta del archivo escrito.
String writeHtmlViewer({
  required CodeGraph graph,
  required CodeGraphMeta meta,
  required String outputDir,
  String fileName = 'graph.html',
}) {
  final jsonString = const JsonEncoder.withIndent(
    '  ',
  ).convert(graph.toJson(meta: meta));
  return writeHtmlViewerFromJson(
    jsonString: jsonString,
    outputDir: outputDir,
    fileName: fileName,
  );
}

/// Escribe el visor HTML desde un JSON ya serializado.
/// Evita re-parsear + re-serializar cuando el JSON ya existe en disco.
/// Devuelve la ruta absoluta del archivo escrito.
/// Lanza [StateError] si el placeholder no está en el template (template corrupto).
String writeHtmlViewerFromJson({
  required String jsonString,
  required String outputDir,
  String fileName = 'graph.html',
}) {
  if (!kGraphHtmlTemplate.contains(_placeholder)) {
    throw StateError(
      'Template corrupto: el placeholder "$_placeholder" no se encontró.',
    );
  }
  // El template menciona el placeholder también en comentarios HTML de documentación,
  // además de la ocurrencia real dentro del <script id="graph-payload">.
  // replaceAll garantiza que ninguna ocurrencia del marcador quede en el output,
  // lo que es seguro porque el JSON no puede contener el string del placeholder.
  final html = kGraphHtmlTemplate.replaceAll(_placeholder, jsonString);
  final dir = Directory(outputDir);
  if (!dir.existsSync()) dir.createSync(recursive: true);
  final outFile = File(p.join(outputDir, fileName));
  outFile.writeAsStringSync(html);
  return outFile.absolute.path;
}
