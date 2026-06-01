# dart_source_graph — Plan de implementación

> **Para agentes:** SUB-SKILL REQUERIDO: Usa `superpowers:subagent-driven-development` (recomendado) o `superpowers:executing-plans` para implementar este plan tarea por tarea. Los pasos usan sintaxis de checkbox (`- [ ]`) para seguimiento.

**Goal:** Crear el paquete `dart_source_graph` extrayendo y adaptando el sistema de grafos de `alea-flow`, publicable en pub.dev.

**Architecture:** Enfoque B — internals migrados sin cambios de comportamiento, con `SourceGraphAnalyzer` como fachada pública. Contratos puros → config → core → analyzer → CLI, sin dependencias inversas. `SourceGraphConfig` reemplaza `ProjectConfig` en todas las firmas.

**Tech Stack:** Dart SDK ^3.12.0 · `analyzer ^12.0.0` · `crypto ^3.0.7` · `path ^1.9.1` · `args ^2.7.0` · `yaml ^3.1.3` · `test ^1.31.1`

**Fuente:** `/Users/zeref/Documents/Github/alea-flow`  
**Destino:** `/Users/zeref/Documents/Github/dartgraph`

---

## Mapa de archivos

| Origen (alea-flow) | Destino (dart_source_graph) | Tipo de cambio |
|---|---|---|
| — | `pubspec.yaml` | nuevo |
| — | `analysis_options.yaml` | nuevo |
| `lib/src/contracts/code_graph.dart` | `lib/src/contracts/code_graph.dart` | migrar + comentarios ES |
| — | `lib/src/config/source_graph_config.dart` | nuevo (reemplaza GraphConfig de ProjectConfig) |
| `lib/src/core/graph/glob_match.dart` | `lib/src/core/glob_match.dart` | migrar + comentarios ES |
| `lib/src/core/graph/graph_files.dart` | `lib/src/core/files.dart` | migrar: `ProjectConfig` → `SourceGraphConfig` |
| `lib/src/core/graph/code_graph_builder.dart` | `lib/src/core/builder.dart` | migrar: `ProjectConfig` → `SourceGraphConfig`, `LayerConfig` rediseñado |
| `lib/src/core/graph/code_graph_resolver.dart` | `lib/src/core/resolver.dart` | migrar: firma `ProjectConfig` → `SourceGraphConfig` |
| `lib/src/core/graph/code_graph_wiring.dart` | `lib/src/core/wiring.dart` | migrar: `config.architecture.wiring` → `config.wiring` |
| `lib/src/core/graph/code_graph_query.dart` | `lib/src/core/query.dart` | migrar: solo imports + comentarios ES |
| — | `lib/src/analyzer.dart` | nuevo: `SourceGraphAnalyzer` |
| `lib/src/cli/commands/graph_command.dart` | `lib/src/cli/build_command.dart` | reescribir: sin `loadProjectConfig`, agrega `--config` YAML |
| `lib/src/cli/commands/graph_query_command.dart` | `lib/src/cli/query_command.dart` | reescribir: solo impact/neighbors/god-nodes |
| — | `bin/dart_source_graph.dart` | nuevo: entry point CLI |
| — | `lib/dart_source_graph.dart` | nuevo: barrel público |
| `test/core/graph/glob_match_test.dart` | `test/core/glob_match_test.dart` | migrar imports |
| `test/core/graph/graph_files_test.dart` | `test/core/files_test.dart` | migrar: fixtures sin .alea.yaml |
| `test/core/graph/code_graph_builder_test.dart` | `test/core/builder_test.dart` | migrar: fixtures sin .alea.yaml |
| `test/core/graph/code_graph_resolver_test.dart` | `test/core/resolver_test.dart` | migrar: fixtures sin .alea.yaml |
| `test/core/graph/code_graph_wiring_test.dart` | `test/core/wiring_test.dart` | migrar: fixtures sin .alea.yaml |
| `test/core/graph/code_graph_query_test.dart` | `test/core/query_test.dart` | migrar imports |
| `test/core/graph/dogfood_smoke_test.dart` | `test/core/dogfood_smoke_test.dart` | migrar: analiza el propio paquete |
| `test/core/graph/resolver_dogfood_smoke_test.dart` | `test/core/resolver_dogfood_smoke_test.dart` | migrar |
| `test/core/graph/wiring_dogfood_smoke_test.dart` | `test/core/wiring_dogfood_smoke_test.dart` | migrar |
| — | `README.md` | nuevo (español) |
| — | `ARCHITECTURE.md` | nuevo (español) |

---

## Task 1: Scaffolding — pubspec.yaml y archivos de proyecto

**Files:**
- Create: `pubspec.yaml`
- Create: `analysis_options.yaml`

- [ ] **Paso 1: Crear pubspec.yaml**

```yaml
name: dart_source_graph
description: >
  Genera un grafo estructurado y semántico del código fuente Dart/Flutter.
  Diseñado para que una IA (u herramienta de análisis) entienda un proyecto
  sin leer cada archivo: identifica Widgets, Notifiers, Blocs, Controllers,
  relaciones de dependencia y nivel de confianza por cada arista.
version: 0.1.0
repository: https://github.com/GuzCabQ/dartgraph
issue_tracker: https://github.com/GuzCabQ/dartgraph/issues

executables:
  dart_source_graph:

environment:
  sdk: ^3.12.0

dependencies:
  # Fijado en 12.x mientras flutter_test pinie test_api: 0.7.11.
  # Subir a ^13.0.0 cuando Flutter lo permita.
  analyzer: ^12.0.0
  args: ^2.7.0
  crypto: ^3.0.7
  path: ^1.9.1
  yaml: ^3.1.3

dev_dependencies:
  test: ^1.31.1
  lints: ^6.1.0
```

- [ ] **Paso 2: Crear analysis_options.yaml**

```yaml
include: package:lints/recommended.yaml

analyzer:
  exclude:
    - "test/**/fixtures/**"
    - ".dart_tool/**"
  errors:
    avoid_print: ignore
```

- [ ] **Paso 3: Crear estructura de directorios**

```bash
mkdir -p lib/src/contracts
mkdir -p lib/src/config
mkdir -p lib/src/core
mkdir -p lib/src/cli
mkdir -p bin
mkdir -p test/core
```

- [ ] **Paso 4: Crear barrel vacío temporal**

Crea `lib/dart_source_graph.dart` con solo un comentario para que `dart pub get` no falle:

```dart
// Barrel público — se completa en Task 14.
```

- [ ] **Paso 5: Instalar dependencias**

```bash
cd /Users/zeref/Documents/Github/dartgraph
dart pub get
```

Esperado: resolución exitosa, sin errores de versión.

- [ ] **Paso 6: Commit**

```bash
git init
git add pubspec.yaml analysis_options.yaml lib/dart_source_graph.dart analysis_options.yaml
git commit -m "chore: scaffolding inicial del paquete dart_source_graph"
```

---

## Task 2: Contratos — lib/src/contracts/code_graph.dart

**Files:**
- Create: `lib/src/contracts/code_graph.dart`

