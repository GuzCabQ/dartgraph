// lib/src/core/resolver.dart
//
// Resolver del grafo (slice-1b): enriquece el grafo estructural usando
// el modelo de elementos del analyzer. Retarget de aristas de herencia,
// agrega aristas `references`. Degradación graceful para archivos no resolubles.
//
// Nota de API (analyzer 12.1.0 — nuevo modelo de fragmentos):
//   InterfaceElement NO tiene `.source` directo; usa
//   `el.firstFragment.libraryFragment.source.fullName` en su lugar.
//   LibraryElement.classes/.enums/.mixins devuelve elementos de TODOS los fragmentos
//   (incluyendo part files), por lo que filtramos por fuente del fragmento para
//   restringir al archivo siendo procesado.

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:path/path.dart' as p;

import '../config/source_graph_config.dart';
import '../contracts/code_graph.dart';
import 'state_api.dart';

class CodeGraphResolver {
  int _resolved = 0;
  int _unresolved = 0;
  int get resolvedFiles => _resolved;
  int get unresolvedFiles => _unresolved;

  Future<CodeGraph> resolve(
    CodeGraph base, {
    required String projectRoot,
    required List<String> filePaths,
    required SourceGraphConfig config,
  }) async {
    // `config` está reservado para filtrado futuro por capa; no se usa en slice-1b.
    _resolved = 0;
    _unresolved = 0;

    // Construye estructuras de búsqueda desde el grafo parseado.
    // declIndex: "relPath#name" -> node id (para declaraciones internas)
    final declIndex = <String, String>{};
    final lineOfNode = <String, int?>{};
    final nodes = <String, GraphNode>{};
    for (final n in base.nodes) {
      nodes[n.id] = n;
      if (n.kind == GraphNodeKind.file || n.kind == GraphNodeKind.external) {
        continue;
      }
      if (n.file != null) {
        declIndex['${n.file}#${n.label}'] = n.id;
        lineOfNode[n.id] = n.line;
      }
    }

    final resolvedRels = <String>{};
    final addedInheritance = <GraphEdge>[];
    final addedReferences = <GraphEdge>[];

    final normalized = filePaths.map(p.normalize).toList();
    if (normalized.isEmpty) return base;

    final collection = buildCollection(normalized);

    for (final path in normalized) {
      final rel = _rel(path, projectRoot);
      try {
        final session = collection.contextFor(path).currentSession;
        final result = await session.getResolvedUnit(path);
        if (result is! ResolvedUnitResult) {
          _unresolved++;
          continue;
        }
        final fileEdges = <GraphEdge>[];
        final fileRefs = <GraphEdge>[];
        final refsSeen = <String>{};
        final lib = result.libraryElement;

        // En el nuevo modelo de fragmentos, LibraryElement.classes/.mixins/.enums
        // devuelve elementos de TODOS los fragmentos (incluyendo part files).
        // Filtramos solo los elementos cuya fuente del primer fragmento coincide con este archivo.
        final here = <InterfaceElement>[
          ...lib.classes.where((e) => _relOfElement(e, projectRoot) == rel),
          ...lib.mixins.where((e) => _relOfElement(e, projectRoot) == rel),
          ...lib.enums.where((e) => _relOfElement(e, projectRoot) == rel),
        ];

        for (final el in here) {
          final name = el.name ?? '';
          if (name.isEmpty) continue; // omite elementos sintéticos/anónimos
          final fromId = declIndex['$rel#$name'];
          if (fromId == null) continue;
          final line = lineOfNode[fromId];

          // El supertipo solo es relevante para clases; las restricciones `on`
          // de mixin y el supertipo implícito `Enum` de los enums no se emiten.
          if (el is ClassElement) {
            final st = el.supertype;
            if (st != null && !_isDartCoreObject(st)) {
              _addInheritance(
                fileEdges,
                nodes,
                declIndex,
                projectRoot,
                fromId,
                st,
                GraphRelation.extends_,
                line,
              );
            }
          }
          for (final t in el.mixins) {
            _addInheritance(
              fileEdges,
              nodes,
              declIndex,
              projectRoot,
              fromId,
              t,
              GraphRelation.mixesIn,
              line,
            );
          }
          for (final t in el.interfaces) {
            _addInheritance(
              fileEdges,
              nodes,
              declIndex,
              projectRoot,
              fromId,
              t,
              GraphRelation.implements_,
              line,
            );
          }
          _addReferences(
            fileRefs,
            refsSeen,
            nodes,
            declIndex,
            projectRoot,
            fromId,
            el,
            line,
          );
        }
        // Resolución de calls/instantiates sobre el AST resuelto.
        // Snapshot pre-walk: los nodos external que el visitante agrega durante
        // el recorrido (allowlist) quedan intencionalmente fuera de este set,
        // que solo sirve para verificar pertenencia de declaraciones internas.
        final nodeIds = nodes.keys.toSet();
        result.unit.accept(_CallResolver(
          rel: rel,
          projectRoot: projectRoot,
          nodeIds: nodeIds,
          nodes: nodes,
          out: fileRefs, // se vuelca en addedReferences -> finalEdges -> pasa por el GC de externos
          lineOf: (offset) => result.lineInfo.getLocation(offset).lineNumber,
          relOfAny: _relOfAnyElement,
          ownerOf: _ownerOf,
          relOfInterface: _relOfElement,
        ));
        addedInheritance.addAll(fileEdges);
        addedReferences.addAll(fileRefs);
        resolvedRels.add(rel);
        _resolved++;
      } catch (_) {
        _unresolved++;
      }
    }

    // Descarta las aristas de herencia por-nombre antiguas para los archivos que
    // se resolvieron exitosamente; conserva todo lo demás (aristas no-herencia, y
    // aristas de archivos no resueltos).
    bool isInheritance(GraphRelation r) =>
        r == GraphRelation.extends_ ||
        r == GraphRelation.implements_ ||
        r == GraphRelation.mixesIn;

    final kept = <GraphEdge>[];
    for (final e in base.edges) {
      if (isInheritance(e.relation)) {
        final srcFile = nodes[e.source]?.file;
        if (srcFile != null && resolvedRels.contains(srcFile)) continue;
      }
      kept.add(e);
    }

    final finalEdges = [...kept, ...addedInheritance, ...addedReferences];

    // GC: descarta nodos externos que quedaron sin aristas después del retargeting
    // de herencia. Los nodos internos (file/class/mixin/enum) siempre se conservan —
    // una declaración interna aislada es significativa; un externo sin aristas es ruido puro.
    final referenced = <String>{};
    for (final e in finalEdges) {
      referenced.add(e.source);
      referenced.add(e.target);
    }
    final keptNodes = [
      for (final n in nodes.values)
        if (n.kind != GraphNodeKind.external || referenced.contains(n.id)) n,
    ];

    return CodeGraph(nodes: keptNodes, edges: finalEdges);
  }

