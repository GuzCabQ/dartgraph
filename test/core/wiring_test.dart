import 'dart:io';

import 'package:dart_source_graph/src/config/source_graph_config.dart';
import 'package:dart_source_graph/src/contracts/code_graph.dart';
import 'package:dart_source_graph/src/core/builder.dart';
import 'package:dart_source_graph/src/core/wiring.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

Directory _fixture(Map<String, String> files) {
  final root = Directory.systemTemp.createTempSync('aflow_wiring_');
  files.forEach((rel, contents) {
    final f = File(p.join(root.path, rel));
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(contents);
  });
  return root;
}

List<String> _dartFiles(String root) => Directory(p.join(root, 'lib'))
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .map((f) => p.normalize(f.absolute.path))
    .toList();

CodeGraph _wired(String root, SourceGraphConfig config) {
  final files = _dartFiles(root);
  final base = CodeGraphBuilder().build(
    projectRoot: root,
    filePaths: files,
    config: config,
  );
  return addWiringEdges(base, projectRoot: root, config: config);
}

// Config con dos reglas de wiring: services → injector, screens → routes
const _configWiring = SourceGraphConfig(
  wiring: WiringConfig(
    rules: [
      WiringRule(
        name: 'service_registration',
        classPattern: '*Service',
        manifestFile: 'lib/src/app/injector.dart',
        registrationCall: 'Get.put',
      ),
      WiringRule(
        name: 'screen_route',
        classPattern: '*Screen',
        manifestFile: 'lib/src/app/routes.dart',
        registrationCall: 'GoRoute',
      ),
    ],
  ),
);

// Config sin wiring
const _configNoWiring = SourceGraphConfig();

