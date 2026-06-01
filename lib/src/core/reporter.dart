// lib/src/core/reporter.dart
//
// Genera el Markdown de GRAPH_REPORT.md desde un CodeGraph en memoria.
// Sin I/O, sin efectos secundarios — recibe CodeGraph + CodeGraphMeta y
// devuelve String. Usa CodeGraphQuery internamente.

import '../contracts/code_graph.dart';
import 'query.dart';

/// Genera el Markdown completo de GRAPH_REPORT.md.
/// [godLimit] controla el top-N de god nodes mostrados.
String generateReport(
  CodeGraph graph,
  CodeGraphMeta meta, {
  int godLimit = 20,
}) {
  final q = CodeGraphQuery(graph);
  final s = q.structure();
  final buf = StringBuffer();

  final today = DateTime.now().toUtc().toIso8601String().substring(0, 10);
  buf.writeln('# Graph Report — ${meta.package}  ($today)');
  buf.writeln();

  _writeSummary(buf, graph, meta, s.clusters.length);
  _writeGodNodes(buf, q, limit: godLimit);
  _writeClusters(buf, s);
  _writeCycles(buf, s);
  _writeUnlayered(buf, q);
  _writeAmbiguousEdges(buf, graph);
  _writeKnowledgeGaps(buf, graph);
  _writeStateFlow(buf, q);

  return buf.toString().trimRight();
}

// ── Section writers ───────────────────────────────────────────────────────────

void _writeSummary(
  StringBuffer buf,
  CodeGraph graph,
  CodeGraphMeta meta,
  int clusterCount,
) {
  buf.writeln('## Summary');
  buf.writeln();
  buf.writeln(
    '- ${graph.nodes.length} nodes · ${graph.edges.length} edges · $clusterCount clusters',
  );

  final byKind = <String, int>{};
  for (final n in graph.nodes) {
    final k = graphNodeKindToJson(n.kind);
    byKind[k] = (byKind[k] ?? 0) + 1;
  }
  if (byKind.isNotEmpty) {
    final parts = (byKind.keys.toList()..sort())
        .map((k) => '$k(${byKind[k]})')
        .join(', ');
    buf.writeln('- Nodes: $parts');
  }

  final byRel = <String, int>{};
  for (final e in graph.edges) {
    final r = graphRelationToJson(e.relation);
    byRel[r] = (byRel[r] ?? 0) + 1;
  }
  if (byRel.isNotEmpty) {
    final parts = (byRel.keys.toList()..sort())
        .map((k) => '$k(${byRel[k]})')
        .join(', ');
    buf.writeln('- Edges: $parts');
  }

  buf.writeln('- Skipped files: ${meta.skippedFiles}');
  if (meta.resolved) {
    buf.writeln(
      '- Resolved: ${meta.resolvedFiles} files · ${meta.unresolvedFiles} unresolved',
    );
  }
  buf.writeln();
}

void _writeGodNodes(StringBuffer buf, CodeGraphQuery q, {required int limit}) {
  final gods = q.godNodes(limit: limit);
  if (gods.isEmpty) return;

  buf.writeln('## God Nodes');
  buf.writeln();
  for (var i = 0; i < gods.length; i++) {
    final g = gods[i];
    final kind = graphNodeKindToJson(g.node.kind);
    final fileStr = g.node.file != null ? ' · ${g.node.file}' : '';
    final lineStr = g.node.line != null ? ':${g.node.line}' : '';
    buf.writeln(
      '${i + 1}. `${g.node.label}`  — ${g.degree} edges  ($kind$fileStr$lineStr)',
    );
  }
  buf.writeln();
}

void _writeClusters(
  StringBuffer buf,
  ({
    List<GraphCluster> clusters,
    List<GraphClusterEdge> clusterEdges,
    List<String> cyclicClusters,
  })
  s,
) {
  if (s.clusters.isEmpty) return;

  buf.writeln('## Architecture Clusters');
  buf.writeln();
  buf.writeln('| Cluster | Files | Flutter | Depends on |');
  buf.writeln('| --- | --- | --- | --- |');

  for (final c in s.clusters) {
    final cyclic = s.cyclicClusters.contains(c.path) ? ' ⚠' : '';
    final flutter = c.importsFlutter ? 'yes' : 'no';
    final outgoing = s.clusterEdges
        .where((e) => e.from == c.path)
        .map((e) => '${e.to} (${e.count})')
        .join(', ');
    final dependsOn = outgoing.isEmpty ? '—' : outgoing;
    buf.writeln(
      '| `${c.path}`$cyclic | ${c.fileCount} | $flutter | $dependsOn |',
    );
  }
  buf.writeln();
}