Este archivo es copia directa de `alea-flow/lib/src/contracts/code_graph.dart` con comentarios traducidos al español y encabezado actualizado. El comportamiento no cambia.

- [ ] **Paso 1: Copiar y traducir**

Crea `lib/src/contracts/code_graph.dart`. Encabezado nuevo:

```dart
// lib/src/contracts/code_graph.dart
//
// Contrato del grafo de código fuente (Code Knowledge Graph).
//
// Tipos de datos puros + (de)serialización. Sin I/O, sin AST, sin crypto.
// Importa solo dart:core y dart:convert — satisface la frontera de pureza.
```

El resto del archivo es idéntico al origen. No modifiques ninguna clase, enum, método o constante. Solo traduce los comentarios `//` y `///`.

- [ ] **Paso 2: Verificar que compila**

```bash
dart analyze lib/src/contracts/code_graph.dart
```

Esperado: sin errores.

- [ ] **Paso 3: Commit**

```bash
git add lib/src/contracts/code_graph.dart
git commit -m "feat: migrar contratos CodeGraph desde alea-flow"
```

---

## Task 3: Config — lib/src/config/source_graph_config.dart

**Files:**
- Create: `lib/src/config/source_graph_config.dart`
- Create: `test/core/config_test.dart`

`SourceGraphConfig` es código nuevo. `LayerConfig` se rediseña: en alea-flow era `Map<String, LayerConfig>` con campos de integridad de capas (`mayImport`, `forbidImports`); aquí es `List<LayerConfig>` con solo `name` y `paths`. `WiringConfig` y `WiringRule` son copia directa de los de alea-flow.

- [ ] **Paso 1: Escribir el test primero**

Crea `test/core/config_test.dart`:

```dart
import 'package:dart_source_graph/dart_source_graph.dart';
import 'package:test/test.dart';

void main() {
  group('SourceGraphConfig — defaults', () {
    test('excluye archivos generados por defecto', () {
      const config = SourceGraphConfig();
      expect(config.exclude, contains('**/*.g.dart'));
      expect(config.exclude, contains('**/*.freezed.dart'));
    });

    test('layers vacío por defecto', () {
      const config = SourceGraphConfig();
      expect(config.layers, isEmpty);
    });

    test('roleOverrides vacío por defecto', () {
      const config = SourceGraphConfig();
      expect(config.roleOverrides, isEmpty);
    });

    test('wiring null por defecto', () {
      const config = SourceGraphConfig();
      expect(config.wiring, isNull);
    });
  });

  group('LayerConfig', () {
    test('name y paths se asignan correctamente', () {
      const layer = LayerConfig(name: 'core', paths: ['lib/src/core/']);
      expect(layer.name, 'core');
      expect(layer.paths, ['lib/src/core/']);
    });
  });

  group('WiringConfig', () {
    test('rules vacío por defecto', () {
      const wiring = WiringConfig();
      expect(wiring.rules, isEmpty);
    });

    test('WiringRule guarda todos sus campos', () {
      const rule = WiringRule(
        name: 'services',
        classPattern: '*Service',
        manifestFile: 'lib/injector.dart',
        registrationCall: 'registerSingleton',
      );
      expect(rule.name, 'services');
      expect(rule.classPattern, '*Service');
      expect(rule.manifestFile, 'lib/injector.dart');
      expect(rule.registrationCall, 'registerSingleton');
      expect(rule.scanPaths, isEmpty);
    });
  });
}
```

- [ ] **Paso 2: Correr el test — debe fallar**

```bash
dart test test/core/config_test.dart
```

Esperado: error de compilación (`SourceGraphConfig` no existe).

- [ ] **Paso 3: Implementar source_graph_config.dart**

Crea `lib/src/config/source_graph_config.dart`:

```dart
// lib/src/config/source_graph_config.dart
//
// Configuración opcional para SourceGraphAnalyzer.
// Sin dependencia de ningún archivo externo (.alea.yaml u otro).
// Todos los campos tienen defaults sensatos — el paquete funciona sin config.

/// Clasifica archivos de la capa arquitectónica por patrón de ruta.
class LayerConfig {
  /// Nombre de la capa, e.g. "core", "adapters", "presentation".
  final String name;

  /// Lista de patrones glob o prefijos de directorio.
  /// Ejemplo: ['lib/src/core/', 'lib/src/domain/**'].
  final List<String> paths;

  const LayerConfig({required this.name, required this.paths});
}

/// Regla de wiring: detecta qué clases se registran en un archivo de manifiesto DI/rutas.
class WiringRule {
  /// Etiqueta legible, usada en mensajes y IDs de regla.
  final String name;

  /// Patrón glob para nombres de clase. Soporta `*` al inicio, final o ambos.
  final String classPattern;

  /// Ruta relativa al proyecto del archivo de manifiesto. Ej: 'lib/src/injector.dart'.
  final String manifestFile;

  /// Nombre exacto de la función/constructor que registra la clase.
  /// Acepta nombre simple ('registerSingleton') o dotted ('Get.put').
  final String registrationCall;

  /// Directorios a escanear (relativos al proyecto). Vacío = todos los declarados en layers.
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

  /// Configuración de wiring. `null` = no-op (no se detectan registros DI).
  final WiringConfig? wiring;

  const SourceGraphConfig({
    this.exclude = const ['**/*.g.dart', '**/*.freezed.dart'],
    this.layers = const [],
    this.roleOverrides = const {},
    this.wiring,
  });
}
```

- [ ] **Paso 4: Actualizar barrel (temporal)**

Agrega al `lib/dart_source_graph.dart`:

```dart
export 'src/config/source_graph_config.dart';
```

- [ ] **Paso 5: Correr el test — debe pasar**

```bash
dart test test/core/config_test.dart
```

Esperado: todos los tests en verde.

- [ ] **Paso 6: Commit**

```bash
git add lib/src/config/source_graph_config.dart test/core/config_test.dart lib/dart_source_graph.dart
git commit -m "feat: SourceGraphConfig, LayerConfig, WiringConfig, WiringRule"
```

---

## Task 4: Utilidades core — glob_match.dart + files.dart

**Files:**
- Create: `lib/src/core/glob_match.dart`
- Create: `lib/src/core/files.dart`
- Create: `test/core/glob_match_test.dart`
- Create: `test/core/files_test.dart`

- [ ] **Paso 1: Migrar glob_match.dart**

Copia `alea-flow/lib/src/core/graph/glob_match.dart` a `lib/src/core/glob_match.dart`. Actualiza el encabezado:

```dart
// lib/src/core/glob_match.dart
//
// Coincidencia de patrones glob para filtrar archivos Dart.
// Sin dependencias externas — solo dart:core.
```

No hay otros cambios (no importa nada del proyecto).

- [ ] **Paso 2: Migrar glob_match_test.dart**

Copia `alea-flow/test/core/graph/glob_match_test.dart` a `test/core/glob_match_test.dart`. Cambia el import:

```dart
// ANTES:
import 'package:alea_flow/src/core/graph/glob_match.dart';
// DESPUÉS:
import 'package:dart_source_graph/src/core/glob_match.dart';
```

