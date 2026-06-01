// lib/src/core/builder.dart
//
// Builder estructural del grafo de código fuente (slice-1a).
// Realiza un pase propio del AST parseado sin tocar los analyzers.
// Emite nodos de archivo (con layer), aristas de directivas, nodos de
// declaración y aristas de herencia por nombre.

import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/file_system/file_system.dart' as analyzer_fs;
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../config/source_graph_config.dart';
import '../contracts/code_graph.dart';
import 'glob_match.dart';

/// Mapa built-in de supertipo → etiqueta de rol semántico. Fundamentado en el
/// catálogo empírico de gestión de estado (docs/superpowers/research/
/// 2026-05-31-state-mgmt-semantics-catalog.md).
/// Los consumidores extienden/sobreescriben vía [SourceGraphConfig.roleOverrides].
const Map<String, String> kBuiltinRoleMap = {
  'Notifier': 'riverpod.notifier',
  'AsyncNotifier': 'riverpod.notifier',
  'StreamNotifier': 'riverpod.notifier',
  'ConsumerWidget': 'riverpod.consumer_widget',
  'ConsumerStatefulWidget': 'riverpod.consumer_widget',
  'HookConsumerWidget': 'riverpod.consumer_widget',
  'Bloc': 'bloc.bloc',
  'Cubit': 'bloc.cubit',
  'ChangeNotifier': 'flutter.change_notifier',
  'GetxController': 'getx.controller',
  'GetxService': 'getx.service',
  'GetView': 'getx.view',
  'GetWidget': 'getx.view',
  'StatelessWidget': 'flutter.widget',
  'StatefulWidget': 'flutter.widget',
  'State': 'flutter.state',
};

