import 'package:dart_source_graph/src/contracts/code_graph.dart';
import 'package:dart_source_graph/src/core/query.dart';
import 'package:test/test.dart';

GraphNode _file(String rel) => GraphNode(
  id: GraphNodeId.file(rel),
  label: rel.split('/').last,
  kind: GraphNodeKind.file,
  file: rel,
);
GraphNode _cls(String rel, String name) => GraphNode(
  id: GraphNodeId.declaration(
    relativePath: rel,
    name: name,
    kind: GraphNodeKind.class_,
  ),
  label: name,
  kind: GraphNodeKind.class_,
  file: rel,
);
GraphNode _ext(String name) => GraphNode(
  id: GraphNodeId.external(name),
  label: name,
  kind: GraphNodeKind.external,
);
GraphEdge _e(String s, String t, GraphRelation r) => GraphEdge(
  source: s,
  target: t,
  relation: r,
  confidence: GraphConfidence.extracted,
);

void main() {
  final a = _cls('lib/a.dart', 'A');
  final b = _cls('lib/b.dart', 'B');
  final c = _cls('lib/c.dart', 'C');
  final d = _cls('lib/d.dart', 'D');
  final fa = _file('lib/a.dart');
  final x = _ext('Flutter');
  final graph = CodeGraph(
    nodes: [a, b, c, d, fa, x],
    edges: [
      _e(a.id, b.id, GraphRelation.references),
      _e(b.id, c.id, GraphRelation.references),
      _e(d.id, c.id, GraphRelation.contains), // contains NO es depends-on
      _e(a.id, x.id, GraphRelation.imports),
      _e(c.id, x.id, GraphRelation.extends_),
    ],
  );
  final q = CodeGraphQuery(graph);

  group('resolveNodes', () {
    test('exact id', () => expect(q.resolveNodes(a.id).single.id, a.id));
    test('by label', () => expect(q.resolveNodes('B').single.id, b.id));
    test('no match', () => expect(q.resolveNodes('Nope'), isEmpty));
    test('ambiguous label returns all', () {
      final g2 = CodeGraph(
        nodes: [_cls('lib/a.dart', 'Dup'), _cls('lib/b.dart', 'Dup')],
        edges: const [],
      );
      expect(CodeGraphQuery(g2).resolveNodes('Dup').length, 2);
    });
  });

  group('impact', () {
    test(
      'reverse closure over depends-on; excludes target and contains-only',
      () {
        final ids = q.impact(c.id).map((n) => n.id).toSet();
        expect(ids, {a.id, b.id});
        expect(ids.contains(c.id), isFalse);
        expect(ids.contains(d.id), isFalse); // D solo `contains` C
      },
    );
    test('external node dependents', () {
      final ids = q.impact(x.id).map((n) => n.id).toSet();
      expect(ids, {a.id, b.id, c.id});
    });

    test('node with no dependents -> empty', () {
      expect(q.impact(a.id), isEmpty); // nada depende de A
    });

    test('cycle terminates and excludes self', () {
      final pNode = _cls('lib/p.dart', 'P');
      final rNode = _cls('lib/r.dart', 'R');
      final g = CodeGraph(
        nodes: [pNode, rNode],
        edges: [
          _e(pNode.id, rNode.id, GraphRelation.references),
          _e(rNode.id, pNode.id, GraphRelation.references),
        ],
      );
      final ids = CodeGraphQuery(g).impact(pNode.id).map((n) => n.id).toSet();
      expect(ids, {rNode.id}); // R depende de P via el ciclo; P mismo excluido
    });
  });

  group('neighbors', () {
    test('incoming/outgoing split', () {
      final n = q.neighbors(b.id);
      expect(n.outgoing.map((e) => e.target), contains(c.id));
      expect(n.incoming.map((e) => e.source), contains(a.id));
    });
  });

  group('godNodes', () {
    test(
      'ranks internal nodes by degree, excludes external, respects limit',
      () {
        final top = q.godNodes(limit: 2);
        expect(top.length, 2);
        expect(top.any((r) => r.node.kind == GraphNodeKind.external), isFalse);
        expect(top[0].degree >= top[1].degree, isTrue);
        expect(top.first.node.id, c.id); // C tiene el mayor grado interno (3)
      },
    );
  });

  group('structure', () {
    final domainFile = _file('lib/src/domain/entity.dart');
    final entity = _cls('lib/src/domain/entity.dart', 'Entity');
    final dataFile = _file('lib/src/data/repo.dart');
    final repo = _cls('lib/src/data/repo.dart', 'Repo');
    final flutter = _ext('package:flutter/material.dart');
    final g = CodeGraph(
      nodes: [domainFile, entity, dataFile, repo, flutter],
      edges: [
        _e(repo.id, entity.id, GraphRelation.references), // data -> domain
        _e(
          entity.id,
          flutter.id,
          GraphRelation.imports,
        ), // domain importa flutter
      ],
    );
    final s = CodeGraphQuery(g).structure(depth: 3);

    test('clusters by directory with file counts', () {
      final paths = {for (final c in s.clusters) c.path};
      expect(paths, containsAll(['lib/src/domain', 'lib/src/data']));
      expect(
        s.clusters.firstWhere((c) => c.path == 'lib/src/domain').fileCount,
        1,
      );
    });

    test('flags a cluster that imports package:flutter', () {
      expect(
        s.clusters.firstWhere((c) => c.path == 'lib/src/domain').importsFlutter,
        isTrue,
      );
      expect(
        s.clusters.firstWhere((c) => c.path == 'lib/src/data').importsFlutter,
        isFalse,
      );
    });

    test('directed edge between clusters', () {
      expect(
        s.clusterEdges.any(
          (e) =>
              e.from == 'lib/src/data' &&
              e.to == 'lib/src/domain' &&
              e.count == 1,
        ),
        isTrue,
      );
    });

    test('no cycle in an acyclic graph', () {
      expect(s.cyclicClusters, isEmpty);
    });

    test('detects a cluster cycle', () {
      final g2 = CodeGraph(
        nodes: g.nodes,
        edges: [
          ...g.edges,
          _e(entity.id, repo.id, GraphRelation.references), // domain -> data
        ],
      );
      final s2 = CodeGraphQuery(g2).structure(depth: 3);
      expect(
        s2.cyclicClusters,
        containsAll(['lib/src/domain', 'lib/src/data']),
      );
    });
  });

  group('unlayered (slice-2 WS-A)', () {
    test('clusters file nodes whose layer is null, by directory; '
        'layered files excluded', () {
      const graph = CodeGraph(
        nodes: [
          GraphNode(
            id: 'file:lib/src/presentation/a.dart',
            label: 'a.dart',
            kind: GraphNodeKind.file,
            file: 'lib/src/presentation/a.dart',
            layer: 'presentation',
          ),
          GraphNode(
            id: 'file:lib/src/feature/login/c.dart',
            label: 'c.dart',
            kind: GraphNodeKind.file,
            file: 'lib/src/feature/login/c.dart',
          ),
          GraphNode(
            id: 'file:lib/src/feature/pay/d.dart',
            label: 'd.dart',
            kind: GraphNodeKind.file,
            file: 'lib/src/feature/pay/d.dart',
          ),
        ],
        edges: [],
      );
      final result = CodeGraphQuery(graph).unlayered(depth: 3);
      expect(result.map((c) => c.path), contains('lib/src/feature'));
      expect(
        result.firstWhere((c) => c.path == 'lib/src/feature').fileCount,
        2,
      );
      expect(
        result.any((c) => c.path.contains('presentation')),
        isFalse,
        reason: 'los archivos con capa se excluyen de la señal unlayered',
      );
    });
  });

  group('stateFlow (slice-2 WS-D)', () {
    test('links a role-tagged node to the state-API calls it makes; '
        'non-state calls filtered out', () {
      const graph = CodeGraph(
        nodes: [
          GraphNode(
            id: 'class:lib/home.dart#Home',
            label: 'Home',
            kind: GraphNodeKind.class_,
            file: 'lib/home.dart',
            role: 'riverpod.consumer_widget',
          ),
          GraphNode(
            id: 'method:lib/home.dart#Home.build',
            label: 'Home.build',
            kind: GraphNodeKind.method,
            file: 'lib/home.dart',
          ),
          GraphNode(
            id: 'external:watch',
            label: 'watch',
            kind: GraphNodeKind.external,
          ),
          GraphNode(
            id: 'external:Text',
            label: 'Text',
            kind: GraphNodeKind.external,
          ),
        ],
        edges: [
          GraphEdge(
            source: 'class:lib/home.dart#Home',
            target: 'method:lib/home.dart#Home.build',
            relation: GraphRelation.contains,
            confidence: GraphConfidence.extracted,
          ),
          GraphEdge(
            source: 'method:lib/home.dart#Home.build',
            target: 'external:watch',
            relation: GraphRelation.calls,
            confidence: GraphConfidence.ambiguous,
          ),
          GraphEdge(
            source: 'method:lib/home.dart#Home.build',
            target: 'external:Text',
            relation: GraphRelation.calls,
            confidence: GraphConfidence.ambiguous,
          ),
        ],
      );
      final sf = CodeGraphQuery(graph).stateFlow();
      expect(sf, hasLength(1));
      expect(sf.first.node, 'Home');
      expect(sf.first.role, 'riverpod.consumer_widget');
      expect(sf.first.calls, [
        'watch',
      ], reason: 'Text no es una llamada state-API');
    });
  });
}