- [ ] **Paso 3: Migrar files.dart**

Copia `alea-flow/lib/src/core/graph/graph_files.dart` a `lib/src/core/files.dart`.

Reemplaza los imports:

```dart
// ANTES:
import '../../contracts/project_config.dart';
import 'glob_match.dart';
// DESPUÉS:
import '../config/source_graph_config.dart';
import 'glob_match.dart';
```

Actualiza la firma de la función:

```dart
// ANTES:
List<String> collectDartFiles(String projectRoot, ProjectConfig config) {
  // ...
  final exclude = config.graph.exclude;
// DESPUÉS:
List<String> collectDartFiles(String projectRoot, SourceGraphConfig config) {
  // ...
  final exclude = config.exclude;
```

Actualiza el encabezado:

```dart
// lib/src/core/files.dart
//
// Recolección compartida de archivos .dart para el productor y consumidor del grafo.
// Modelo opt-out: todos los .dart bajo lib/ menos los que coincidan con config.exclude.
// Deduplicado y ordenado. Productor y consumidor deben llamar a la misma función
// para que inputs_fingerprint sea consistente.
```

- [ ] **Paso 4: Migrar files_test.dart**

Copia `alea-flow/test/core/graph/graph_files_test.dart` a `test/core/files_test.dart`.

Reemplaza los imports:

```dart
// ANTES:
import 'package:alea_flow/src/contracts/project_config.dart';
import 'package:alea_flow/src/core/config/loader.dart';
import 'package:alea_flow/src/core/graph/graph_files.dart';
// DESPUÉS:
import 'package:dart_source_graph/src/config/source_graph_config.dart';
import 'package:dart_source_graph/src/core/files.dart';
```

Reemplaza el helper de config que usaba `loadProjectConfig` con `SourceGraphConfig` directo:

```dart
// ANTES:
ProjectConfig _config(String root) => loadProjectConfig(root);
// y el fixture .alea.yaml completo
// DESPUÉS:
// No se necesita helper — usa SourceGraphConfig directamente en cada test:
// collectDartFiles(root.path, const SourceGraphConfig())
```

Actualiza cada llamada `_config(root.path)` por `const SourceGraphConfig()` (o la config específica que el test necesite).

- [ ] **Paso 5: Correr tests**

```bash
dart test test/core/glob_match_test.dart test/core/files_test.dart
```

Esperado: todos en verde.

- [ ] **Paso 6: Commit**

```bash
git add lib/src/core/glob_match.dart lib/src/core/files.dart test/core/glob_match_test.dart test/core/files_test.dart
git commit -m "feat: migrar glob_match y collectDartFiles"
```

---

## Task 5: Core builder — lib/src/core/builder.dart

**Files:**
- Create: `lib/src/core/builder.dart`
- Create: `test/core/builder_test.dart`

Este es el cambio más complejo: `LayerConfig` se rediseña de `Map<String, LayerConfig>` a `List<LayerConfig>`, lo que requiere actualizar `_layerOf`.

- [ ] **Paso 1: Migrar builder_test.dart**

Copia `alea-flow/test/core/graph/code_graph_builder_test.dart` a `test/core/builder_test.dart`.

Reemplaza los imports:

```dart
// ANTES:
import 'package:alea_flow/src/contracts/code_graph.dart';
import 'package:alea_flow/src/contracts/project_config.dart';
import 'package:alea_flow/src/core/config/loader.dart';
import 'package:alea_flow/src/core/graph/code_graph_builder.dart';
// DESPUÉS:
import 'package:dart_source_graph/src/config/source_graph_config.dart';
import 'package:dart_source_graph/src/contracts/code_graph.dart';
import 'package:dart_source_graph/src/core/builder.dart';
```

Elimina la función `_config` y el fixture `_alea` completo. Reemplaza todas las llamadas:

```dart
// ANTES:
builder.build(projectRoot: root.path, filePaths: files, config: _config(root.path))
// DESPUÉS:
builder.build(projectRoot: root.path, filePaths: files, config: const SourceGraphConfig())
```

Para tests que declaran capas específicas:

```dart
// ANTES (usaba _alea con layers: {domain: paths: [lib/src/domain/]}):
// DESPUÉS:
builder.build(
  projectRoot: root.path,
  filePaths: files,
  config: const SourceGraphConfig(
    layers: [
      LayerConfig(name: 'domain', paths: ['lib/src/domain/']),
      LayerConfig(name: 'presentation', paths: ['lib/src/presentation/']),
    ],
  ),
)
```

- [ ] **Paso 2: Migrar builder.dart**

Copia `alea-flow/lib/src/core/graph/code_graph_builder.dart` a `lib/src/core/builder.dart`.

Reemplaza el import de project_config:

```dart
// ANTES:
import '../../contracts/project_config.dart';
import 'glob_match.dart';
// DESPUÉS:
import '../config/source_graph_config.dart';
import 'glob_match.dart';
```

Actualiza la firma de `build()`:

```dart
// ANTES:
CodeGraph build({
  required String projectRoot,
  required List<String> filePaths,
  required ProjectConfig config,
  String? packageName,
}) {
  // ...
  final layers = config.architecture.layers;
  // ...
  role: _roleFor(supers, config.graph.roleOverrides),
// DESPUÉS:
CodeGraph build({
  required String projectRoot,
  required List<String> filePaths,
  required SourceGraphConfig config,
  String? packageName,
}) {
  // ...
  final layers = config.layers;
  // ...
  role: _roleFor(supers, config.roleOverrides),
```

Actualiza `_layerOf` para trabajar con `List<LayerConfig>`:

```dart
// ANTES:
String? _layerOf(String relativePath, Map<String, LayerConfig> layers) {
  final rel = relativePath.replaceAll(r'\', '/');
  for (final entry in layers.entries) {
    for (final layerPath in entry.value.paths) {
      final lp = layerPath.replaceAll(r'\', '/');
      final pattern = (lp.contains('*') || lp.endsWith('/')) ? lp : '$lp/';
      if (globMatch(pattern, rel)) return entry.key;
    }
  }
  return null;
}
// DESPUÉS:
String? _layerOf(String relativePath, List<LayerConfig> layers) {
  final rel = relativePath.replaceAll(r'\', '/');
  for (final layer in layers) {
    for (final layerPath in layer.paths) {
      final lp = layerPath.replaceAll(r'\', '/');
      final pattern = (lp.contains('*') || lp.endsWith('/')) ? lp : '$lp/';
      if (globMatch(pattern, rel)) return layer.name;
    }
  }
  return null;
}
```

Actualiza el encabezado y traduce los comentarios al español.

- [ ] **Paso 3: Correr tests**

```bash
dart test test/core/builder_test.dart
```

Esperado: todos en verde.

- [ ] **Paso 4: Commit**

```bash
git add lib/src/core/builder.dart test/core/builder_test.dart
git commit -m "feat: migrar CodeGraphBuilder con SourceGraphConfig y LayerConfig rediseñado"
```

---

## Task 6: Core resolver — lib/src/core/resolver.dart

**Files:**
- Create: `lib/src/core/resolver.dart`
- Create: `test/core/resolver_test.dart`

