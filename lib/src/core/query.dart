// lib/src/core/query.dart
//
// Consultas read-only sobre un CodeGraph en memoria.
// impact(), neighbors(), godNodes() y utilidades de estructura de directorios.

import '../contracts/code_graph.dart';
import 'state_api.dart';

/// Relaciones donde el source *depende del* target. [CodeGraphQuery.impact]
/// las recorre en reversa. `contains`/`exports`/`part`/`partOf`/`wiring` están
/// excluidas: las primeras son estructurales-internas; `wiring` (clase -> manifiesto)
/// no encaja en la dirección source-depende-de-target.
const Set<GraphRelation> kDependsOnRelations = {
  GraphRelation.imports,
  GraphRelation.references,
  GraphRelation.extends_,
  GraphRelation.implements_,
  GraphRelation.mixesIn,
};

/// Cluster de directorio: su [path] relativo al proyecto, el número de nodos `file`
/// directamente bajo él, y si algún nodo importa `package:flutter/...`.
typedef GraphCluster = ({String path, int fileCount, bool importsFlutter});

/// Arista de dependencia dirigida con conteo entre dos clusters distintos.
typedef GraphClusterEdge = ({String from, String to, int count});

class CodeGraphQuery {
  CodeGraphQuery(this.graph) : _byId = {for (final n in graph.nodes) n.id: n};

  final CodeGraph graph;
  final Map<String, GraphNode> _byId;

  /// Resuelve [nameOrId] a nodos: coincidencia exacta de id (único), o todos los nodos
  /// cuyo `label` sea igual (ordenados por id). Vacío cuando no hay coincidencia.
  List<GraphNode> resolveNodes(String nameOrId) {
    final exact = _byId[nameOrId];
    if (exact != null) return [exact];
    return graph.nodes.where((n) => n.label == nameOrId).toList()
      ..sort((a, b) => a.id.compareTo(b.id));
  }

  /// Todos los nodos que transitivamente dependen de [nodeId] (cierre reverso sobre
  /// [kDependsOnRelations]). Excluye al propio [nodeId].
  /// El orden del conjunto devuelto no está especificado; ordena por [GraphNode.id] para
  /// salida determinista. La adyacencia reversa se reconstruye en cada llamada (O(aristas));
  /// cachea externamente para consultas repetidas.
  Set<GraphNode> impact(String nodeId) {
    final reverse = <String, List<String>>{}; // target -> sources
    for (final e in graph.edges) {
      if (!kDependsOnRelations.contains(e.relation)) continue;
      (reverse[e.target] ??= <String>[]).add(e.source);
    }
    final seen = <String>{};
    final stack = <String>[nodeId];
    while (stack.isNotEmpty) {
      final cur = stack.removeLast();
      for (final src in (reverse[cur] ?? const <String>[])) {
        if (seen.add(src)) stack.add(src);
      }
    }
    seen.remove(nodeId);
    return {
      for (final id in seen)
        if (_byId[id] != null) _byId[id]!,
    };
  }

  /// Aristas directas a 1 salto donde [nodeId] es target (entrantes) o source (salientes).
  ({List<GraphEdge> incoming, List<GraphEdge> outgoing}) neighbors(
    String nodeId,
  ) {
    final incoming = graph.edges.where((e) => e.target == nodeId).toList();
    final outgoing = graph.edges.where((e) => e.source == nodeId).toList();
    return (incoming: incoming, outgoing: outgoing);
  }

  /// Top-[limit] nodos INTERNOS por grado total (source o target), descendente,
  /// empates resueltos por id. Los nodos externos están excluidos — las importaciones
  /// de terceros (e.g. `package:flutter/...`) tienen grado trivialmente alto y no son
  /// los hubs de tu arquitectura.
  /// El grado cuenta cada arista que toca el nodo, incluyendo aristas hacia nodos externos
  /// (e.g. un archivo que importa muchos paquetes es un hub de alto grado legítimo).
  List<({GraphNode node, int degree})> godNodes({int limit = 20}) {
    final degree = <String, int>{};
    for (final e in graph.edges) {
      degree[e.source] = (degree[e.source] ?? 0) + 1;
      degree[e.target] = (degree[e.target] ?? 0) + 1;
    }
    final ranked =
        graph.nodes
            .where((n) => n.kind != GraphNodeKind.external)
            .map((n) => (node: n, degree: degree[n.id] ?? 0))
            .toList()
          ..sort((a, b) {
            final d = b.degree.compareTo(a.degree);
            return d != 0 ? d : a.node.id.compareTo(b.node.id);
          });
    return ranked.take(limit).toList();
  }

