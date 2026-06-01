// lib/src/core/wiring.dart
//
// Aristas de wiring del grafo: clase registrada → archivo de manifiesto DI/rutas.
// Impulsado por config.wiring. No-op cuando no hay reglas configuradas.

import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/file_system/file_system.dart' as analyzer_fs;
import 'package:path/path.dart' as p;

import '../config/source_graph_config.dart';
import '../contracts/code_graph.dart';

/// Devuelve [base] enriquecido con aristas `wiring`. No-op (devuelve [base]) cuando
/// el consumidor no declara `wiring.rules`.
CodeGraph addWiringEdges(
  CodeGraph base, {
  required String projectRoot,
  required SourceGraphConfig config,
}) {
  final wiring = config.wiring;
  if (wiring == null || wiring.rules.isEmpty) return base;

  final byName = <String, List<String>>{}; // label de declaración -> node ids
  final nodes = <String, GraphNode>{};
  for (final n in base.nodes) {
    nodes[n.id] = n;
    if (n.kind == GraphNodeKind.file || n.kind == GraphNodeKind.external) {
      continue;
    }
    (byName[n.label] ??= <String>[]).add(n.id);
  }

  final added = <GraphEdge>[];
  final seen = <String>{}; // "source|target"

  for (final rule in wiring.rules) {
    final manifestAbs = p.normalize(p.join(projectRoot, rule.manifestFile));
    if (!File(manifestAbs).existsSync()) continue;

    final Set<String> registered;
    try {
      final parsed = parseFile(
        path: manifestAbs,
        featureSet: FeatureSet.latestLanguageVersion(),
        throwIfDiagnostics: false,
      );
      final collector = _RegistrationCollector(rule.registrationCall);
      parsed.unit.accept(collector);
      registered = collector.registered;
    } on FileSystemException {
      continue;
    } on analyzer_fs.FileSystemException {
      continue;
    }
    if (registered.isEmpty) continue;

    final manifestRel = p
        .relative(manifestAbs, from: projectRoot)
        .replaceAll(r'\', '/');
    final manifestId = GraphNodeId.file(manifestRel);
    nodes.putIfAbsent(
      manifestId,
      () => GraphNode(
        id: manifestId,
        label: p.basename(manifestRel),
        kind: GraphNodeKind.file,
        file: manifestRel,
      ),
    );

    for (final name in registered) {
      for (final sourceId in (byName[name] ?? const <String>[])) {
        final key = '$sourceId|$manifestId';
        if (!seen.add(key)) continue;
        added.add(
          GraphEdge(
            source: sourceId,
            target: manifestId,
            relation: GraphRelation.wiring,
            confidence: GraphConfidence.extracted,
          ),
        );
      }
    }
  }

  // Los nodos de manifiesto insertados en `nodes` durante la iteración se descartan
  // aquí si no hay aristas — ninguna arista nueva significa ningún nodo nuevo en el
  // grafo (no-op verdadero).
  if (added.isEmpty) return base;
  return CodeGraph(
    nodes: nodes.values.toList(),
    edges: [...base.edges, ...added],
  );
}

/// Recorre el AST de un manifiesto y recolecta identificadores PascalCase registrados
/// dentro de invocaciones de [callName]. Adaptado de
/// `wiring_cohesion._RegistrationCollector` de alea-flow (analyzer sin cambios;
/// la duplicación es una limpieza deliberada para después).
class _RegistrationCollector extends RecursiveAstVisitor<void> {
  _RegistrationCollector(this.callName);

  final String callName;
  final Set<String> registered = {};

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final type = node.constructorName.type.name.lexeme;
    if (type == callName) {
      final classes = _ClassRefCollector();
      node.argumentList.accept(classes);
      registered.addAll(classes.classes);
      final typeArgs = node.constructorName.type.typeArguments;
      if (typeArgs != null) {
        for (final ta in typeArgs.arguments) {
          if (ta is NamedType) registered.add(ta.name.lexeme);
        }
      }
    }
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final method = node.methodName.name;
    final target = node.target;
    final fullCall = target is SimpleIdentifier
        ? '${target.name}.$method'
        : method;
    if (fullCall == callName || method == callName) {
      final classes = _ClassRefCollector();
      node.argumentList.accept(classes);
      registered.addAll(classes.classes);
      final typeArgs = node.typeArguments;
      if (typeArgs != null) {
        for (final ta in typeArgs.arguments) {
          if (ta is NamedType) registered.add(ta.name.lexeme);
        }
      }
    }
    super.visitMethodInvocation(node);
  }
}

/// Recolecta cada identificador PascalCase visitado dentro de un subárbol.
/// Adaptado de `wiring_cohesion._ClassRefCollector` de alea-flow.
class _ClassRefCollector extends RecursiveAstVisitor<void> {
  final Set<String> classes = {};

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    final name = node.name;
    if (_isPascalCase(name)) classes.add(name);
    super.visitSimpleIdentifier(node);
  }

  @override
  void visitNamedType(NamedType node) {
    classes.add(node.name.lexeme);
    super.visitNamedType(node);
  }

  bool _isPascalCase(String s) {
    if (s.isEmpty) return false;
    final c = s.codeUnitAt(0);
    return c >= 0x41 && c <= 0x5A;
  }
}
