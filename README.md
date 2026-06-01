# dart_source_graph

Produce un grafo semántico del código fuente Dart/Flutter para que una IA entienda la estructura del proyecto sin leer cada archivo.

## Principio rector

**Mejor no tener un dato que tenerlo mal.** Cada arista del grafo lleva un nivel de confianza (`extracted` > `inferred` > `ambiguous`). El paquete solo emite lo que puede fundamentar.

## Instalación

```shell
dart pub add dart_source_graph
```

## Uso como librería

```dart
import 'package:dart_source_graph/dart_source_graph.dart';

// Uso mínimo — sin config, cero dependencias externas
final graph = await SourceGraphAnalyzer().analyze('.');

// Con config: capas arquitectónicas + resolución de tipos
final graph = await SourceGraphAnalyzer(
  config: SourceGraphConfig(
    layers: [LayerConfig(name: 'core', paths: ['lib/src/core/'])],
  ),
).analyze('.', resolve: true);
```

## Uso CLI

```shell
dart pub global activate dart_source_graph

# Construir grafo
dart_source_graph build --project-root . --output graph.json

# Construir grafo + visor HTML de una sola vez
dart_source_graph build --project-root . --output graph.json --html

# Consultas
dart_source_graph query impact SourceGraphAnalyzer -i graph.json
dart_source_graph query god-nodes --limit 10 -i graph.json

# Regenerar el visor HTML sin re-analizar el proyecto
dart_source_graph view --graph graph.json
dart_source_graph view --graph graph.json --output docs/graph.html
```

## Visor HTML

`dart_source_graph` puede generar un visor HTML interactivo (`graph.html`) autocontenido — no requiere servidor, funciona desde `file://`.

**Desde el CLI:**

```shell
dart_source_graph build --output graph.json --html
# → graph.json  +  graph.html en el mismo directorio
```

**Desde la API (para integraciones como alea-flow):**

```dart
import 'package:dart_source_graph/dart_source_graph.dart';
import 'package:dart_source_graph/viewer.dart';

final graph = await SourceGraphAnalyzer().analyze('.');
final meta = CodeGraphMeta(
  schemaVersion: '1.0.0',
  package: 'my_app',
  generatedAt: DateTime.now().toUtc().toIso8601String(),
  inputsFingerprint: CodeGraphBuilder.inputsFingerprint('.', []),
  root: '.',
);
writeHtmlViewer(graph: graph, meta: meta, outputDir: './graph');
// → ./graph/graph.html
```

## SourceGraphConfig

| Campo           | Tipo                  | Default                                | Descripción                                        |
| --------------- | --------------------- | -------------------------------------- | -------------------------------------------------- |
| `exclude`       | `List<String>`        | `['**/*.g.dart', '**/*.freezed.dart']` | Globs de archivos a excluir                        |
| `layers`        | `List<LayerConfig>`   | `[]`                                   | Clasificación de archivos por capa arquitectónica  |
| `roleOverrides` | `Map<String, String>` | `{}`                                   | Sobreescribe roles semánticos built-in             |
| `wiring`        | `WiringConfig?`       | `null`                                 | Detecta registros DI/rutas en archivos manifest    |

## Roles detectados automáticamente

| Supertipo                                                        | Rol                              |
| ---------------------------------------------------------------- | -------------------------------- |
| `Notifier`, `AsyncNotifier`, `StreamNotifier`                    | `riverpod.notifier`              |
| `ConsumerWidget`, `ConsumerStatefulWidget`, `HookConsumerWidget` | `riverpod.consumer_widget`       |
| `Bloc`                                                           | `bloc.bloc`                      |
| `Cubit`                                                          | `bloc.cubit`                     |
| `ChangeNotifier`                                                 | `flutter.change_notifier`        |
| `StatelessWidget`, `StatefulWidget`                              | `flutter.widget`                 |
| `State`                                                          | `flutter.state`                  |
| `GetxController`                                                 | `getx.controller`                |
| `GetxService`                                                    | `getx.service`                   |
| `GetView`, `GetWidget`                                           | `getx.view`                      |
| ...                                                              | (extensible vía `roleOverrides`) |

## Formato graph.json

```json
{
  "schema_version": "1.0.0",
  "package": "my_app",
  "generated_at": "2026-05-31T12:00:00.000Z",
  "inputs_fingerprint": "sha256:abc123...",
  "root": "/path/to/project",
  "resolved": true,
  "summary": { "nodes": 142, "edges": 387, "skipped_files": 0 },
  "nodes": [
    { "id": "class:lib/src/core/builder.dart#CodeGraphBuilder",
      "label": "CodeGraphBuilder", "kind": "class",
      "file": "lib/src/core/builder.dart", "line": 54,
      "layer": "core", "role": null }
  ],
  "edges": [
    { "source": "file:lib/src/core/builder.dart",
      "target": "file:lib/src/contracts/code_graph.dart",
      "relation": "imports", "confidence": "extracted", "line": 20 }
  ]
}
```
