// test/core/reporter_test.dart
import 'package:dart_source_graph/src/contracts/code_graph.dart';
import 'package:dart_source_graph/src/core/reporter.dart';
import 'package:test/test.dart';

// ── Helpers ──────────────────────────────────────────────────────────────────

GraphNode _file(String rel, {String? layer}) => GraphNode(
  id: GraphNodeId.file(rel),
  label: rel.split('/').last,
  kind: GraphNodeKind.file,
  file: rel,
  layer: layer,
);

GraphNode _cls(String rel, String name, {String? role, String? layer}) =>
    GraphNode(
      id: GraphNodeId.declaration(
        relativePath: rel,
        name: name,
        kind: GraphNodeKind.class_,
      ),
      label: name,
      kind: GraphNodeKind.class_,
      file: rel,
      role: role,
      layer: layer,
    );

GraphNode _method(String rel, String owner, String name) => GraphNode(
  id: GraphNodeId.member(
    relativePath: rel,
    owner: owner,
    name: name,
    kind: GraphNodeKind.method,
  ),
  label: name,
  kind: GraphNodeKind.method,
  file: rel,
);

GraphEdge _e(
  String s,
  String t,
  GraphRelation r, {
  GraphConfidence confidence = GraphConfidence.extracted,
  int? line,
}) => GraphEdge(
  source: s,
  target: t,
  relation: r,
  confidence: confidence,
  line: line,
);

CodeGraphMeta _meta({String package = 'test_pkg'}) => CodeGraphMeta(
  schemaVersion: '1.0.0',
  package: package,
  generatedAt: '2026-06-01T00:00:00.000Z',
  inputsFingerprint: 'sha256:abc',
  root: '.',
);

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('generateReport', () {
    test('empty graph renders header, summary, and knowledge gaps only', () {
      final graph = CodeGraph(nodes: const [], edges: const []);
      final report = generateReport(graph, _meta());

      expect(report, contains('# Graph Report — test_pkg'));
      expect(report, contains('## Summary'));
      expect(report, contains('## Knowledge Gaps'));
      expect(report, isNot(contains('## God Nodes')));
      expect(report, isNot(contains('## Architecture Clusters')));
      expect(report, isNot(contains('## Import Cycles')));
      expect(report, isNot(contains('## Unlayered Files')));
      expect(report, isNot(contains('## Ambiguous Edges')));
      expect(report, isNot(contains('## State Flow')));
    });

    test('summary contains package name, node count, and edge count', () {
      final a = _cls('lib/a.dart', 'A');
      final b = _cls('lib/b.dart', 'B');
      final graph = CodeGraph(
        nodes: [a, b],
        edges: [_e(a.id, b.id, GraphRelation.imports)],
      );

      final report = generateReport(graph, _meta(package: 'my_package'));
      expect(report, contains('my_package'));
      expect(report, contains('2 nodes'));
      expect(report, contains('1 edges'));
    });

    test('god nodes capped by godLimit', () {
      final nodes = List.generate(5, (i) => _cls('lib/a.dart', 'Class$i'));
      final edges = [
        for (var i = 0; i < nodes.length - 1; i++)
          _e(nodes[i].id, nodes[i + 1].id, GraphRelation.references),
      ];
      final graph = CodeGraph(nodes: nodes, edges: edges);

      final report = generateReport(graph, _meta(), godLimit: 2);

      expect(report, contains('## God Nodes'));
      final section = report.split('## God Nodes').last.split('\n##').first;
      expect(section, contains('1.'));
      expect(section, contains('2.'));
      expect(section, isNot(contains('\n3.')));
    });

    test('import cycle renders Import Cycles section with warning symbol', () {
      final fa = _file('lib/a/a.dart');
      final fb = _file('lib/b/b.dart');
      final graph = CodeGraph(
        nodes: [fa, fb],
        edges: [
          _e(fa.id, fb.id, GraphRelation.imports),
          _e(fb.id, fa.id, GraphRelation.imports),
        ],
      );

      final report = generateReport(graph, _meta());
      expect(report, contains('## Import Cycles'));
      expect(report, contains('⚠'));
    });

    test('role nodes render State Flow section', () {
      final notifier = _cls(
        'lib/src/counter.dart',
        'CounterNotifier',
        role: 'riverpod.notifier',
      );
      final method = _method(
        'lib/src/counter.dart',
        'CounterNotifier',
        'build',
      );
      final readTarget = GraphNode(
        id: GraphNodeId.external('read'),
        label: 'read',
        kind: GraphNodeKind.external,
      );

      final graph = CodeGraph(
        nodes: [notifier, method, readTarget],
        edges: [
          _e(notifier.id, method.id, GraphRelation.contains),
          _e(method.id, readTarget.id, GraphRelation.calls),
        ],
      );

      final report = generateReport(graph, _meta());
      expect(report, contains('## State Flow'));
      expect(report, contains('CounterNotifier'));
      expect(report, contains('riverpod.notifier'));
      expect(report, contains('read'));
    });

    test('ambiguous edges render Ambiguous Edges section', () {
      final a = _cls('lib/src/a.dart', 'A');
      final b = _cls('lib/src/b.dart', 'B');
      final graph = CodeGraph(
        nodes: [a, b],
        edges: [
          _e(
            a.id,
            b.id,
            GraphRelation.references,
            confidence: GraphConfidence.ambiguous,
            line: 42,
          ),
        ],
      );

      final report = generateReport(graph, _meta());
      expect(report, contains('## Ambiguous Edges'));
      expect(report, contains('`A` → `B`'));
    });

    test('no Unlayered Files section when graph has no file nodes', () {
      final a = _cls('lib/src/a.dart', 'A');
      final graph = CodeGraph(nodes: [a], edges: const []);

      final report = generateReport(graph, _meta());
      expect(report, isNot(contains('## Unlayered Files')));
    });

    test('Unlayered Files section present when a file node has no layer', () {
      final withLayer = _file('lib/src/core/a.dart', layer: 'core');
      final withoutLayer = _file('lib/src/utils/b.dart');
      final graph = CodeGraph(
        nodes: [withLayer, withoutLayer],
        edges: const [],
      );

      final report = generateReport(graph, _meta());
      expect(report, contains('## Unlayered Files'));
      expect(report, contains('lib/src/utils'));
    });

    test('knowledge gaps lists isolated node labels', () {
      final a = _cls('lib/src/a.dart', 'OrphanClass');
      final graph = CodeGraph(nodes: [a], edges: const []);

      final report = generateReport(graph, _meta());
      expect(report, contains('## Knowledge Gaps'));
      expect(report, contains('OrphanClass'));
      expect(report, contains('degree 0'));
    });

    test(
      'knowledge gaps shows no-gaps message when all internal nodes connected',
      () {
        final a = _cls('lib/a.dart', 'A');
        final b = _cls('lib/b.dart', 'B');
        final graph = CodeGraph(
          nodes: [a, b],
          edges: [
            _e(a.id, b.id, GraphRelation.references),
            _e(b.id, a.id, GraphRelation.references),
          ],
        );

        final report = generateReport(graph, _meta());
        expect(report, contains('## Knowledge Gaps'));
        expect(report, contains('No isolated or weakly connected'));
      },
    );

    test('external nodes are excluded from knowledge gaps', () {
      final ext = GraphNode(
        id: GraphNodeId.external('package:flutter/material.dart'),
        label: 'material.dart',
        kind: GraphNodeKind.external,
      );
      final graph = CodeGraph(nodes: [ext], edges: const []);

      final report = generateReport(graph, _meta());
      expect(report, isNot(contains('material.dart')));
    });
  });
}