El resolver no usa `config` funcionalmente (está reservado para slice futura) — el cambio es solo en la firma.

- [ ] **Paso 1: Migrar resolver_test.dart**

Copia `alea-flow/test/core/graph/code_graph_resolver_test.dart` a `test/core/resolver_test.dart`.

Reemplaza imports:

```dart
// ANTES:
import 'package:alea_flow/src/contracts/code_graph.dart';
import 'package:alea_flow/src/contracts/project_config.dart';
import 'package:alea_flow/src/core/config/loader.dart';
import 'package:alea_flow/src/core/graph/code_graph_builder.dart';
import 'package:alea_flow/src/core/graph/code_graph_resolver.dart';
import 'package:alea_flow/src/core/graph/graph_files.dart';
// DESPUÉS:
import 'package:dart_source_graph/src/config/source_graph_config.dart';
import 'package:dart_source_graph/src/contracts/code_graph.dart';
import 'package:dart_source_graph/src/core/builder.dart';
import 'package:dart_source_graph/src/core/files.dart';
import 'package:dart_source_graph/src/core/resolver.dart';
```

Elimina `_config()` y el fixture `.alea.yaml`. Reemplaza `_config(root.path)` por `const SourceGraphConfig()` en todas las llamadas.

- [ ] **Paso 2: Migrar resolver.dart**

Copia `alea-flow/lib/src/core/graph/code_graph_resolver.dart` a `lib/src/core/resolver.dart`.

Reemplaza el import:

```dart
// ANTES:
import '../../contracts/project_config.dart';
// DESPUÉS:
import '../config/source_graph_config.dart';
```

Actualiza la firma de `resolve()`:

```dart
// ANTES:
Future<CodeGraph> resolve(
  CodeGraph base, {
  required String projectRoot,
  required List<String> filePaths,
  required ProjectConfig config,
}) async {
// DESPUÉS:
Future<CodeGraph> resolve(
  CodeGraph base, {
  required String projectRoot,
  required List<String> filePaths,
  required SourceGraphConfig config,
}) async {
```

Traduce comentarios al español. Actualiza el encabezado.

- [ ] **Paso 3: Correr tests**

```bash
dart test test/core/resolver_test.dart
```

Esperado: todos en verde.

- [ ] **Paso 4: Commit**

```bash
git add lib/src/core/resolver.dart test/core/resolver_test.dart
git commit -m "feat: migrar CodeGraphResolver con SourceGraphConfig"
```

---

## Task 7: Core wiring — lib/src/core/wiring.dart

**Files:**
- Create: `lib/src/core/wiring.dart`
- Create: `test/core/wiring_test.dart`

- [ ] **Paso 1: Migrar wiring_test.dart**

Copia `alea-flow/test/core/graph/code_graph_wiring_test.dart` a `test/core/wiring_test.dart`.

Reemplaza imports:

```dart
// ANTES:
import 'package:alea_flow/src/contracts/code_graph.dart';
import 'package:alea_flow/src/contracts/project_config.dart';
import 'package:alea_flow/src/core/config/loader.dart';
import 'package:alea_flow/src/core/graph/code_graph_builder.dart';
import 'package:alea_flow/src/core/graph/code_graph_wiring.dart';
// DESPUÉS:
import 'package:dart_source_graph/src/config/source_graph_config.dart';
import 'package:dart_source_graph/src/contracts/code_graph.dart';
import 'package:dart_source_graph/src/core/builder.dart';
import 'package:dart_source_graph/src/core/wiring.dart';
```

Los tests que instancian `WiringConfig`/`WiringRule` — estos tipos ahora vienen de `source_graph_config.dart`. Las firmas son idénticas a las de `alea-flow/lib/src/contracts/project_config.dart`, así que solo cambia el import.

Elimina `_config()`, el fixture `.alea.yaml` y `loadProjectConfig`. Construye `SourceGraphConfig` directamente con `WiringConfig`:

```dart
// ANTES:
final config = _config(root.path); // cargaba el .alea.yaml con wiring rules
// DESPUÉS:
const config = SourceGraphConfig(
  wiring: WiringConfig(rules: [
    WiringRule(
      name: 'services',
      classPattern: '*Service',
      manifestFile: 'lib/src/injector.dart',
      registrationCall: 'registerSingleton',
    ),
  ]),
);
```

- [ ] **Paso 2: Migrar wiring.dart**

Copia `alea-flow/lib/src/core/graph/code_graph_wiring.dart` a `lib/src/core/wiring.dart`.

Reemplaza imports:

```dart
// ANTES:
import '../../contracts/project_config.dart';
// DESPUÉS:
import '../config/source_graph_config.dart';
```

Actualiza la firma de `addWiringEdges`:

```dart
// ANTES:
CodeGraph addWiringEdges(
  CodeGraph base, {
  required String projectRoot,
  required ProjectConfig config,
}) {
  final wiring = config.architecture.wiring;
// DESPUÉS:
CodeGraph addWiringEdges(
  CodeGraph base, {
  required String projectRoot,
  required SourceGraphConfig config,
}) {
  final wiring = config.wiring;
```

Traduce comentarios al español. Actualiza el encabezado.

- [ ] **Paso 3: Correr tests**

```bash
dart test test/core/wiring_test.dart
```

Esperado: todos en verde.

- [ ] **Paso 4: Commit**

```bash
git add lib/src/core/wiring.dart test/core/wiring_test.dart
git commit -m "feat: migrar addWiringEdges con SourceGraphConfig"
```

---

## Task 8: Core query — lib/src/core/query.dart

**Files:**
- Create: `lib/src/core/query.dart`
- Create: `test/core/query_test.dart`

- [ ] **Paso 1: Migrar query_test.dart**

Copia `alea-flow/test/core/graph/code_graph_query_test.dart` a `test/core/query_test.dart`.

Reemplaza imports:

```dart
// ANTES:
import 'package:alea_flow/src/contracts/code_graph.dart';
import 'package:alea_flow/src/core/graph/code_graph_query.dart';
// DESPUÉS:
import 'package:dart_source_graph/src/contracts/code_graph.dart';
import 'package:dart_source_graph/src/core/query.dart';
```

No hay cambios de `ProjectConfig` — `CodeGraphQuery` no recibe config.

- [ ] **Paso 2: Migrar query.dart**

Copia `alea-flow/lib/src/core/graph/code_graph_query.dart` a `lib/src/core/query.dart`.

Solo actualiza el encabezado y traduce comentarios al español. No hay imports de `project_config`.

- [ ] **Paso 3: Correr tests**

```bash
dart test test/core/query_test.dart
```

Esperado: todos en verde.

- [ ] **Paso 4: Commit**

```bash
git add lib/src/core/query.dart test/core/query_test.dart
git commit -m "feat: migrar CodeGraphQuery"
```

---

## Task 9: Smoke tests

**Files:**
- Create: `test/core/dogfood_smoke_test.dart`
- Create: `test/core/resolver_dogfood_smoke_test.dart`
- Create: `test/core/wiring_dogfood_smoke_test.dart`

Estos tests analizan el propio paquete como fixture — verifican que el grafo se puede construir sobre código Dart real.

