// lib/src/contracts/code_graph.dart
//
// Contrato del grafo de código fuente (Code Knowledge Graph).
//
// Tipos de datos puros + (de)serialización. Sin I/O, sin AST, sin crypto.
// Importa solo dart:core y dart:convert — satisface la frontera de pureza.

/// Tipos de nodo. Los guiones bajos al final evitan palabras reservadas de Dart;
/// se descartan en JSON (`class_` -> "class").
enum GraphNodeKind { file, class_, mixin_, enum_, method, function, external }

/// Relaciones entre nodos de grafo. Directivas estructurales + contención +
/// herencia + referencias + cableado se emiten hoy; `calls` es una fase posterior.
enum GraphRelation {
  imports,
  exports,
  part,
  partOf,
  contains,
  extends_,
  implements_,
  mixesIn,
  references, // fase-1b: clase -> un tipo en sus firmas de miembro
  wiring, // clase -> el archivo manifest que la registra (DI/tabla de rutas)
  calls, // fase-2: miembro -> nombre de método invocado (por nombre, ambiguo)
}

/// Procedencia de una arista. La fase-1a emite solo [extracted].
enum GraphConfidence { extracted, inferred, ambiguous }

const Map<GraphNodeKind, String> _nodeKindJson = {
  GraphNodeKind.file: 'file',
  GraphNodeKind.class_: 'class',
  GraphNodeKind.mixin_: 'mixin',
  GraphNodeKind.enum_: 'enum',
  GraphNodeKind.method: 'method',
  GraphNodeKind.function: 'function',
  GraphNodeKind.external: 'external',
};

const Map<GraphRelation, String> _relationJson = {
  GraphRelation.imports: 'imports',
  GraphRelation.exports: 'exports',
  GraphRelation.part: 'part',
  GraphRelation.partOf: 'part_of',
  GraphRelation.contains: 'contains',
  GraphRelation.extends_: 'extends',
  GraphRelation.implements_: 'implements',
  GraphRelation.mixesIn: 'mixes_in',
  GraphRelation.references: 'references',
  GraphRelation.wiring: 'wiring',
  GraphRelation.calls: 'calls',
};

const Map<GraphConfidence, String> _confidenceJson = {
  GraphConfidence.extracted: 'extracted',
  GraphConfidence.inferred: 'inferred',
  GraphConfidence.ambiguous: 'ambiguous',
};

String graphNodeKindToJson(GraphNodeKind k) => _nodeKindJson[k]!;
String graphRelationToJson(GraphRelation r) => _relationJson[r]!;
String graphConfidenceToJson(GraphConfidence c) => _confidenceJson[c]!;

GraphNodeKind graphNodeKindFromJson(String s) =>
    _reverse(_nodeKindJson, s, 'node kind');
GraphRelation graphRelationFromJson(String s) =>
    _reverse(_relationJson, s, 'relation');
GraphConfidence graphConfidenceFromJson(String s) =>
    _reverse(_confidenceJson, s, 'confidence');

T _reverse<T>(Map<T, String> map, String s, String what) {
  for (final entry in map.entries) {
    if (entry.value == s) return entry.key;
  }
  throw FormatException('Unknown $what: "$s"');
}

/// Constructores de id de nodo estables y legibles. El prefijo es el nombre JSON
/// del tipo de nodo.
class GraphNodeId {
  GraphNodeId._();

  static String file(String relativePath) => 'file:$relativePath';

  static String declaration({
    required String relativePath,
    required String name,
    required GraphNodeKind kind,
  }) => '${graphNodeKindToJson(kind)}:$relativePath#$name';

  static String external(String uri) => 'external:$uri';

  /// Id para un método o función de nivel superior. [owner] es el nombre de la
  /// clase/mixin/enum que lo contiene, o '' para una función de nivel superior.
  static String member({
    required String relativePath,
    required String owner,
    required String name,
    required GraphNodeKind kind, // method | function
  }) => owner.isEmpty
      ? '${graphNodeKindToJson(kind)}:$relativePath#$name'
      : '${graphNodeKindToJson(kind)}:$relativePath#$owner.$name';
}

