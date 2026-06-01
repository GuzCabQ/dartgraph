// lib/src/config/source_graph_config.dart
//
// Configuración opcional para SourceGraphAnalyzer.
// Sin dependencia de ningún archivo externo (.alea.yaml u otro).
// Todos los campos tienen defaults sensatos — el paquete funciona sin config.

/// Clasifica archivos en una capa arquitectónica según patrón de ruta.
class LayerConfig {
  /// Nombre de la capa, e.g. "core", "adapters", "presentation".
  final String name;

  /// Patrones glob o prefijos de directorio. Ej: ['lib/src/core/', 'lib/src/domain/**'].
  final List<String> paths;

  const LayerConfig({required this.name, required this.paths});
}

/// Detecta qué clases se registran en un archivo de manifiesto DI/rutas.
class WiringRule {
  /// Etiqueta legible, usada en mensajes y IDs de regla.
  final String name;

  /// Patrón glob para nombres de clase. Soporta `*` al inicio, final o ambos.
  final String classPattern;

  /// Ruta relativa al proyecto del archivo de manifiesto.
  final String manifestFile;

  /// Nombre exacto de la función/constructor que registra la clase.
  final String registrationCall;

  /// Directorios a escanear. Vacío = todos los declarados en layers.
  final List<String> scanPaths;

  const WiringRule({
    required this.name,
    required this.classPattern,
    required this.manifestFile,
    required this.registrationCall,
    this.scanPaths = const [],
  });
}

/// Configuración del análisis de wiring (registro DI/rutas).
class WiringConfig {
  final List<WiringRule> rules;

  const WiringConfig({this.rules = const []});
}

/// Configuración opcional para [SourceGraphAnalyzer] y [CodeGraphBuilder].
///
/// Sin config → grafo completo con roles built-in, sin layer tags, sin wiring edges.
class SourceGraphConfig {
  /// Patrones glob de archivos a excluir. Por defecto excluye código generado.
  final List<String> exclude;

  /// Asigna nodos a capas arquitectónicas según patrón de ruta.
  final List<LayerConfig> layers;

  /// Extiende o sobreescribe el mapa built-in de supertipo → rol semántico.
  final Map<String, String> roleOverrides;

  /// Configuración de wiring. `null` = no-op.
  final WiringConfig? wiring;

  const SourceGraphConfig({
    this.exclude = const ['**/*.g.dart', '**/*.freezed.dart'],
    this.layers = const [],
    this.roleOverrides = const {},
    this.wiring,
  });
}