void _writeCycles(
  StringBuffer buf,
  ({
    List<GraphCluster> clusters,
    List<GraphClusterEdge> clusterEdges,
    List<String> cyclicClusters,
  })
  s,
) {
  if (s.cyclicClusters.isEmpty) return;

  buf.writeln('## Import Cycles');
  buf.writeln();
  for (final c in s.cyclicClusters) {
    buf.writeln('- ⚠ `$c`');
  }
  buf.writeln();
}

void _writeUnlayered(StringBuffer buf, CodeGraphQuery q) {
  final unlayered = q.unlayered();
  if (unlayered.isEmpty) return;

  buf.writeln('## Unlayered Files');
  buf.writeln();
  for (final u in unlayered) {
    buf.writeln('- `${u.path}` (${u.fileCount} files without a layer)');
  }
  buf.writeln();
}

void _writeAmbiguousEdges(StringBuffer buf, CodeGraph graph) {
  final ambiguous = graph.edges
      .where((e) => e.confidence == GraphConfidence.ambiguous)
      .toList();
  if (ambiguous.isEmpty) return;

  final nodeById = {for (final n in graph.nodes) n.id: n};
  buf.writeln('## Ambiguous Edges');
  buf.writeln();
  for (final e in ambiguous) {
    final srcLabel = nodeById[e.source]?.label ?? e.source;
    final tgtLabel = nodeById[e.target]?.label ?? e.target;
    final srcFile = nodeById[e.source]?.file ?? '';
    final lineStr = e.line != null ? ':${e.line}' : '';
    buf.writeln('- `$srcLabel` → `$tgtLabel`  [$srcFile$lineStr]');
  }
  buf.writeln();
}

void _writeKnowledgeGaps(StringBuffer buf, CodeGraph graph) {
  final degree = <String, int>{};
  for (final e in graph.edges) {
    degree[e.source] = (degree[e.source] ?? 0) + 1;
    degree[e.target] = (degree[e.target] ?? 0) + 1;
  }

  final internal = graph.nodes
      .where((n) => n.kind != GraphNodeKind.external)
      .toList();
  final isolated = internal.where((n) => (degree[n.id] ?? 0) == 0).toList();
  final weakly = internal.where((n) => (degree[n.id] ?? 0) == 1).toList();

  buf.writeln('## Knowledge Gaps');
  buf.writeln();

  if (isolated.isEmpty && weakly.isEmpty) {
    buf.writeln('- No isolated or weakly connected nodes detected.');
  } else {
    if (isolated.isNotEmpty) {
      final labels = isolated.take(10).map((n) => '`${n.label}`').join(', ');
      final extra = isolated.length > 10
          ? ' (+${isolated.length - 10} more)'
          : '';
      buf.writeln('- **Isolated nodes (degree 0):** $labels$extra');
    }
    if (weakly.isNotEmpty) {
      final labels = weakly.take(10).map((n) => '`${n.label}`').join(', ');
      final extra = weakly.length > 10 ? ' (+${weakly.length - 10} more)' : '';
      buf.writeln('- **Weakly connected nodes (degree 1):** $labels$extra');
    }
  }
  buf.writeln();
}

void _writeStateFlow(StringBuffer buf, CodeGraphQuery q) {
  final flows = q.stateFlow();
  if (flows.isEmpty) return;

  buf.writeln('## State Flow');
  buf.writeln();
  buf.writeln('| Node | Role | State API Calls |');
  buf.writeln('| --- | --- | --- |');
  for (final f in flows) {
    buf.writeln('| `${f.node}` | ${f.role} | ${f.calls.join(', ')} |');
  }
  buf.writeln();
}
