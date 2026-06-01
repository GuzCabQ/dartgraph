import 'dart:io';

import 'package:dart_source_graph/src/contracts/code_graph.dart';
import 'package:dart_source_graph/src/viewer/_template.dart';
import 'package:dart_source_graph/src/viewer/html_exporter.dart';
import 'package:test/test.dart';

void main() {
  group('writeHtmlViewerFromJson', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('dsg_viewer_'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test('reemplaza el placeholder con el JSON', () {
      const json = '{"schema_version":"1.0.0"}';
      final path = writeHtmlViewerFromJson(jsonString: json, outputDir: tmp.path);
      final html = File(path).readAsStringSync();
      expect(html, contains(json));
      expect(html, isNot(contains('/* GRAPH_JSON_PLACEHOLDER */')));
    });

    test('crea outputDir si no existe', () {
      final nested = '${tmp.path}/a/b/c';
      writeHtmlViewerFromJson(jsonString: '{}', outputDir: nested);
      expect(Directory(nested).existsSync(), isTrue);
    });

    test('fileName por defecto es graph.html', () {
      final path = writeHtmlViewerFromJson(jsonString: '{}', outputDir: tmp.path);
      expect(path, endsWith('graph.html'));
      expect(File(path).existsSync(), isTrue);
    });

    test('fileName personalizado se respeta', () {
      final path = writeHtmlViewerFromJson(
        jsonString: '{}',
        outputDir: tmp.path,
        fileName: 'viewer.html',
      );
      expect(path, endsWith('viewer.html'));
    });

    test('retorna ruta absoluta', () {
      final path = writeHtmlViewerFromJson(jsonString: '{}', outputDir: tmp.path);
      expect(path, startsWith('/'));
    });

    test('kGraphHtmlTemplate contiene el placeholder (guard implícito)', () {
      expect(kGraphHtmlTemplate, contains('/* GRAPH_JSON_PLACEHOLDER */'));
    });
  });

  group('writeHtmlViewer', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('dsg_viewer2_'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test('serializa CodeGraph + CodeGraphMeta y escribe HTML', () {
      const graph = CodeGraph(nodes: [], edges: []);
      final meta = CodeGraphMeta(
        schemaVersion: '1.0.0',
        package: 'test_pkg',
        generatedAt: '2026-06-01T00:00:00.000Z',
        inputsFingerprint: 'sha256:abc',
        root: '.',
      );
      final path = writeHtmlViewer(graph: graph, meta: meta, outputDir: tmp.path);
      final html = File(path).readAsStringSync();
      expect(html, contains('"test_pkg"'));
      expect(html, contains('"schema_version"'));
      expect(html, isNot(contains('/* GRAPH_JSON_PLACEHOLDER */')));
    });
  });
}