- [ ] **Paso 1: Migrar dogfood_smoke_test.dart**

Copia `alea-flow/test/core/graph/dogfood_smoke_test.dart` a `test/core/dogfood_smoke_test.dart`.

Reemplaza imports:

```dart
// ANTES:
import 'package:alea_flow/src/...';
// DESPUÉS:
import 'package:dart_source_graph/src/...';
```

En el test, la ruta del proyecto apunta a `dart_source_graph` en lugar de `alea_flow`. Si el test hace referencia a `'alea_flow'` como nombre de paquete esperado, actualízalo a `'dart_source_graph'`.

- [ ] **Paso 2: Migrar resolver_dogfood_smoke_test.dart**

Copia y adapta igual que el paso anterior: imports + nombre de paquete.

- [ ] **Paso 3: Migrar wiring_dogfood_smoke_test.dart**

Copia y adapta. Si el test usa `WiringConfig` con reglas hardcodeadas de alea-flow, reemplaza por reglas vacías (`const SourceGraphConfig()`) o elimina el test de wiring (ya que dart_source_graph no tiene manifests DI propios).

- [ ] **Paso 4: Correr todos los tests**

```bash
dart test
```

Esperado: todos en verde, incluyendo los smoke tests.

- [ ] **Paso 5: Commit**

```bash
git add test/core/dogfood_smoke_test.dart test/core/resolver_dogfood_smoke_test.dart test/core/wiring_dogfood_smoke_test.dart
git commit -m "feat: migrar smoke tests (dogfood sobre el propio paquete)"
```

---

## Task 10: Fachada — lib/src/analyzer.dart

**Files:**
- Create: `lib/src/analyzer.dart`
- Create: `test/core/analyzer_test.dart`

- [ ] **Paso 1: Escribir el test primero**

Crea `test/core/analyzer_test.dart`:

```dart
import 'dart:io';

import 'package:dart_source_graph/dart_source_graph.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

Directory _fixture(Map<String, String> files) {
  final root = Directory.systemTemp.createTempSync('dsg_analyzer_');
  files.forEach((rel, content) {
    final f = File(p.join(root.path, rel));
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(content);
  });
  return root;
}

void main() {
  group('SourceGraphAnalyzer', () {
    test('produce grafo con nodos y aristas desde código Dart', () async {
      final root = _fixture({
        'pubspec.yaml': 'name: demo\nenvironment:\n  sdk: ^3.0.0\n',
        'lib/a.dart': 'class A {}',
        'lib/b.dart': "import 'a.dart';\nclass B extends A {}",
      });

      final analyzer = const SourceGraphAnalyzer();
      final graph = await analyzer.analyze(root.path);

      expect(graph.nodes, isNotEmpty);
      expect(
        graph.nodes.any((n) => n.label == 'a.dart'),
        isTrue,
        reason: 'debe incluir nodo de archivo a.dart',
      );
      expect(
        graph.edges.any((e) => e.relation == GraphRelation.imports),
        isTrue,
        reason: 'debe incluir arista de importación',
      );

      root.deleteSync(recursive: true);
    });

    test('config sin layers produce nodos con layer null', () async {
      final root = _fixture({
        'pubspec.yaml': 'name: demo\nenvironment:\n  sdk: ^3.0.0\n',
        'lib/x.dart': 'class X {}',
      });

      final graph = await const SourceGraphAnalyzer().analyze(root.path);
      expect(graph.nodes.every((n) => n.layer == null), isTrue);

      root.deleteSync(recursive: true);
    });

    test('LayerConfig asigna layer a nodos que coinciden', () async {
      final root = _fixture({
        'pubspec.yaml': 'name: demo\nenvironment:\n  sdk: ^3.0.0\n',
        'lib/core/service.dart': 'class MyService {}',
      });

      const config = SourceGraphConfig(
        layers: [LayerConfig(name: 'core', paths: ['lib/core/'])],
      );
      final graph = await SourceGraphAnalyzer(config: config).analyze(root.path);
      final fileNode = graph.nodes.firstWhere((n) => n.label == 'service.dart');
      expect(fileNode.layer, 'core');

      root.deleteSync(recursive: true);
    });
  });
}
```

- [ ] **Paso 2: Correr el test — debe fallar**

```bash
dart test test/core/analyzer_test.dart
```

Esperado: error de compilación (`SourceGraphAnalyzer` no existe).

- [ ] **Paso 3: Implementar analyzer.dart**

Crea `lib/src/analyzer.dart`:

```dart
// lib/src/analyzer.dart
//
// Fachada principal del paquete. Orquesta los tres pasos internos:
// build → resolve → wiring en un solo método asíncrono.
// Los internals (CodeGraphBuilder, CodeGraphResolver, etc.) siguen
// exportados para quien necesite control granular.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'config/source_graph_config.dart';
import 'contracts/code_graph.dart';
import 'core/builder.dart';
import 'core/files.dart';
import 'core/resolver.dart';
import 'core/wiring.dart';

/// Fachada que orquesta build → resolve → wiring en una sola llamada.
///
/// Uso mínimo (sin config, sin resolución semántica):
/// ```dart
/// final graph = await SourceGraphAnalyzer().analyze('.');
/// ```
///
/// Uso completo:
/// ```dart
/// final graph = await SourceGraphAnalyzer(
///   config: SourceGraphConfig(
///     layers: [LayerConfig(name: 'core', paths: ['lib/src/core/'])],
///   ),
/// ).analyze('.', resolve: true, wiring: true);
/// ```
class SourceGraphAnalyzer {
  final SourceGraphConfig config;

  const SourceGraphAnalyzer({this.config = const SourceGraphConfig()});

  /// Analiza el proyecto en [projectRoot] y retorna su grafo de código.
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
    final pkg = packageName ?? _inferPackageName(root);

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

  /// Lee el nombre del paquete desde pubspec.yaml. Retorna null si falla.
  static String? _inferPackageName(String projectRoot) {
    try {
      final pubspec = File(p.join(projectRoot, 'pubspec.yaml'));
      if (!pubspec.existsSync()) return null;
      final yaml = loadYaml(pubspec.readAsStringSync()) as YamlMap;
      return yaml['name'] as String?;
    } catch (_) {
      return null;
    }
  }
}
```

- [ ] **Paso 4: Correr el test — debe pasar**

```bash
dart test test/core/analyzer_test.dart
```

Esperado: todos en verde.

- [ ] **Paso 5: Commit**

```bash
git add lib/src/analyzer.dart test/core/analyzer_test.dart
git commit -m "feat: SourceGraphAnalyzer — fachada build→resolve→wiring"
```

---

## Task 11: CLI build — lib/src/cli/build_command.dart

**Files:**
- Create: `lib/src/cli/build_command.dart`

Adaptado de `graph_command.dart`. Diferencias clave: sin `loadProjectConfig`, agrega `--config` para YAML opcional.

- [ ] **Paso 1: Crear lib/src/cli/build_command.dart**

```dart
// lib/src/cli/build_command.dart
//
// Subcomando `build`: genera graph.json desde el AST de Dart.
// Sin acoplamiento a .alea.yaml — la config es opcional vía --config.