  /// Resumen estructural a nivel de directorio, para fundamentar `.alea.yaml`.
  ///
  /// Agrupa nodos por los primeros [depth] segmentos de directorio de su path `file`
  /// (NO por `GraphNode.layer`, que se deriva de config y es circular aquí). Devuelve
  /// clusters con conteos de archivos + flag de importación de flutter, las aristas de
  /// dependencia dirigidas entre clusters distintos, y los clusters que participan en
  /// un ciclo de importación (endpoints de aristas de retroceso; no un SCC completo).
  ({
    List<GraphCluster> clusters,
    List<GraphClusterEdge> clusterEdges,
    List<String> cyclicClusters,
  })
  structure({int depth = 3}) {
    String? clusterOf(GraphNode n) {
      final f = n.file;
      if (f == null) return null;
      final parts = f.split('/');
      if (parts.length <= 1) return null; // archivo en la raíz, sin directorio
      final dirs = parts.sublist(
        0,
        parts.length - 1,
      ); // descarta el nombre de archivo
      final take = dirs.length < depth ? dirs.length : depth;
      return dirs.sublist(0, take).join('/');
    }

    final fileCount = <String, int>{};
    final flutter = <String, bool>{};
    final nodeCluster = <String, String>{};
    for (final n in graph.nodes) {
      final c = clusterOf(n);
      if (c == null) continue;
      nodeCluster[n.id] = c;
      flutter[c] ??= false;
      if (n.kind == GraphNodeKind.file) {
        fileCount[c] = (fileCount[c] ?? 0) + 1;
      }
    }

    for (final e in graph.edges) {
      if (e.relation != GraphRelation.imports) continue;
      if (!e.target.startsWith('external:package:flutter/')) continue;
      final c = nodeCluster[e.source];
      if (c != null) flutter[c] = true;
    }

    final edgeCount = <String, int>{}; // "from to" -> count
    for (final e in graph.edges) {
      if (!kDependsOnRelations.contains(e.relation)) continue;
      final from = nodeCluster[e.source];
      final to = nodeCluster[e.target];
      if (from == null || to == null || from == to) continue;
      final key = '$from $to';
      edgeCount[key] = (edgeCount[key] ?? 0) + 1;
    }

    final clusterPaths = (<String>{...fileCount.keys, ...flutter.keys}).toList()
      ..sort();
    final clusters = <GraphCluster>[
      for (final c in clusterPaths)
        (
          path: c,
          fileCount: fileCount[c] ?? 0,
          importsFlutter: flutter[c] ?? false,
        ),
    ];

    final clusterEdges =
        <GraphClusterEdge>[
          for (final key in edgeCount.keys)
            (
              from: key.split(' ')[0],
              to: key.split(' ')[1],
              count: edgeCount[key]!,
            ),
        ]..sort((a, b) {
          final f = a.from.compareTo(b.from);
          return f != 0 ? f : a.to.compareTo(b.to);
        });

    // Detección de ciclos a nivel de cluster (DFS recursivo; el conteo de clusters
    // es pequeño). Marca los endpoints de cualquier arista de retroceso.
    final adj = <String, List<String>>{};
    for (final e in clusterEdges) {
      (adj[e.from] ??= <String>[]).add(e.to);
    }
    final color = <String, int>{}; // 0 blanco, 1 gris, 2 negro
    final inCycle = <String>{};
    void dfs(String u) {
      color[u] = 1;
      for (final v in (adj[u] ?? const <String>[])) {
        final cv = color[v] ?? 0;
        if (cv == 1) {
          inCycle
            ..add(u)
            ..add(v);
        } else if (cv == 0) {
          dfs(v);
        }
      }
      color[u] = 2;
    }

    for (final c in clusterPaths) {
      if ((color[c] ?? 0) == 0) dfs(c);
    }

    return (
      clusters: clusters,
      clusterEdges: clusterEdges,
      cyclicClusters: inCycle.toList()..sort(),
    );
  }

  /// Conteos agrupados por directorio de nodos FILE sin capa (`layer == null`).
  /// Señal acotada para `/complete-config` ("declara estos bajo una capa, o
  /// agrégalos a graph.exclude") — nunca un volcado de archivos. Agrupa por los
  /// primeros [depth] segmentos de directorio; ordenado por path.
  List<({String path, int fileCount})> unlayered({int depth = 3}) {
    final counts = <String, int>{};
    for (final n in graph.nodes) {
      if (n.kind != GraphNodeKind.file || n.layer != null) continue;
      final f = n.file;
      if (f == null) continue;
      final parts = f.split('/');
      if (parts.length <= 1) continue;
      final dirs = parts.sublist(0, parts.length - 1);
      final take = dirs.length < depth ? dirs.length : depth;
      final cluster = dirs.sublist(0, take).join('/');
      counts[cluster] = (counts[cluster] ?? 0) + 1;
    }
    final paths = counts.keys.toList()..sort();
    return [for (final pth in paths) (path: pth, fileCount: counts[pth]!)];
  }

  /// Para cada nodo con rol etiquetado, el conjunto de llamadas a la API de estado
  /// que hacen sus métodos miembro (e.g. un `riverpod.consumer_widget` que llama
  /// `watch`/`read`). Resumen de flujo de estado acotado y consumible por IA derivado
  /// de `role` + `calls`; las `calls` crudas permanecen en el grafo para traversal.
  /// Ordenado por label de nodo.
  List<({String node, String role, List<String> calls})> stateFlow() {
    final methodsOf = <String, List<String>>{}; // class id -> method ids
    for (final e in graph.edges) {
      if (e.relation != GraphRelation.contains) continue;
      final t = _byId[e.target];
      if (t != null && t.kind == GraphNodeKind.method) {
        (methodsOf[e.source] ??= <String>[]).add(e.target);
      }
    }
    final callsOf = <String, Set<String>>{}; // method id -> state-api names
    for (final e in graph.edges) {
      if (e.relation != GraphRelation.calls) continue;
      final name = _byId[e.target]?.label ?? '';
      if (!kStateApiCalls.contains(name)) continue;
      (callsOf[e.source] ??= <String>{}).add(name);
    }
    final result = <({String node, String role, List<String> calls})>[];
    for (final n in graph.nodes) {
      final role = n.role;
      if (role == null) continue;
      final calls = <String>{};
      for (final m in methodsOf[n.id] ?? const <String>[]) {
        calls.addAll(callsOf[m] ?? const <String>{});
      }
      if (calls.isEmpty) continue;
      result.add((node: n.label, role: role, calls: calls.toList()..sort()));
    }
    result.sort((a, b) => a.node.compareTo(b.node));
    return result;
  }
}
