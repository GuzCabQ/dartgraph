# dart_source_graph — Spec de diseño

**Fecha:** 2026-05-31  
**Paquete:** `dart_source_graph`  
**Repositorio:** `/Users/zeref/Documents/Github/dartgraph`  
**Origen del código:** extraído de `alea-flow` (`/Users/zeref/Documents/Github/alea-flow`)

---

## Propósito

`dart_source_graph` produce un grafo estructurado y semántico del código fuente Dart/Flutter. Su consumidor principal es una IA (o herramienta de análisis) que necesita entender un proyecto sin leer cada archivo.

**Principio rector:** mejor no tener un dato que tenerlo mal. Cada arista del grafo lleva un nivel de confianza (`extracted` / `inferred` / `ambiguous`) para que el consumidor sepa cuánto puede confiar en ella.

**Lo que entrega:**

- Qué archivos existen y en qué capa arquitectónica viven (`layer`)
- Qué clases son Widgets, Notifiers, Blocs, Controllers — detectado automáticamente (`role`)
- Qué depende de qué (imports, herencia, referencias de tipo)
- Dónde están registradas las clases en el sistema de DI/rutas (wiring)
- Un fingerprint SHA-256 para detectar si el grafo está desactualizado

**Lo que NO hace:**

- No ejecuta `dart analyze` ni reporta errores de compilación
- No genera código
- No reemplaza el árbol de archivos — lo complementa con semántica

---

## Convenciones de idioma

| Artefacto | Idioma |
|---|---|
| Nombres de clases, métodos, variables, enums | Inglés |
| Comentarios en código (`//`, `///`) | Español |
| README, ARCHITECTURE.md, ADRs, docs | Español |
| Mensajes de error en la API pública | Español |
| Mensajes del CLI | Español |

---

## Enfoque elegido: B — API pública limpia + internals intactos

Los archivos internos se migran sin cambios de comportamiento. Se añade `SourceGraphAnalyzer` como fachada principal que orquesta los tres pasos (build → resolve → wiring) en un solo método. Los internals siguen exportados para control granular.

---

## Estructura del paquete

```
dart_source_graph/
├── pubspec.yaml
├── ARCHITECTURE.md              ← fronteras internas (español)
├── README.md                    ← orientado a pub.dev (español)
├── lib/
│   ├── dart_source_graph.dart   ← barrel público
│   └── src/
│       ├── contracts/
│       │   └── code_graph.dart  ← tipos puros: GraphNode, GraphEdge, CodeGraph, CodeGraphMeta
│       ├── config/
│       │   └── source_graph_config.dart  ← SourceGraphConfig (sin acoplamiento externo)
│       ├── core/
│       │   ├── builder.dart     ← CodeGraphBuilder
│       │   ├── resolver.dart    ← CodeGraphResolver
│       │   ├── wiring.dart      ← addWiringEdges()
│       │   ├── query.dart       ← CodeGraphQuery
│       │   ├── files.dart       ← collectDartFiles()
│       │   └── glob_match.dart  ← globMatch()
│       └── analyzer.dart        ← SourceGraphAnalyzer (fachada pública)
├── bin/
│   └── dart_source_graph.dart   ← entry point del ejecutable CLI
└── test/
    └── core/                    ← tests migrados de alea-flow (9 archivos)
```

---

## API pública (`lib/dart_source_graph.dart`)

Exportaciones:

| Símbolo | Propósito |
|---|---|
| `SourceGraphAnalyzer` | Entry point principal |
| `SourceGraphConfig` | Configuración opcional |
| `CodeGraph` | Grafo inmutable (nodos + aristas) |
| `CodeGraphMeta` | Metadatos del grafo (fingerprint, versión, etc.) |
| `GraphNode` | Nodo individual |
| `GraphEdge` | Arista dirigida |
| `GraphNodeKind` | Enum: file, class_, mixin_, enum_, method, function, external |
| `GraphRelation` | Enum: imports, exports, extends_, implements_, mixesIn, references, wiring, calls |
| `GraphConfidence` | Enum: extracted, inferred, ambiguous |
| `GraphNodeId` | Builder de IDs estables |
| `CodeGraphQuery` | Consultas sobre el grafo en memoria |
| `CodeGraphBuilder` | Builder granular (control manual) |
| `CodeGraphResolver` | Resolver granular (control manual) |
| `addWiringEdges` | Función granular (control manual) |
| `collectDartFiles` | Recolección de archivos (control manual) |
| `LayerConfig` | Tipo de configuración de capa (pattern → nombre) |
| `WiringConfig` | Tipo de configuración de wiring (manifests + reglas) |

---

## `SourceGraphConfig`

```dart
SourceGraphConfig({
  List<String> exclude = const ['**/*.g.dart', '**/*.freezed.dart'],
  List<LayerConfig> layers = const [],      // cada LayerConfig tiene: pattern (glob) + name (String)
  Map<String, String> roleOverrides = const {},
  WiringConfig? wiring,                     // WiringConfig tiene: manifests (List<String>) + rules (List<WiringRule>)
})
```

Sin config → grafo completo con roles built-in, sin layer tags, sin wiring edges. Cero acoplamiento a `.alea.yaml` o cualquier otro archivo externo.

**Roles detectados automáticamente (built-in):**