import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../analyzer.dart';
import '../config/source_graph_config.dart';
import '../contracts/code_graph.dart';
import '../core/builder.dart';
import '../core/files.dart';
import '../core/resolver.dart';
import '../core/wiring.dart';

class BuildCommand extends Command<int> {
  BuildCommand() {
    argParser
      ..addOption(
        'project-root',
        abbr: 'r',
        defaultsTo: '.',
        help: 'Directorio raíz del proyecto Dart/Flutter a analizar.',
      )
      ..addOption(
        'output',
        abbr: 'o',
        help: 'Ruta de salida para graph.json. Por defecto: stdout.',
        valueHelp: 'graph.json',
      )
      ..addOption(
        'config',
        abbr: 'c',
        help: 'Ruta al archivo de config YAML (opcional).',
        valueHelp: 'dart_source_graph.yaml',
      )
      ..addFlag(
        'resolve',
        defaultsTo: false,
        negatable: false,
        help: 'Resolución semántica (más lento, requiere pub get).',
      )
      ..addFlag(
        'ensure-fresh',
        defaultsTo: false,
        negatable: false,
        help: 'Omite el rebuild si el fingerprint coincide. Requiere --output.',
      );
  }

  @override
  String get name => 'build';

  @override
  String get description =>
      'Genera el grafo de código fuente (graph.json) desde el AST de Dart.';

  @override
  Future<int> run() async {
    final res = argResults!;
    final projectRoot = p.canonicalize(res['project-root'] as String);
    final output = res['output'] as String?;
    final configPath = res['config'] as String?;
    final ensureFresh = res['ensure-fresh'] as bool;
    final resolve = res['resolve'] as bool;

    if (ensureFresh && output == null) {
      stderr.writeln('Error: --ensure-fresh requiere --output.');
      return 64;
    }

    final config = _loadConfig(configPath);
    final files = collectDartFiles(projectRoot, config);

    if (ensureFresh && output != null) {
      final target = p.isAbsolute(output)
          ? output
          : p.join(projectRoot, output);
      final existing = File(target);
      if (existing.existsSync()) {
        try {
          final doc =
              jsonDecode(existing.readAsStringSync()) as Map<String, Object?>;
          final stored = doc['inputs_fingerprint'] as String?;
          final current = CodeGraphBuilder.inputsFingerprint(projectRoot, files);
          if (stored != null && stored == current) {
            stderr.writeln(
              'Grafo al día (${files.length} archivos) — sin reconstruir.',
            );
            return 0;
          }
        } catch (_) {
          // archivo anterior inválido → reconstruir
        }
      }
    }

    final builder = CodeGraphBuilder();
    final packageName = SourceGraphAnalyzer._inferPackageName(projectRoot);
    var graph = builder.build(
      projectRoot: projectRoot,
      filePaths: files,
      config: config,
      packageName: packageName,
    );

    if (config.wiring != null) {
      graph = addWiringEdges(graph, projectRoot: projectRoot, config: config);
    }

    var resolvedFiles = 0;
    var unresolvedFiles = 0;
    if (resolve) {
      final resolver = CodeGraphResolver();
      graph = await resolver.resolve(
        graph,
        projectRoot: projectRoot,
        filePaths: files,
        config: config,
      );
      resolvedFiles = resolver.resolvedFiles;
      unresolvedFiles = resolver.unresolvedFiles;
    }

    final meta = CodeGraphMeta(
      schemaVersion: '1.0.0',
      package: packageName ?? p.basename(projectRoot),
      generatedAt: DateTime.now().toUtc().toIso8601String(),
      inputsFingerprint: CodeGraphBuilder.inputsFingerprint(projectRoot, files),
      root: '.',
      skippedFiles: builder.skippedFiles,
      resolved: resolve,
      resolvedFiles: resolvedFiles,
      unresolvedFiles: unresolvedFiles,
    );

    final encoded = const JsonEncoder.withIndent('  ')
        .convert(graph.toJson(meta: meta));

    if (output == null) {
      stdout.writeln(encoded);
      return 0;
    }

    try {
      final target = p.isAbsolute(output)
          ? output
          : p.join(projectRoot, output);
      final file = File(target);
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(encoded);
      stdout.writeln(
        'Escrito: ${graph.nodes.length} nodos / ${graph.edges.length} aristas → $target',
      );
      return 0;
    } on FileSystemException catch (e) {
      stderr.writeln('Error al escribir graph.json: $e');
      return 2;
    }
  }
}

/// Lee [SourceGraphConfig] desde un archivo YAML. Si [configPath] es null
/// o el archivo no existe, retorna la config por defecto.
SourceGraphConfig _loadConfig(String? configPath) {
  if (configPath == null) return const SourceGraphConfig();
  final file = File(configPath);
  if (!file.existsSync()) {
    stderr.writeln('Error: archivo de config no encontrado: $configPath');
    exit(2);
  }
  try {
    final yaml = loadYaml(file.readAsStringSync()) as YamlMap;
    return SourceGraphConfig(
      exclude: (yaml['exclude'] as YamlList?)?.cast<String>() ??
          const ['**/*.g.dart', '**/*.freezed.dart'],
      layers: [
        for (final l in (yaml['layers'] as YamlList?) ?? const [])
          LayerConfig(
            name: (l as YamlMap)['name'] as String,
            paths: (l['paths'] as YamlList).cast<String>(),
          ),
      ],
      roleOverrides: {
        for (final e
            in ((yaml['role_overrides'] as YamlMap?) ?? {}).entries)
          e.key as String: e.value as String,
      },
      wiring: yaml['wiring'] == null
          ? null
          : WiringConfig(
              rules: [
                for (final r
                    in ((yaml['wiring'] as YamlMap)['rules'] as YamlList?) ??
                        const [])
                  WiringRule(
                    name: (r as YamlMap)['name'] as String,
                    classPattern: r['class_pattern'] as String,
                    manifestFile: r['manifest_file'] as String,
                    registrationCall: r['registration_call'] as String,
                    scanPaths: (r['scan_paths'] as YamlList?)?.cast<String>() ??
                        const [],
                  ),
              ],
            ),
    );
  } catch (e) {
    stderr.writeln('Error al leer el archivo de config: $e');
    exit(2);
  }
}
```

**Nota:** `SourceGraphAnalyzer._inferPackageName` es privado. Muévelo a un helper top-level en `lib/src/core/package_name.dart` o hazlo interno en `build_command.dart` con el mismo cuerpo. La opción más simple: duplícalo inline en el command o expón `inferPackageName` como función package-private.

Para evitar duplicación, en `lib/src/analyzer.dart` cambia `_inferPackageName` a una función top-level interna:

```dart
// En lib/src/analyzer.dart — cambia de método estático a función top-level:
String? inferPackageName(String projectRoot) { ... }
```

Y en `build_command.dart`:

```dart
import '../analyzer.dart' show inferPackageName;
// ...
final packageName = inferPackageName(projectRoot);
```

- [ ] **Paso 2: Verificar que compila**

```bash
dart analyze lib/src/cli/build_command.dart
```

Esperado: sin errores.

- [ ] **Paso 3: Commit**

```bash
git add lib/src/cli/build_command.dart
git commit -m "feat: CLI build_command — genera graph.json sin acoplamiento a .alea.yaml"
```

---

## Task 12: CLI query — lib/src/cli/query_command.dart

**Files:**
- Create: `lib/src/cli/query_command.dart`

Solo incluye: `impact`, `neighbors`, `god-nodes`. Los subcomandos `structure`, `unlayered`, `state-flow` son específicos de alea-flow y no se migran.

La verificación de freshness se simplifica: sin `loadProjectConfig`, usa `collectDartFiles` con `const SourceGraphConfig()`.

- [ ] **Paso 1: Crear lib/src/cli/query_command.dart**

```dart
// lib/src/cli/query_command.dart
//
// Subcomando `query`: consultas read-only sobre un graph.json preexistente.
// Incluye: impact, neighbors, god-nodes.
// Avisa (stderr) si el grafo está desactualizado vs el árbol de archivos.