  /// Construye el [AnalysisContextCollection] para los paths normalizados dados.
  /// Sobreescribible en tests para inyectar fallos en paths específicos.
  AnalysisContextCollection buildCollection(List<String> normalizedPaths) =>
      AnalysisContextCollection(includedPaths: normalizedPaths);

  void _addInheritance(
    List<GraphEdge> out,
    Map<String, GraphNode> nodes,
    Map<String, String> declIndex,
    String projectRoot,
    String fromId,
    InterfaceType type,
    GraphRelation relation,
    int? line,
  ) {
    final targetId = _targetIdFor(type.element, nodes, declIndex, projectRoot);
    out.add(
      GraphEdge(
        source: fromId,
        target: targetId,
        relation: relation,
        confidence: GraphConfidence.extracted,
        line: line,
      ),
    );
  }

  /// El id externo es el nombre bare del elemento (e.g. 'StatelessWidget'), a diferencia
  /// de las aristas de import que usan la URI.
  ///
  /// Devuelve el id del nodo de declaración interna cuando el elemento fue escaneado,
  /// de lo contrario crea/devuelve un nodo externo-por-nombre.
  String _targetIdFor(
    InterfaceElement element,
    Map<String, GraphNode> nodes,
    Map<String, String> declIndex,
    String projectRoot,
  ) {
    final name = element.name ?? '';
    final rel = _relOfElement(element, projectRoot);
    final internal = declIndex['$rel#$name'];
    if (internal != null) return internal;

    // No está en nuestro conjunto de escaneo — emite un nodo externo.
    final extId = GraphNodeId.external(name);
    nodes.putIfAbsent(
      extId,
      () => GraphNode(id: extId, label: name, kind: GraphNodeKind.external),
    );
    return extId;
  }