| Supertipo | Rol asignado |
|---|---|
| `Notifier`, `AsyncNotifier`, `StreamNotifier` | `riverpod.notifier` |
| `ConsumerWidget`, `ConsumerStatefulWidget`, `HookConsumerWidget` | `riverpod.consumer_widget` |
| `Bloc` | `bloc.bloc` |
| `Cubit` | `bloc.cubit` |
| `ChangeNotifier` | `flutter.change_notifier` |
| `GetxController`, `GetxService` | `getx.controller` / `getx.service` |
| `GetView`, `GetWidget` | `getx.view` |
| `StatelessWidget`, `StatefulWidget` | `flutter.widget` |
| `State` | `flutter.state` |

---

## `SourceGraphAnalyzer` (fachada)

```dart
class SourceGraphAnalyzer {
  SourceGraphAnalyzer({SourceGraphConfig config = const SourceGraphConfig()});

  Future<CodeGraph> analyze(
    String projectRoot, {
    bool resolve = false,    // activa CodeGraphResolver (más lento, más preciso)
    bool wiring = false,     // activa addWiringEdges()
    String? packageName,     // inferido del pubspec.yaml si es null
  });
}
```

**Flujo interno:**

1. `collectDartFiles()` — recolecta archivos respetando `config.exclude`
2. `CodeGraphBuilder.build()` — grafo estructural desde AST parseado
3. Si `resolve: true` → `CodeGraphResolver.resolve()` — enriquece con semántica del analyzer
4. Si `wiring: true` → `addWiringEdges()` — agrega edges de registro DI/rutas
5. Retorna `CodeGraph`

---

## CLI

Ejecutable: `dart run dart_source_graph` (o `dart_source_graph` si se instala globalmente).

```
dart_source_graph build
  --project-root <path>   (default: '.')
  --output <path>         (default: stdout)
  --config <yaml>         (opcional, sin default — no acopla a .alea.yaml)
  --resolve               (análisis semántico, más lento)
  --ensure-fresh          (fuerza rebuild comparando fingerprint)

dart_source_graph query <subcomando>
  -i <graph.json>         (default: 'graph.json')
  --format text|json

  subcomandos:
    impact <nombre|id>    ← qué depende de este nodo (cierre transitivo inverso)
    neighbors <nombre|id> ← vecinos directos (1-hop)
    god-nodes [--limit N] ← nodos más conectados (hubs, excluye externos)
```

---

## Migración desde `alea-flow`

| Archivo origen | Destino |
|---|---|
| `lib/src/contracts/code_graph.dart` | `lib/src/contracts/code_graph.dart` |
| `lib/src/core/graph/code_graph_builder.dart` | `lib/src/core/builder.dart` |
| `lib/src/core/graph/code_graph_resolver.dart` | `lib/src/core/resolver.dart` |
| `lib/src/core/graph/code_graph_wiring.dart` | `lib/src/core/wiring.dart` |
| `lib/src/core/graph/code_graph_query.dart` | `lib/src/core/query.dart` |
| `lib/src/core/graph/glob_match.dart` | `lib/src/core/glob_match.dart` |
| `lib/src/core/graph/graph_files.dart` | `lib/src/core/files.dart` |
| `lib/src/cli/commands/graph_command.dart` | `lib/src/cli/build_command.dart` (reescrito: usa `SourceGraphConfig` en lugar de `ProjectConfig`) |
| `lib/src/cli/commands/graph_query_command.dart` | `lib/src/cli/query_command.dart` (reescrito: usa `SourceGraphConfig` en lugar de `ProjectConfig`) |
| `test/core/graph/*.dart` (9 archivos) | `test/core/` |

**Cambios al migrar:**

- `GraphConfig` → `SourceGraphConfig` (mismos campos, sin dependencia de `ProjectConfig`)
- Imports de `package:alea_flow/...` → `package:dart_source_graph/...`
- Comentarios en código traducidos al español
- `ProjectConfig` removido de las firmas — reemplazado por `SourceGraphConfig`

**`alea-flow` post-extracción:** agrega `dart_source_graph` como dependencia en su `pubspec.yaml`, elimina los archivos migrados, y construye un `SourceGraphConfig` a partir de su `ProjectConfig` existente. Cero cambio de comportamiento observable.

---

## Dependencias

```yaml
dependencies:
  analyzer: ^12.0.0   # AST parsing y resolución semántica
  crypto: ^3.0.7      # SHA-256 para inputs_fingerprint
  path: ^1.9.1        # utilidades de rutas
  args: ^2.7.0        # parsing de argumentos CLI
  yaml: ^3.1.3        # lectura del --config opcional

dev_dependencies:
  test: ^1.31.1
  lints: ^6.1.0
```

Nota: `analyzer` se mantiene en `^12.0.0` mientras `flutter_test` pinie `test_api: 0.7.11`. Actualizar a `^13.0.0` cuando Flutter lo permita.

---

## Fronteras arquitectónicas

```
contracts/     ← sin imports externos (solo dart:core, dart:convert)
config/        ← depende de contracts/
core/          ← depende de contracts/ y config/
analyzer.dart  ← depende de core/ y config/
cli/           ← depende de analyzer.dart y config/
bin/           ← depende de cli/
```

Ninguna capa importa hacia arriba. Tests pueden importar cualquier capa.

---

## Tests

Los 9 archivos de test de `alea-flow` se migran a `test/core/`:

- `code_graph_builder_test.dart`
- `code_graph_resolver_test.dart`
- `code_graph_wiring_test.dart`
- `code_graph_query_test.dart`
- `graph_files_test.dart`
- `glob_match_test.dart`
- `dogfood_smoke_test.dart`
- `resolver_dogfood_smoke_test.dart`
- `wiring_dogfood_smoke_test.dart`

Se actualizan los imports. Se añade un test de smoke sobre el propio paquete `dart_source_graph`.