import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import '../config/source_graph_config.dart';
import '../contracts/code_graph.dart';
import '../core/builder.dart';
import '../core/files.dart';
import '../core/query.dart';

class QueryCommand extends Command<int> {
  QueryCommand() {
    addSubcommand(_ImpactSubcommand());
    addSubcommand(_NeighborsSubcommand());
    addSubcommand(_GodNodesSubcommand());
  }

  @override
  String get name => 'query';

  @override
  String get description =>
      'Consulta un graph.json preexistente: impact, neighbors, god-nodes.';
}

void _addCommonOptions(ArgParser parser) {
  parser
    ..addOption(
      'input',
      abbr: 'i',
      defaultsTo: 'graph.json',
      help: 'Ruta al graph.json preexistente.',
    )
    ..addOption(
      'project-root',
      abbr: 'r',
      defaultsTo: '.',
      help: 'Raíz del proyecto, para la verificación de frescura.',
    )
    ..addOption(
      'format',
      defaultsTo: 'text',
      allowed: ['text', 'json'],
      help: 'Formato de salida.',
    );
}

/// Carga el grafo desde --input y advierte si está desactualizado.
/// Retorna null en error (el caller retorna exit 2).
CodeGraph? _loadGraph(ArgResults res) {
  final projectRoot = p.canonicalize(res['project-root'] as String);
  final rawInput = res['input'] as String;
  final inputPath = p.isAbsolute(rawInput)
      ? rawInput
      : p.join(projectRoot, rawInput);
  final file = File(inputPath);
  if (!file.existsSync()) {
    stderr.writeln('Error: archivo de grafo no encontrado: $inputPath');
    return null;
  }
  final Map<String, Object?> doc;
  try {
    doc = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
  } catch (e) {
    stderr.writeln('Error: no se pudo parsear $inputPath: $e');
    return null;
  }
  // Verificación de frescura sin config externa.
  try {
    final files = collectDartFiles(projectRoot, const SourceGraphConfig());
    final current = CodeGraphBuilder.inputsFingerprint(projectRoot, files);
    final stored = doc['inputs_fingerprint'] as String?;
    if (stored != null && stored != current) {
      stderr.writeln(
        'Aviso: $inputPath está desactualizado — re-ejecuta `dart_source_graph build`.',
      );
    }
  } catch (_) {
    // falla silenciosa — igual responde la query
  }
  try {
    return CodeGraph.fromJson(doc);
  } catch (e) {
    stderr.writeln('Error: $inputPath no es un grafo válido: $e');
    return null;
  }
}

String? _resolveOne(CodeGraphQuery q, String nameOrId) {
  final matches = q.resolveNodes(nameOrId);
  if (matches.isEmpty) {
    stderr.writeln('Error: ningún nodo coincide con "$nameOrId".');
    return null;
  }
  if (matches.length > 1) {
    stderr.writeln('Error: "$nameOrId" es ambiguo; usa un id completo:');
    for (final n in matches) stderr.writeln('  ${n.id}');
    return null;
  }
  return matches.single.id;
}

class _ImpactSubcommand extends Command<int> {
  _ImpactSubcommand() { _addCommonOptions(argParser); }
  @override String get name => 'impact';
  @override String get description =>
      'Qué depende transitivamente de un nodo (radio de blast).';

  @override
  Future<int> run() async {
    final res = argResults!;
    if (res.rest.isEmpty) {
      stderr.writeln('Uso: dart_source_graph query impact <nombre|id>');
      return 64;
    }
    final graph = _loadGraph(res);
    if (graph == null) return 2;
    final q = CodeGraphQuery(graph);
    final id = _resolveOne(q, res.rest.first);
    if (id == null) return 1;
    final impacted = q.impact(id).toList()..sort((a, b) => a.id.compareTo(b.id));
    if (res['format'] == 'json') {
      stdout.writeln(const JsonEncoder.withIndent('  ').convert({
        'target': id,
        'impacted': [for (final n in impacted) n.id],
      }));
    } else {
      stdout.writeln('Impacto de $id — ${impacted.length} nodo(s) dependen de él:');
      for (final n in impacted) {
        stdout.writeln('  ${n.id}${n.file != null ? '  (${n.file})' : ''}');
      }
    }
    return 0;
  }
}

class _NeighborsSubcommand extends Command<int> {
  _NeighborsSubcommand() { _addCommonOptions(argParser); }
  @override String get name => 'neighbors';
  @override String get description => 'Aristas directas (entrada + salida) de un nodo.';

  @override
  Future<int> run() async {
    final res = argResults!;
    if (res.rest.isEmpty) {
      stderr.writeln('Uso: dart_source_graph query neighbors <nombre|id>');
      return 64;
    }
    final graph = _loadGraph(res);
    if (graph == null) return 2;
    final q = CodeGraphQuery(graph);
    final id = _resolveOne(q, res.rest.first);
    if (id == null) return 1;
    final n = q.neighbors(id);
    if (res['format'] == 'json') {
      stdout.writeln(const JsonEncoder.withIndent('  ').convert({
        'node': id,
        'incoming': [for (final e in n.incoming) e.toJson()],
        'outgoing': [for (final e in n.outgoing) e.toJson()],
      }));
    } else {
      stdout.writeln('Vecinos de $id:');
      stdout.writeln('  entrantes (${n.incoming.length}):');
      for (final e in n.incoming) {
        stdout.writeln('    ${e.source}  --${graphRelationToJson(e.relation)}-->');
      }
      stdout.writeln('  salientes (${n.outgoing.length}):');
      for (final e in n.outgoing) {
        stdout.writeln('    --${graphRelationToJson(e.relation)}-->  ${e.target}');
      }
    }
    return 0;
  }
}

class _GodNodesSubcommand extends Command<int> {
  _GodNodesSubcommand() {
    _addCommonOptions(argParser);
    argParser.addOption('limit', defaultsTo: '20', help: 'Cuántos hubs mostrar.');
  }
  @override String get name => 'god-nodes';
  @override String get description => 'Nodos internos con más conexiones (hubs arquitectónicos).';