/// Un nodo único en el grafo de conocimiento de código.
///
/// [id] es un identificador estable con prefijo construido con [GraphNodeId].
/// [label] es el nombre legible para humanos (nombre de clase, basename de archivo, etc.).
/// [file] es la ruta relativa al proyecto; null para nodos [GraphNodeKind.external].
/// [line] es la línea de declaración basada en 1; null para nodos de archivo/externos.
/// [layer] es el nombre de la capa arquitectónica configurada; null cuando el nodo cae
/// fuera de cualquier capa declarada.
/// [role] es una etiqueta semántica de rol de gestión de estado (ej. `riverpod.notifier`,
/// `getx.controller`, `flutter.widget`), derivada del supertipo de la declaración;
/// null cuando no aplica ningún rol. (fase-2)
class GraphNode {
  final String id;
  final String label;
  final GraphNodeKind kind;
  final String? file;
  final int? line;
  final String? layer;
  final String? role;

  const GraphNode({
    required this.id,
    required this.label,
    required this.kind,
    this.file,
    this.line,
    this.layer,
    this.role,
  });

  Map<String, Object?> toJson() => {
    'id': id,
    'label': label,
    'kind': graphNodeKindToJson(kind),
    if (file != null) 'file': file,
    if (line != null) 'line': line,
    if (layer != null) 'layer': layer,
    if (role != null) 'role': role,
  };

  factory GraphNode.fromJson(Map<String, Object?> json) => GraphNode(
    id: json['id'] as String,
    label: json['label'] as String,
    kind: graphNodeKindFromJson(json['kind'] as String),
    file: json['file'] as String?,
    line: json['line'] as int?,
    layer: json['layer'] as String?,
    role: json['role'] as String?,
  );
}

/// Una arista dirigida en el grafo de conocimiento de código.
///
/// [source] y [target] son ids de nodo (ver [GraphNodeId]).
/// [relation] describe la relación estructural.
/// [confidence] refleja cómo se derivó la arista.
/// [line] es la línea fuente basada en 1 donde se expresa la relación; se omite
/// cuando no aplica (ej. aristas de contención sintética).
class GraphEdge {
  final String source;
  final String target;
  final GraphRelation relation;
  final GraphConfidence confidence;
  final int? line;

  const GraphEdge({
    required this.source,
    required this.target,
    required this.relation,
    required this.confidence,
    this.line,
  });

  Map<String, Object?> toJson() => {
    'source': source,
    'target': target,
    'relation': graphRelationToJson(relation),
    'confidence': graphConfidenceToJson(confidence),
    if (line != null) 'line': line,
  };

  factory GraphEdge.fromJson(Map<String, Object?> json) => GraphEdge(
    source: json['source'] as String,
    target: json['target'] as String,
    relation: graphRelationFromJson(json['relation'] as String),
    confidence: graphConfidenceFromJson(json['confidence'] as String),
    line: json['line'] as int?,
  );
}

/// Metadatos de tiempo de compilación que envuelven un [CodeGraph] en un documento
/// publicado. `generatedAt` es suministrado por el llamador para que el contrato
/// permanezca libre de reloj (puro).
class CodeGraphMeta {
  final String schemaVersion;
  final String package;
  final String generatedAt; // ISO-8601
  final String inputsFingerprint; // "sha256:…" anclaje de frescura
  final String root;
  final int skippedFiles;
  final bool resolved;
  final int resolvedFiles;
  final int unresolvedFiles;

  const CodeGraphMeta({
    required this.schemaVersion,
    required this.package,
    required this.generatedAt,
    required this.inputsFingerprint,
    required this.root,
    this.skippedFiles = 0,
    this.resolved = false,
    this.resolvedFiles = 0,
    this.unresolvedFiles = 0,
  });