void main() {
  group('addWiringEdges', () {
    test('registered class -> manifest file (method + constructor calls)', () {
      final root = _fixture({
        'pubspec.yaml': 'name: demo\n',
        'lib/src/domain/foo_service.dart': 'class FooService {}\n',
        'lib/src/domain/foo_screen.dart': 'class FooScreen {}\n',
        'lib/src/app/injector.dart':
            "import '../domain/foo_service.dart';\n"
            "void wire() { Get.put(FooService()); }\n",
        'lib/src/app/routes.dart':
            "import '../domain/foo_screen.dart';\n"
            "final routes = [GoRoute(builder: (_, __) => FooScreen())];\n",
      });
      addTearDown(() => root.deleteSync(recursive: true));

      final graph = _wired(root.path, _configWiring);
      final svcId = GraphNodeId.declaration(
        relativePath: 'lib/src/domain/foo_service.dart',
        name: 'FooService',
        kind: GraphNodeKind.class_,
      );
      final screenId = GraphNodeId.declaration(
        relativePath: 'lib/src/domain/foo_screen.dart',
        name: 'FooScreen',
        kind: GraphNodeKind.class_,
      );

      expect(
        graph.edges.any(
          (e) =>
              e.relation == GraphRelation.wiring &&
              e.source == svcId &&
              e.target == GraphNodeId.file('lib/src/app/injector.dart'),
        ),
        isTrue,
      );
      expect(
        graph.edges.any(
          (e) =>
              e.relation == GraphRelation.wiring &&
              e.source == screenId &&
              e.target == GraphNodeId.file('lib/src/app/routes.dart'),
        ),
        isTrue,
      );
    });

    test('no wiring config -> base graph unchanged (no wiring edges)', () {
      final root = _fixture({
        'pubspec.yaml': 'name: demo\n',
        'lib/src/domain/foo_service.dart': 'class FooService {}\n',
      });
      addTearDown(() => root.deleteSync(recursive: true));
      final files = _dartFiles(root.path);
      final base = CodeGraphBuilder().build(
        projectRoot: root.path,
        filePaths: files,
        config: _configNoWiring,
      );
      final graph = addWiringEdges(
        base,
        projectRoot: root.path,
        config: _configNoWiring,
      );
      expect(identical(graph, base), isTrue);
      expect(
        graph.edges.any((e) => e.relation == GraphRelation.wiring),
        isFalse,
      );
    });

    test('missing manifest file -> no crash, no wiring edge', () {
      final root = _fixture({
        'pubspec.yaml': 'name: demo\n',
        'lib/src/domain/foo_service.dart': 'class FooService {}\n',
      });
      addTearDown(() => root.deleteSync(recursive: true));
      final files = _dartFiles(root.path);
      final base = CodeGraphBuilder().build(
        projectRoot: root.path,
        filePaths: files,
        config: _configWiring,
      );
      final graph = addWiringEdges(
        base,
        projectRoot: root.path,
        config: _configWiring,
      );
      expect(identical(graph, base), isTrue);
      expect(
        graph.edges.any((e) => e.relation == GraphRelation.wiring),
        isFalse,
      );
    });

    test('registered name with no matching project class -> no edge', () {
      final root = _fixture({
        'pubspec.yaml': 'name: demo\n',
        'lib/src/app/injector.dart': "void wire() { Get.put(BarService()); }\n",
      });
      addTearDown(() => root.deleteSync(recursive: true));
      final files = _dartFiles(root.path);
      final base = CodeGraphBuilder().build(
        projectRoot: root.path,
        filePaths: files,
        config: _configWiring,
      );
      final graph = addWiringEdges(
        base,
        projectRoot: root.path,
        config: _configWiring,
      );
      expect(identical(graph, base), isTrue);
      expect(
        graph.edges.any((e) => e.relation == GraphRelation.wiring),
        isFalse,
      );
    });

    test('bare method registration call shape works', () {
      const config = SourceGraphConfig(
        wiring: WiringConfig(
          rules: [
            WiringRule(
              name: 'services',
              classPattern: '*Service',
              manifestFile: 'lib/src/injector.dart',
              registrationCall: 'registerSingleton',
            ),
          ],
        ),
      );
      final root = _fixture({
        'pubspec.yaml': 'name: demo\n',
        'lib/src/domain/bar_service.dart': 'class BarService {}\n',
        'lib/src/injector.dart':
            "import 'domain/bar_service.dart';\nvoid wire() { registerSingleton(BarService()); }\n",
      });
      addTearDown(() => root.deleteSync(recursive: true));
      final graph = _wired(root.path, config);
      expect(
        graph.edges.any(
          (e) =>
              e.relation == GraphRelation.wiring &&
              e.source ==
                  GraphNodeId.declaration(
                    relativePath: 'lib/src/domain/bar_service.dart',
                    name: 'BarService',
                    kind: GraphNodeKind.class_,
                  ) &&
              e.target == GraphNodeId.file('lib/src/injector.dart'),
        ),
        isTrue,
      );
    });

    test(
      'a registered name declared in two files yields an edge from each',
      () {
        final root = _fixture({
          'pubspec.yaml': 'name: demo\n',
          'lib/src/domain/a.dart': 'class FooService {}\n',
          'lib/src/domain/b.dart': 'class FooService {}\n',
          'lib/src/app/injector.dart':
              "void wire() { Get.put(FooService()); }\n",
        });
        addTearDown(() => root.deleteSync(recursive: true));
        final graph = _wired(root.path, _configWiring);
        final wiringEdges = graph.edges
            .where(
              (e) =>
                  e.relation == GraphRelation.wiring &&
                  e.target == GraphNodeId.file('lib/src/app/injector.dart'),
            )
            .toList();
        expect(wiringEdges.length, 2);
        expect(
          wiringEdges.map((e) => e.source).toList(),
          containsAll([
            GraphNodeId.declaration(
              relativePath: 'lib/src/domain/a.dart',
              name: 'FooService',
              kind: GraphNodeKind.class_,
            ),
            GraphNodeId.declaration(
              relativePath: 'lib/src/domain/b.dart',
              name: 'FooService',
              kind: GraphNodeKind.class_,
            ),
          ]),
        );
      },
    );

    test('deterministic (byte-identical twice)', () {
      final root = _fixture({
        'pubspec.yaml': 'name: demo\n',
        'lib/src/domain/foo_service.dart': 'class FooService {}\n',
        'lib/src/app/injector.dart':
            "import '../domain/foo_service.dart';\n"
            "void wire() { Get.put(FooService()); }\n",
      });
      addTearDown(() => root.deleteSync(recursive: true));
      const meta = CodeGraphMeta(
        schemaVersion: '1.0.0',
        package: 'demo',
        generatedAt: 't',
        inputsFingerprint: 'sha256:x',
        root: '.',
      );
      expect(
        _wired(root.path, _configWiring).toJson(meta: meta).toString(),
        _wired(root.path, _configWiring).toJson(meta: meta).toString(),
      );
    });
  });
}
