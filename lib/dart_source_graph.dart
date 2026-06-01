// lib/dart_source_graph.dart
//
// API pública del paquete dart_source_graph.
// Importa este archivo para acceder a todos los símbolos públicos.

// Fachada principal
export 'src/analyzer.dart' show SourceGraphAnalyzer, inferPackageName;

// Configuración
export 'src/config/source_graph_config.dart'
    show SourceGraphConfig, LayerConfig, WiringConfig, WiringRule;

// Contratos (tipos de datos del grafo)
export 'src/contracts/code_graph.dart';

// Internals exportados para control granular
export 'src/core/builder.dart' show CodeGraphBuilder, kBuiltinRoleMap;
export 'src/core/files.dart' show collectDartFiles;
export 'src/core/query.dart' show CodeGraphQuery;
export 'src/core/reporter.dart' show generateReport;
export 'src/core/resolver.dart' show CodeGraphResolver;
export 'src/core/wiring.dart' show addWiringEdges;