  /// Devuelve el path relativo al proyecto para un [InterfaceElement] usando el
  /// accessor del modelo de fragmentos. Consistente con el filtro `here` por archivo
  /// y los lookups de `_targetIdFor`.
  String _relOfElement(InterfaceElement element, String projectRoot) {
    final srcFull = element.firstFragment.libraryFragment.source.fullName;
    return _rel(srcFull, projectRoot);
  }

  /// Ruta relativa al proyecto para cualquier [Element] con fragmentos.
  /// Devuelve null si el elemento no tiene fragmento de librería (sintético).
  String? _relOfAnyElement(Element element, String projectRoot) {
    final libFrag = element.firstFragment.libraryFragment;
    if (libFrag == null) return null;
    return _rel(libFrag.source.fullName, projectRoot);
  }

  /// Nombre del owner para construir el id de miembro: el nombre del
  /// InterfaceElement contenedor, o '' si el elemento es top-level.
  String _ownerOf(Element element) {
    final enc = element.enclosingElement;
    if (enc is InterfaceElement) return enc.name ?? '';
    return '';
  }

  bool _isDartCoreObject(InterfaceType t) =>
      t.element.name == 'Object' && t.element.library.isInSdk;

  String _rel(String absolute, String projectRoot) {
    if (!p.isAbsolute(absolute)) return absolute.replaceAll(r'\', '/');
    try {
      return p.relative(absolute, from: projectRoot).replaceAll(r'\', '/');
    } on ArgumentError {
      return absolute.replaceAll(r'\', '/');
    }
  }

  void _addReferences(
    List<GraphEdge> out,
    Set<String> seen,
    Map<String, GraphNode> nodes,
    Map<String, String> declIndex,
    String projectRoot,
    String fromId,
    InterfaceElement el,
    int? line,
  ) {
    final types = <DartType>[];
    // Los elementos Enum exponen fields sintéticos (`index`: int, `values`: List<E>).
    // `int`/`List` son dart: (filtrados por isInSdk); el `E` interno de `values`
    // resuelve al propio enum y es descartado por la guardia de auto-referencia
    // abajo. Ambas guardias son esenciales — no eliminar.
    for (final f in el.fields) {
      types.add(f.type);
    }
    for (final m in el.methods) {
      types.add(m.returnType);
      for (final param in m.formalParameters) {
        types.add(param.type);
      }
    }
    for (final c in el.constructors) {
      for (final param in c.formalParameters) {
        types.add(param.type);
      }
    }

    final targets = <InterfaceElement>{};
    for (final t in types) {
      _collectInterfaceElements(t, targets);
    }

    for (final element in targets) {
      // InterfaceElement.library es non-nullable; isInSdk filtra tipos dart:.
      if (element.library.isInSdk) continue; // omite tipos dart: (ruido)
      final name = element.name ?? '';
      if (name.isEmpty) continue; // guardia contra elementos sin nombre
      final targetId = _targetIdFor(element, nodes, declIndex, projectRoot);
      if (targetId == fromId) continue; // sin auto-referencia
      final key = '$fromId|$targetId';
      if (!seen.add(key)) continue;
      out.add(
        GraphEdge(
          source: fromId,
          target: targetId,
          relation: GraphRelation.references,
          confidence: GraphConfidence.extracted,
          line: line,
        ),
      );
    }
  }

  /// Recolecta el [InterfaceElement] cabeza de [type] y, recursivamente, de sus
  /// argumentos de tipo genérico (`Future<User>` → User; `Map<String,Entity>` → Entity).
  /// Los parámetros de tipo (T) y los tipos no-interface se omiten.
  void _collectInterfaceElements(DartType type, Set<InterfaceElement> out) {
    if (type is InterfaceType) {
      out.add(type.element);
      for (final arg in type.typeArguments) {
        _collectInterfaceElements(arg, out);
      }
    }
  }
}

/// Recorre el AST resuelto de un archivo y emite aristas `calls`/`instantiates`
/// resueltas semánticamente. Atribuye cada invocación al método/función miembro
/// que la contiene. Solo emite cuando el `sourceId` existe en [nodeIds].
class _CallResolver extends RecursiveAstVisitor<void> {
  _CallResolver({
    required this.rel,
    required this.projectRoot,
    required this.nodeIds,
    required this.nodes,
    required this.out,
    required this.lineOf,
    required this.relOfAny,
    required this.ownerOf,
    required this.relOfInterface,
  });

  final String rel;
  final String projectRoot;
  final Set<String> nodeIds;
  final Map<String, GraphNode> nodes;
  final List<GraphEdge> out;
  final int Function(int offset) lineOf;
  final String? Function(Element, String) relOfAny;
  final String Function(Element) ownerOf;
  final String Function(InterfaceElement, String) relOfInterface;

  final Set<String> _seen = <String>{};
  String _owner = '';
  String? _sourceId;

  void _emit(String target, GraphRelation relation, GraphConfidence c, int line) {
    final key = '$_sourceId|$target|${graphRelationToJson(relation)}|${graphConfidenceToJson(c)}';
    if (!_seen.add(key)) return;
    out.add(GraphEdge(source: _sourceId!, target: target, relation: relation, confidence: c, line: line));
  }

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    final prev = _owner;
    // analyzer 13.0.0: ClassDeclaration expone el nombre vía
    // `namePart.typeName` (ya no existe `node.name`).
    _owner = node.namePart.typeName.lexeme;
    super.visitClassDeclaration(node);
    _owner = prev;
  }

  @override
  void visitMixinDeclaration(MixinDeclaration node) {
    final prev = _owner;
    _owner = node.name.lexeme;
    super.visitMixinDeclaration(node);
    _owner = prev;
  }

  @override
  void visitEnumDeclaration(EnumDeclaration node) {
    final prev = _owner;
    // analyzer 13.0.0: EnumDeclaration expone el nombre vía
    // `namePart.typeName` (ya no existe `node.name`).
    _owner = node.namePart.typeName.lexeme;
    super.visitEnumDeclaration(node);
    _owner = prev;
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    final id = GraphNodeId.member(relativePath: rel, owner: _owner, name: node.name.lexeme, kind: GraphNodeKind.method);
    final prev = _sourceId;
    _sourceId = nodeIds.contains(id) ? id : null;
    super.visitMethodDeclaration(node);
    _sourceId = prev;
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    if (node.parent is CompilationUnit) {
      final id = GraphNodeId.member(relativePath: rel, owner: '', name: node.name.lexeme, kind: GraphNodeKind.function);
      final prev = _sourceId;
      _sourceId = nodeIds.contains(id) ? id : null;
      super.visitFunctionDeclaration(node);
      _sourceId = prev;
    } else {
      super.visitFunctionDeclaration(node);
    }
  }

  // Nota: los cuerpos de constructores no son orígenes de calls — el grafo no
  // modela nodos de constructor, por lo que `_sourceId` queda null dentro de
  // ellos y sus invocaciones se descartan (límite de alcance intencional).
  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (_sourceId != null) {
      final el = node.methodName.element;
      final line = lineOf(node.methodName.offset);
      var emitted = false;
      if (el != null) {
        final calleeRel = relOfAny(el, projectRoot);
        final calleeName = el.name;
        if (calleeRel != null && calleeName != null && calleeName.isNotEmpty) {
          final owner = ownerOf(el);
          final kind = owner.isEmpty ? GraphNodeKind.function : GraphNodeKind.method;
          final candidate = GraphNodeId.member(relativePath: calleeRel, owner: owner, name: calleeName, kind: kind);
          if (nodeIds.contains(candidate)) {
            _emit(candidate, GraphRelation.calls, GraphConfidence.extracted, line);
            emitted = true;
          }
        }
      }
      if (!emitted) {
        final invoked = node.methodName.name;
        if (kStateApiCalls.contains(invoked)) {
          final extId = GraphNodeId.external(invoked);
          nodes.putIfAbsent(extId, () => GraphNode(id: extId, label: invoked, kind: GraphNodeKind.external));
          _emit(extId, GraphRelation.calls, GraphConfidence.inferred, line);
        }
      }
    }
    super.visitMethodInvocation(node);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    if (_sourceId != null) {
      final el = node.constructorName.type.element;
      if (el is InterfaceElement) {
        final r = relOfInterface(el, projectRoot);
        final name = el.name;
        if (name != null && name.isNotEmpty) {
          final classId = GraphNodeId.declaration(relativePath: r, name: name, kind: GraphNodeKind.class_);
          if (nodeIds.contains(classId)) {
            _emit(classId, GraphRelation.instantiates, GraphConfidence.extracted, lineOf(node.offset));
          }
        }
      }
    }
    super.visitInstanceCreationExpression(node);
  }
}