  factory CodeGraphMeta.fromJson(Map<String, Object?> json) {
    final summary =
        (json['summary'] as Map?)?.cast<String, Object?>() ?? const {};
    return CodeGraphMeta(
      schemaVersion: json['schema_version'] as String,
      package: json['package'] as String,
      generatedAt: json['generated_at'] as String,
      inputsFingerprint: json['inputs_fingerprint'] as String,
      root: json['root'] as String,
      skippedFiles: (summary['skipped_files'] as int?) ?? 0,
      resolved: (json['resolved'] as bool?) ?? false,
      resolvedFiles: (summary['resolved_files'] as int?) ?? 0,
      unresolvedFiles: (summary['unresolved_files'] as int?) ?? 0,
    );
  }
}

/// Un grafo de conocimiento de código inmutable: un conjunto de [GraphNode]s más
/// [GraphEdge]s dirigidas (source -> target). Los ids de nodo son únicos. [toJson]
/// emite un documento determinista, compatible con git-diff.
class CodeGraph {
  final List<GraphNode> nodes;
  final List<GraphEdge> edges;

  const CodeGraph({required this.nodes, required this.edges});

  /// Documento determinista, compatible con git-diff. Los nodos se ordenan por id;
  /// las aristas por (source, target, relation, confidence, line).
  Map<String, Object?> toJson({required CodeGraphMeta meta}) {
    final sortedNodes = [...nodes]..sort((a, b) => a.id.compareTo(b.id));
    final sortedEdges = [...edges]
      ..sort((a, b) {
        final s = a.source.compareTo(b.source);
        if (s != 0) return s;
        final t = a.target.compareTo(b.target);
        if (t != 0) return t;
        final r = graphRelationToJson(
          a.relation,
        ).compareTo(graphRelationToJson(b.relation));
        if (r != 0) return r;
        final c = graphConfidenceToJson(
          a.confidence,
        ).compareTo(graphConfidenceToJson(b.confidence));
        if (c != 0) return c;
        return (a.line ?? -1).compareTo(b.line ?? -1);
      });

    final byKind = <String, int>{};
    for (final n in sortedNodes) {
      final k = graphNodeKindToJson(n.kind);
      byKind[k] = (byKind[k] ?? 0) + 1;
    }
    final byRelation = <String, int>{};
    for (final e in sortedEdges) {
      final r = graphRelationToJson(e.relation);
      byRelation[r] = (byRelation[r] ?? 0) + 1;
    }

    return {
      'schema_version': meta.schemaVersion,
      'package': meta.package,
      'generated_at': meta.generatedAt,
      'inputs_fingerprint': meta.inputsFingerprint,
      'root': meta.root,
      'resolved': meta.resolved,
      'summary': {
        'nodes': sortedNodes.length,
        'edges': sortedEdges.length,
        'skipped_files': meta.skippedFiles,
        'resolved_files': meta.resolvedFiles,
        'unresolved_files': meta.unresolvedFiles,
        'by_kind': _sortedMap(byKind),
        'by_relation': _sortedMap(byRelation),
      },
      'nodes': [for (final n in sortedNodes) n.toJson()],
      'edges': [for (final e in sortedEdges) e.toJson()],
    };
  }

  factory CodeGraph.fromJson(Map<String, Object?> json) => CodeGraph(
    nodes: [
      for (final n in (json['nodes'] as List).cast<Map<String, Object?>>())
        GraphNode.fromJson(n),
    ],
    edges: [
      for (final e in (json['edges'] as List).cast<Map<String, Object?>>())
        GraphEdge.fromJson(e),
    ],
  );
}

Map<String, int> _sortedMap(Map<String, int> m) {
  final keys = m.keys.toList()..sort();
  return {for (final k in keys) k: m[k]!};
}