/// Construye un [CodeGraph] estructural a partir del AST parseado de los archivos
/// Dart del proyecto.
///
/// Mantiene estado mutable por build ([_skipped], [_packageName]) que se reinicia
/// al inicio de cada llamada a [build]. Una sola instancia es de uso único por
/// build y NO es segura para llamadas concurrentes; crea un builder nuevo (o llama
/// secuencialmente) si necesitas construir más de un grafo.
class CodeGraphBuilder {
  /// SHA-256 sobre la lista ordenada de líneas "relpath sha256(bytes)" para cada
  /// archivo de entrada. Independiente del orden; sensible al contenido. Los archivos
  /// ilegibles se incluyen solo por ruta (su desaparición/retorno mueve el hash).
  static String inputsFingerprint(String projectRoot, List<String> filePaths) {
    final lines = <String>[];
    for (final absolute in filePaths) {
      final rel = p
          .relative(p.normalize(absolute), from: projectRoot)
          .replaceAll(r'\', '/');
      String contentHash;
      try {
        contentHash = sha256
            .convert(File(absolute).readAsBytesSync())
            .toString();
      } on FileSystemException {
        contentHash = 'unreadable';
      }
      lines.add('$rel $contentHash');
    }
    lines.sort();
    final digest = sha256.convert(utf8.encode(lines.join('\n')));
    return 'sha256:$digest';
  }

  int _skipped = 0;

  /// Número de archivos omitidos en el último build (FileSystemException).
  int get skippedFiles => _skipped;

  String? _packageName;

  /// Construye el grafo estructural para [filePaths] bajo [projectRoot].
  ///
  /// Cuando [packageName] es el nombre del paquete propio, los URIs
  /// `package:<name>/x` en import/export resuelven al nodo interno `file:lib/x`
  /// en lugar de un nodo externo. Pasar null deja todos los URIs `package:` como
  /// externos.
  CodeGraph build({
    required String projectRoot,
    required List<String> filePaths,
    required SourceGraphConfig config,
    String? packageName,
  }) {
    _skipped = 0;
    _packageName = packageName;
    // mapa id -> nodo (desduplicar nodos externos)
    final nodes = <String, GraphNode>{};
    final edges = <GraphEdge>[];
    final layers = config.layers;

    for (final absolute in filePaths) {
      final normalized = p.normalize(absolute);
      final rel = _projectRelative(normalized, projectRoot);

      // parseFile (PhysicalResourceProvider por defecto) envuelve
      // FileSystemException de dart:io en la propia del analyzer antes de
      // propagarla; en la práctica dispara el brazo del analyzer. El brazo
      // dart:io protege a llamadores que inyectan un ResourceProvider custom.
      // En ambos casos: omitir el archivo y contabilizarlo.
      late final ParseStringResult parsed;
      try {
        parsed = parseFile(
          path: normalized,
          featureSet: FeatureSet.latestLanguageVersion(),
          throwIfDiagnostics: false,
        );
      } on FileSystemException {
        _skipped++;
        continue;
      } on analyzer_fs.FileSystemException {
        _skipped++;
        continue;
      }
      final unit = parsed.unit;
      int lineOf(int offset) => parsed.lineInfo.getLocation(offset).lineNumber;

      // Crear nodo de archivo con su capa arquitectónica (puede ser null).
      final fileId = GraphNodeId.file(rel);
      nodes[fileId] = GraphNode(
        id: fileId,
        label: p.basename(rel),
        kind: GraphNodeKind.file,
        file: rel,
        layer: _layerOf(rel, layers),
      );

      // Procesar directivas: import, export, part, part of.
      for (final directive in unit.directives) {
        if (directive is ImportDirective) {
          _addUriEdge(
            nodes,
            edges,
            fileId,
            rel,
            directive.uri.stringValue,
            GraphRelation.imports,
            projectRoot,
            lineOf(directive.offset),
          );
        } else if (directive is ExportDirective) {
          _addUriEdge(
            nodes,
            edges,
            fileId,
            rel,
            directive.uri.stringValue,
            GraphRelation.exports,
            projectRoot,
            lineOf(directive.offset),
          );
        } else if (directive is PartDirective) {
          _addUriEdge(
            nodes,
            edges,
            fileId,
            rel,
            directive.uri.stringValue,
            GraphRelation.part,
            projectRoot,
            lineOf(directive.offset),
          );
        } else if (directive is PartOfDirective) {
          final uri = directive.uri?.stringValue;
          if (uri != null) {
            _addUriEdge(
              nodes,
              edges,
              fileId,
              rel,
              uri,
              GraphRelation.partOf,
              projectRoot,
              lineOf(directive.offset),
            );
          } else {
            // part of con nombre de librería (sin URI).
            final libName =
                directive.libraryName?.tokens.map((t) => t.lexeme).join() ??
                'unknown';
            final targetId = GraphNodeId.external(libName);
            nodes.putIfAbsent(
              targetId,
              () => GraphNode(
                id: targetId,
                label: libName,
                kind: GraphNodeKind.external,
              ),
            );
            edges.add(
              GraphEdge(
                source: fileId,
                target: targetId,
                relation: GraphRelation.partOf,
                confidence: GraphConfidence.extracted,
                line: lineOf(directive.offset),
              ),
            );
          }
        }
      }

      // Procesar declaraciones top-level: clases, mixins, enums, funciones.
      for (final decl in unit.declarations) {
        if (decl is ClassDeclaration) {
          final name = decl.namePart.typeName.lexeme;
          final declLine = lineOf(decl.namePart.typeName.offset);
          final supers = <String>[
            if (decl.extendsClause != null)
              decl.extendsClause!.superclass.name.lexeme,
            for (final t in decl.withClause?.mixinTypes ?? const <NamedType>[])
              t.name.lexeme,
            for (final t
                in decl.implementsClause?.interfaces ?? const <NamedType>[])
              t.name.lexeme,
          ];
          _addDeclaration(
            nodes,
            edges,
            fileId: fileId,
            fileRel: rel,
            name: name,
            kind: GraphNodeKind.class_,
            line: declLine,
            role:
                _roleFromAnnotations(decl.metadata, isFunction: false) ??
                _roleFor(supers, config.roleOverrides),
          );
          _addInheritance(
            nodes,
            edges,
            fileRel: rel,
            declName: name,
            declKind: GraphNodeKind.class_,
            extendsType: decl.extendsClause?.superclass,
            withTypes: decl.withClause?.mixinTypes,
            implementsTypes: decl.implementsClause?.interfaces,
            lineOf: lineOf,
          );
          // Procesar miembros de la clase: métodos.
          final classId = GraphNodeId.declaration(
            relativePath: rel,
            name: name,
            kind: GraphNodeKind.class_,
          );
          for (final member in decl.body.members) {
            if (member is MethodDeclaration) {
              final mName = member.name.lexeme;
              final mLine = lineOf(member.name.offset);
              final mId = GraphNodeId.member(
                relativePath: rel,
                owner: name,
                name: mName,
                kind: GraphNodeKind.method,
              );
              nodes[mId] = GraphNode(
                id: mId,
                label: '$name.$mName',
                kind: GraphNodeKind.method,
                file: rel,
                line: mLine,
              );
              edges.add(
                GraphEdge(
                  source: classId,
                  target: mId,
                  relation: GraphRelation.contains,
                  confidence: GraphConfidence.extracted,
                  line: mLine,
                ),
              );
              _collectCalls(
                nodes,
                edges,
                sourceId: mId,
                body: member.body,
                lineOf: lineOf,
              );
            }
          }
        } else if (decl is MixinDeclaration) {
          final name = decl.name.lexeme;
          final declLine = lineOf(decl.name.offset);
          _addDeclaration(
            nodes,
            edges,
            fileId: fileId,
            fileRel: rel,
            name: name,
            kind: GraphNodeKind.mixin_,
            line: declLine,
          );
          _addInheritance(
            nodes,
            edges,
            fileRel: rel,
            declName: name,
            declKind: GraphNodeKind.mixin_,
            implementsTypes: decl.implementsClause?.interfaces,
            lineOf: lineOf,
          );
        } else if (decl is EnumDeclaration) {
          final name = decl.namePart.typeName.lexeme;
          final declLine = lineOf(decl.namePart.typeName.offset);
          _addDeclaration(
            nodes,
            edges,
            fileId: fileId,
            fileRel: rel,
            name: name,
            kind: GraphNodeKind.enum_,
            line: declLine,
          );
          _addInheritance(
            nodes,
            edges,
            fileRel: rel,
            declName: name,
            declKind: GraphNodeKind.enum_,
            withTypes: decl.withClause?.mixinTypes,
            implementsTypes: decl.implementsClause?.interfaces,
            lineOf: lineOf,
          );
        } else if (decl is FunctionDeclaration) {
          final fName = decl.name.lexeme;
          final fLine = lineOf(decl.name.offset);
          final fId = GraphNodeId.member(
            relativePath: rel,
            owner: '',
            name: fName,
            kind: GraphNodeKind.function,
          );
          nodes[fId] = GraphNode(
            id: fId,
            label: fName,
            kind: GraphNodeKind.function,
            file: rel,
            line: fLine,
            role: _roleFromAnnotations(decl.metadata, isFunction: true),
          );
          edges.add(
            GraphEdge(
              source: fileId,
              target: fId,
              relation: GraphRelation.contains,
              confidence: GraphConfidence.extracted,
              line: fLine,
            ),
          );
          _collectCalls(
            nodes,
            edges,
            sourceId: fId,
            body: decl.functionExpression.body,
            lineOf: lineOf,
          );
        }
      }
    }

    return CodeGraph(nodes: nodes.values.toList(), edges: edges);
  }

  /// Rol derivado de las anotaciones de una declaración. `@riverpod` / `@Riverpod(…)`
  /// de Riverpod codegen generan el supertipo en un `.g.dart` excluido, por lo que la
  /// anotación es la única señal de rol. [isFunction] distingue un provider funcional
  /// de un notifier de clase. Se evalúa ANTES del mapa de supertipo.
  String? _roleFromAnnotations(
    NodeList<Annotation> metadata, {
    required bool isFunction,
  }) {
    for (final a in metadata) {
      // 'riverpod' (@riverpod) | 'Riverpod' (@Riverpod())
      final n = a.name.name;
      if (n == 'riverpod' || n == 'Riverpod') {
        return isFunction ? 'riverpod.provider' : 'riverpod.notifier';
      }
    }
    return null;
  }

  /// Primer nombre de supertipo (orden extends/with/implements) que mapea a un rol.
  /// [overrides] de [SourceGraphConfig.roleOverrides] ganan sobre el mapa built-in.
  /// Null cuando ninguno coincide.
  String? _roleFor(
    Iterable<String> supertypeNames,
    Map<String, String> overrides,
  ) {
    for (final n in supertypeNames) {
      final r = overrides[n] ?? kBuiltinRoleMap[n];
      if (r != null) return r;
    }
    return null;
  }

  /// Recorre [body] y emite una arista `calls` desde [sourceId] a un nodo externo
  /// por nombre para cada invocación de método. La resolución por nombre es
  /// inherentemente imprecisa, por lo que toda arista es [GraphConfidence.ambiguous].
  void _collectCalls(
    Map<String, GraphNode> nodes,
    List<GraphEdge> edges, {
    required String sourceId,
    required AstNode body,
    required int Function(int) lineOf,
  }) {
    body.accept(
      _CallCollector((methodName, offset) {
        final tId = GraphNodeId.external(methodName);
        nodes.putIfAbsent(
          tId,
          () => GraphNode(
            id: tId,
            label: methodName,
            kind: GraphNodeKind.external,
          ),
        );
        edges.add(
          GraphEdge(
            source: sourceId,
            target: tId,
            relation: GraphRelation.calls,
            confidence: GraphConfidence.ambiguous,
            line: lineOf(offset),
          ),
        );
      }),
    );
  }

  /// Agrega el nodo de declaración y la arista contains desde el archivo.
  void _addDeclaration(
    Map<String, GraphNode> nodes,
    List<GraphEdge> edges, {
    required String fileId,
    required String fileRel,
    required String name,
    required GraphNodeKind kind,
    required int line,
    String? role,
  }) {
    final id = GraphNodeId.declaration(
      relativePath: fileRel,
      name: name,
      kind: kind,
    );
    nodes[id] = GraphNode(
      id: id,
      label: name,
      kind: kind,
      file: fileRel,
      line: line,
      role: role,
    );
    edges.add(
      GraphEdge(
        source: fileId,
        target: id,
        relation: GraphRelation.contains,
        confidence: GraphConfidence.extracted,
        line: line,
      ),
    );
  }

  /// Agrega aristas de herencia (extends, mixesIn, implements) desde una declaración
  /// hacia nodos externos por nombre.
  void _addInheritance(
    Map<String, GraphNode> nodes,
    List<GraphEdge> edges, {
    required String fileRel,
    required String declName,
    required GraphNodeKind declKind,
    NamedType? extendsType,
    List<NamedType>? withTypes,
    List<NamedType>? implementsTypes,
    required int Function(int) lineOf,
  }) {
    final fromId = GraphNodeId.declaration(
      relativePath: fileRel,
      name: declName,
      kind: declKind,
    );

    void link(NamedType t, GraphRelation r) {
      final typeName = t.name.lexeme;
      final targetId = GraphNodeId.external(typeName);
      nodes.putIfAbsent(
        targetId,
        () => GraphNode(
          id: targetId,
          label: typeName,
          kind: GraphNodeKind.external,
        ),
      );
      edges.add(
        GraphEdge(
          source: fromId,
          target: targetId,
          relation: r,
          confidence: GraphConfidence.extracted,
          line: lineOf(t.offset),
        ),
      );
    }

    if (extendsType != null) link(extendsType, GraphRelation.extends_);
    for (final t in withTypes ?? const <NamedType>[]) {
      link(t, GraphRelation.mixesIn);
    }
    for (final t in implementsTypes ?? const <NamedType>[]) {
      link(t, GraphRelation.implements_);
    }
  }

  /// Si [rawUri] es `package:<self>/<sub>` del paquete propio del proyecto,
  /// devuelve la ruta relativa `lib/<sub>`; de lo contrario null.
  /// El mapeo `package:<name>/x` ⇄ `<root>/lib/x` es una regla fija del sistema
  /// de paquetes Dart, por lo que la arista resultante es `extracted`.
  String? _selfPackageFile(String rawUri) {
    assert(rawUri.startsWith('package:'));
    final pkg = _packageName;
    if (pkg == null || pkg.isEmpty) return null;
    final rest = rawUri.substring('package:'.length); // "<name>/<sub>"
    final slash = rest.indexOf('/');
    if (slash <= 0) return null;
    if (rest.substring(0, slash) != pkg) return null;
    final sub = rest.substring(slash + 1);
    if (sub.isEmpty) return null;
    return 'lib/$sub';
  }

  /// Resuelve [rawUri] a un id de nodo (archivo interno o externo) y agrega la arista.
  void _addUriEdge(
    Map<String, GraphNode> nodes,
    List<GraphEdge> edges,
    String fromId,
    String fromRel,
    String? rawUri,
    GraphRelation relation,
    String projectRoot,
    int line,
  ) {
    if (rawUri == null || rawUri.isEmpty) return;
    final String targetId;
    if (rawUri.startsWith('package:')) {
      final selfFile = _selfPackageFile(rawUri);
      if (selfFile != null) {
        // URI del paquete propio resuelve al nodo de archivo interno lib/;
        // no se crea nodo externo.
        targetId = GraphNodeId.file(selfFile);
      } else {
        targetId = GraphNodeId.external(rawUri);
        nodes.putIfAbsent(
          targetId,
          () => GraphNode(
            id: targetId,
            label: rawUri.contains('/') ? rawUri.split('/').last : rawUri,
            kind: GraphNodeKind.external,
          ),
        );
      }
    } else if (rawUri.startsWith('dart:')) {
      targetId = GraphNodeId.external(rawUri);
      nodes.putIfAbsent(
        targetId,
        () => GraphNode(
          id: targetId,
          label: rawUri.contains('/') ? rawUri.split('/').last : rawUri,
          kind: GraphNodeKind.external,
        ),
      );
    } else {
      // Limitación conocida slice-1a: si el target resuelto no está en `filePaths`
      // (código generado, o ruta fuera del conjunto de escaneo), esta arista referencia
      // un id file: sin nodo correspondiente. Aceptable por ahora; cobertura exhaustiva
      // de nodos es trabajo de una slice posterior.
      final fromDir = p.dirname(p.join(projectRoot, fromRel));
      final absTarget = p.normalize(p.join(fromDir, rawUri));
      final relTarget = _projectRelative(absTarget, projectRoot);
      targetId = GraphNodeId.file(relTarget);
    }
    edges.add(
      GraphEdge(
        source: fromId,
        target: targetId,
        relation: relation,
        confidence: GraphConfidence.extracted,
        line: line,
      ),
    );
  }

  /// Devuelve el nombre de la capa para [relativePath] según la lista de capas,
  /// o null si ninguna capa lo cubre. CAMBIO CRÍTICO respecto a alea-flow:
  /// recibe [List<LayerConfig>] (con campo `name`) en lugar de [Map<String, LayerConfig>].
  String? _layerOf(String relativePath, List<LayerConfig> layers) {
    final rel = relativePath.replaceAll(r'\', '/');
    for (final layer in layers) {
      for (final layerPath in layer.paths) {
        final lp = layerPath.replaceAll(r'\', '/');
        // Un directorio sin metacaracteres glob ni '/' al final se trata como
        // prefijo de directorio; los patrones con '*'/'**' o '/' al final coinciden tal cual.
        final pattern = (lp.contains('*') || lp.endsWith('/')) ? lp : '$lp/';
        if (globMatch(pattern, rel)) return layer.name;
      }
    }
    return null;
  }

  /// Convierte una ruta absoluta a ruta relativa al proyecto, normalizada con '/'.
  String _projectRelative(String path, String projectRoot) {
    if (!p.isAbsolute(path)) return path.replaceAll(r'\', '/');
    try {
      return p.relative(path, from: projectRoot).replaceAll(r'\', '/');
    } on ArgumentError {
      return path.replaceAll(r'\', '/');
    }
  }
}

/// Visita el cuerpo de un miembro y reporta cada invocación de método por nombre.
/// Usado por [CodeGraphBuilder] para emitir aristas `calls`.
class _CallCollector extends RecursiveAstVisitor<void> {
  _CallCollector(this.onCall);

  final void Function(String methodName, int offset) onCall;

  @override
  void visitMethodInvocation(MethodInvocation node) {
    onCall(node.methodName.name, node.methodName.offset);
    super.visitMethodInvocation(node);
  }
}
