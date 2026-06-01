import 'dart:io';

import 'package:dart_source_graph/dart_source_graph.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

Directory _fixture(Map<String, String> files) {
  final root = Directory.systemTemp.createTempSync('dsg_analyzer_');
  files.forEach((rel, content) {
    final f = File(p.join(root.path, rel));
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(content);
  });
  return root;
}

void main() {
  group('SourceGraphAnalyzer', () {
    test('produce grafo con nodos y aristas desde código Dart', () async {
      final root = _fixture({
        'pubspec.yaml': 'name: demo\nenvironment:\n  sdk: ^3.0.0\n',
        'lib/a.dart': 'class A {}',
        'lib/b.dart': "import 'a.dart';\nclass B extends A {}",
      });
      final graph = await const SourceGraphAnalyzer().analyze(root.path);
      expect(graph.nodes, isNotEmpty);
      expect(graph.nodes.any((n) => n.label == 'a.dart'), isTrue);
      expect(
        graph.edges.any((e) => e.relation == GraphRelation.imports),
        isTrue,
      );
      root.deleteSync(recursive: true);
    });

    test('config sin layers produce nodos con layer null', () async {
      final root = _fixture({
        'pubspec.yaml': 'name: demo\nenvironment:\n  sdk: ^3.0.0\n',
        'lib/x.dart': 'class X {}',
      });
      final graph = await const SourceGraphAnalyzer().analyze(root.path);
      expect(graph.nodes.every((n) => n.layer == null), isTrue);
      root.deleteSync(recursive: true);
    });

    test('LayerConfig asigna layer a nodos que coinciden', () async {
      final root = _fixture({
        'pubspec.yaml': 'name: demo\nenvironment:\n  sdk: ^3.0.0\n',
        'lib/core/service.dart': 'class MyService {}',
      });
      const config = SourceGraphConfig(
        layers: [
          LayerConfig(name: 'core', paths: ['lib/core/']),
        ],
      );
      final graph = await SourceGraphAnalyzer(
        config: config,
      ).analyze(root.path);
      final fileNode = graph.nodes.firstWhere((n) => n.label == 'service.dart');
      expect(fileNode.layer, 'core');
      root.deleteSync(recursive: true);
    });
  });
}
