// lib/src/analyzer.dart
//
// Fachada principal del paquete. Orquesta los tres pasos internos:
// build → resolve → wiring en un solo método asíncrono.
// Los internals (CodeGraphBuilder, CodeGraphResolver, etc.) siguen
// exportados en el barrel para quien necesite control granular.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'config/source_graph_config.dart';
import 'contracts/code_graph.dart';
import 'core/builder.dart';
import 'core/files.dart';
import 'core/resolver.dart';
import 'core/wiring.dart';

/// Lee el nombre del paquete desde pubspec.yaml del proyecto analizado.
/// Retorna null si el archivo no existe o no puede parsearse.
/// Función top-level (no privada) para que build_command.dart pueda importarla.
String? inferPackageName(String projectRoot) {
  try {
    final pubspec = File(p.join(projectRoot, 'pubspec.yaml'));
    if (!pubspec.existsSync()) return null;
    final yaml = loadYaml(pubspec.readAsStringSync()) as YamlMap;
    return yaml['name'] as String?;
  } catch (_) {
    return null;
  }
}

/// Fachada que orquesta build → resolve → wiring en una sola llamada.
///
/// Uso mínimo:
/// ```dart
/// final graph = await SourceGraphAnalyzer().analyze('.');
/// ```
class SourceGraphAnalyzer {
  final SourceGraphConfig config;

  const SourceGraphAnalyzer({this.config = const SourceGraphConfig()});

  /// Analiza el proyecto en [projectRoot] y retorna su grafo de código fuente.
  ///
  /// [resolve] activa el resolver semántico (más lento, requiere `dart pub get`).
  /// [wiring] activa la detección de registros DI/rutas (requiere config.wiring != null).
  /// [packageName] se infiere del pubspec.yaml si no se provee.
  Future<CodeGraph> analyze(
    String projectRoot, {
    bool resolve = false,
    bool wiring = false,
    String? packageName,
  }) async {
    final root = p.canonicalize(projectRoot);
    final files = collectDartFiles(root, config);
    final pkg = packageName ?? inferPackageName(root);

    final builder = CodeGraphBuilder();
    var graph = builder.build(
      projectRoot: root,
      filePaths: files,
      config: config,
      packageName: pkg,
    );

    if (wiring && config.wiring != null) {
      graph = addWiringEdges(graph, projectRoot: root, config: config);
    }

    if (resolve) {
      final resolver = CodeGraphResolver();
      graph = await resolver.resolve(
        graph,
        projectRoot: root,
        filePaths: files,
        config: config,
      );
    }

    return graph;
  }
}