  @override
  Future<int> run() async {
    final res = argResults!;
    final limit = int.tryParse(res['limit'] as String) ?? 20;
    final graph = _loadGraph(res);
    if (graph == null) return 2;
    final top = CodeGraphQuery(graph).godNodes(limit: limit);
    if (res['format'] == 'json') {
      stdout.writeln(const JsonEncoder.withIndent('  ').convert([
        for (final r in top)
          {'id': r.node.id, 'degree': r.degree, 'file': r.node.file},
      ]));
    } else {
      stdout.writeln('Top $limit hubs por grado:');
      for (final r in top) {
        final loc = r.node.file != null ? '  (${r.node.file})' : '';
        stdout.writeln('  ${r.degree.toString().padLeft(4)}  ${r.node.id}$loc');
      }
    }
    return 0;
  }
}
```

- [ ] **Paso 2: Verificar que compila**

```bash
dart analyze lib/src/cli/query_command.dart
```

Esperado: sin errores.

- [ ] **Paso 3: Commit**

```bash
git add lib/src/cli/query_command.dart
git commit -m "feat: CLI query_command — impact, neighbors, god-nodes"
```

---

## Task 13: Entry point CLI — bin/dart_source_graph.dart

**Files:**
- Create: `bin/dart_source_graph.dart`

- [ ] **Paso 1: Crear bin/dart_source_graph.dart**

```dart
// bin/dart_source_graph.dart
//
// Entry point del ejecutable CLI.
// Uso: dart run dart_source_graph <build|query> [opciones]

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dart_source_graph/src/cli/build_command.dart';
import 'package:dart_source_graph/src/cli/query_command.dart';

Future<void> main(List<String> args) async {
  final runner = CommandRunner<int>(
    'dart_source_graph',
    'Genera y consulta el grafo de código fuente de un proyecto Dart/Flutter.',
  )
    ..addCommand(BuildCommand())
    ..addCommand(QueryCommand());

  try {
    final code = await runner.run(args) ?? 0;
    exit(code);
  } on UsageException catch (e) {
    stderr.writeln(e.message);
    exit(64);
  }
}
```

- [ ] **Paso 2: Probar el CLI sobre el propio paquete**

```bash
dart run bin/dart_source_graph.dart build --project-root . --output /tmp/dsg_self.json
```

Esperado: mensaje "Escrito: N nodos / M aristas → /tmp/dsg_self.json".

```bash
dart run bin/dart_source_graph.dart query impact SourceGraphAnalyzer -i /tmp/dsg_self.json
```

Esperado: lista de nodos que dependen de `SourceGraphAnalyzer`.

- [ ] **Paso 3: Commit**

```bash
git add bin/dart_source_graph.dart
git commit -m "feat: entry point CLI dart_source_graph"
```

---

## Task 14: Barrel público — lib/dart_source_graph.dart

**Files:**
- Modify: `lib/dart_source_graph.dart`

- [ ] **Paso 1: Escribir el barrel completo**

Reemplaza el contenido de `lib/dart_source_graph.dart`:

```dart
// lib/dart_source_graph.dart
//
// API pública del paquete dart_source_graph.
// Importa este archivo para acceder a todos los símbolos públicos.

// Fachada principal
export 'src/analyzer.dart' show SourceGraphAnalyzer;

// Configuración
export 'src/config/source_graph_config.dart'
    show SourceGraphConfig, LayerConfig, WiringConfig, WiringRule;

// Contratos (tipos de datos del grafo)
export 'src/contracts/code_graph.dart';

// Internals exportados para control granular
export 'src/core/builder.dart' show CodeGraphBuilder, kBuiltinRoleMap;
export 'src/core/files.dart' show collectDartFiles;
export 'src/core/query.dart' show CodeGraphQuery;
export 'src/core/resolver.dart' show CodeGraphResolver;
export 'src/core/wiring.dart' show addWiringEdges;
```

- [ ] **Paso 2: Verificar que el barrel compila sin errores**

```bash
dart analyze lib/dart_source_graph.dart
```

Esperado: sin errores.

- [ ] **Paso 3: Correr toda la suite de tests**

```bash
dart test
```

Esperado: todos en verde.

- [ ] **Paso 4: Commit**

```bash
git add lib/dart_source_graph.dart
git commit -m "feat: barrel público — API completa de dart_source_graph"
```

---

## Task 15: Documentación — README.md y ARCHITECTURE.md

**Files:**
- Modify: `README.md`
- Create: `ARCHITECTURE.md`

- [ ] **Paso 1: Escribir README.md**

El README.md debe cubrir en español:
1. Qué es el paquete (propósito + principio rector)
2. Instalación (`dart pub add dart_source_graph`)
3. Uso básico como librería (snippet de `SourceGraphAnalyzer`)
4. Uso básico del CLI (`dart_source_graph build`, `dart_source_graph query impact`)
5. Referencia de `SourceGraphConfig` (tabla de campos con defaults)
6. Roles detectados automáticamente (tabla built-in)
7. Formato del `graph.json` (esquema resumido)

- [ ] **Paso 2: Escribir ARCHITECTURE.md**

El ARCHITECTURE.md debe documentar en español:
1. Fronteras de capas (contracts → config → core → analyzer → cli)
2. Regla: ninguna capa importa hacia arriba
3. Por qué `SourceGraphConfig` no acopla a ningún archivo externo
4. El principio de confianza (`GraphConfidence`): mejor no tener un dato que tenerlo mal
5. Diagrama de dependencias en texto

```
contracts/     ← sin imports externos (solo dart:core, dart:convert)
config/        ← depende de contracts/
core/          ← depende de contracts/ y config/
src/analyzer   ← depende de core/ y config/
src/cli/       ← depende de src/analyzer y config/
bin/           ← depende de src/cli/
```

- [ ] **Paso 3: Commit final**

```bash
git add README.md ARCHITECTURE.md
git commit -m "docs: README.md y ARCHITECTURE.md en español"
```

---

## Self-review del plan

**Cobertura del spec:**
- ✅ pubspec.yaml con nombre `dart_source_graph` → Task 1
- ✅ `SourceGraphConfig`, `LayerConfig`, `WiringConfig`, `WiringRule` → Task 3
- ✅ Todos los archivos core migrados → Tasks 4–8
- ✅ `SourceGraphAnalyzer` (fachada) → Task 10
- ✅ CLI `build` con `--config` opcional → Task 11
- ✅ CLI `query` con impact/neighbors/god-nodes → Task 12
- ✅ Barrel público con todos los símbolos del spec → Task 14
- ✅ Tests migrados y adaptados (sin `.alea.yaml`) → Tasks 4–9
- ✅ Comentarios en español → mencionado en cada tarea de migración
- ✅ README.md y ARCHITECTURE.md en español → Task 15
- ✅ `inferPackageName` como función accesible desde CLI → Task 11 (nota sobre refactor)

**Nota de implementación:** En Task 11 se señala mover `_inferPackageName` de método privado a función top-level `inferPackageName` en `lib/src/analyzer.dart` para que `build_command.dart` pueda importarla. Esto debe resolverse antes de Task 11.
