// lib/src/core/state_api.dart
//
// Allowlist de nombres de llamadas a APIs de gestión de estado reconocidas.
// Fuente de verdad única consumida por el resolver (para conservar estas calls
// externas como `inferred`) y por la query (para el reporte State Flow).

/// Nombres de métodos de APIs de estado de los frameworks soportados.
const Set<String> kStateApiCalls = {
  'watch', 'read', 'listen', 'select', // riverpod / provider
  'find', 'put', 'lazyPut', 'putAsync', // getx
};
