# Arquitectura de dart_source_graph

## Fronteras de capas

Ninguna capa importa hacia arriba. Las dependencias van en una sola dirección:

```
contracts/    ← sin imports externos (solo dart:core, dart:convert)
config/       ← depende de contracts/
core/         ← depende de contracts/ y config/
analyzer.dart ← depende de core/ y config/
cli/          ← depende de analyzer.dart y config/
bin/          ← depende de cli/
tests         ← pueden importar cualquier capa
```

## Por qué la config es opcional

`SourceGraphConfig` no lee ningún archivo externo. No hay acoplamiento a `.yaml`, `.json` ni ninguna convención de proyecto. Sin config, el paquete funciona con defaults sensatos:

- Excluye archivos generados (`*.g.dart`, `*.freezed.dart`)
- No asigna capas (todos los nodos tienen `layer: null`)
- Detecta roles built-in (Widget, Notifier, Bloc, etc.)
- No agrega aristas de wiring

## El principio de confianza

Cada arista del grafo lleva un `GraphConfidence`:

| Nivel | Significado |
|---|---|
| `extracted` | Observado directamente en el AST — máxima confianza |
| `inferred` | Resuelto vía el modelo de elementos del analyzer |
| `ambiguous` | No pudo resolverse — solo nombre, sin nodo destino confirmado |

**Regla:** mejor no tener un dato que tenerlo mal. Si una herencia no pudo resolverse, el edge queda marcado `ambiguous` para que el consumidor (e.g. una IA) sepa que debe tratarlo con cautela.

## Cómo extender

**Añadir capas arquitectónicas:**
```dart
SourceGraphConfig(
  layers: [
    LayerConfig(name: 'core', paths: ['lib/src/core/']),
    LayerConfig(name: 'adapters', paths: ['lib/src/adapters/']),
  ],
)
```

**Detectar registros DI/rutas (wiring):**
```dart
SourceGraphConfig(
  wiring: WiringConfig(rules: [
    WiringRule(
      name: 'services',
      classPattern: '*Service',
      manifestFile: 'lib/src/injector.dart',
      registrationCall: 'registerSingleton',
    ),
  ]),
)
```

**Añadir roles semánticos custom:**
```dart
SourceGraphConfig(
  roleOverrides: {'BaseViewModel': 'mvvm.viewmodel'},
)
```

## Qué NO hace este paquete

- No ejecuta `dart analyze` ni reporta errores de compilación
- No genera código
- No modifica el proyecto analizado
- No requiere Flutter SDK — solo Dart
