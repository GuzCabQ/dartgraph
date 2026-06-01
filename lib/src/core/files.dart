// lib/src/core/files.dart
//
// Recolección compartida de archivos .dart para el productor y consumidor del grafo.
// Modelo opt-out: todos los .dart bajo lib/ menos los que coincidan con config.exclude.
// Deduplicado y ordenado.

import 'dart:io';

import 'package:path/path.dart' as p;

import '../config/source_graph_config.dart';
import 'glob_match.dart';

/// Recolecta archivos `.dart` para el grafo bajo el modelo **opt-out**: todos los
/// `.dart` bajo `lib/`, MENOS cualquier ruta que coincida con un glob de `config.exclude`.
/// Las rutas de capas ya NO controlan la recolección — solo clasifican (ver
/// `CodeGraphBuilder._layerOf`). Un punto ciego solo puede existir por una entrada
/// explícita en `config.exclude`, nunca por omisión. Deduplicado + ordenado.
///
/// Productor y consumidor comparten esta función para que `inputs_fingerprint`
/// sea consistente.
List<String> collectDartFiles(String projectRoot, SourceGraphConfig config) {
  final lib = p.join(projectRoot, 'lib');
  if (!Directory(lib).existsSync()) return const [];
  final exclude = config.exclude;
  final out = <String>{};
  for (final entity in Directory(
    lib,
  ).listSync(recursive: true, followLinks: false)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final abs = p.normalize(entity.absolute.path);
    final rel = p.relative(abs, from: projectRoot).replaceAll(r'\', '/');
    if (exclude.any((g) => globMatch(g, rel))) continue;
    out.add(abs);
  }
  return out.toList()..sort();
}
