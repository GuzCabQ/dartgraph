# dart_source_graph

[![pub.dev](https://img.shields.io/pub/v/dart_source_graph.svg)](https://pub.dev/packages/dart_source_graph)
[![pub points](https://img.shields.io/pub/points/dart_source_graph)](https://pub.dev/packages/dart_source_graph/score)
[![License: BSD-3](https://img.shields.io/badge/license-BSD--3-blue.svg)](https://opensource.org/licenses/BSD-3-Clause)

**The dependency graph your AI can trust.**

`dart_source_graph` statically analyzes your Dart/Flutter source and produces a compact, deterministic `graph.json`: every file, class, import, inheritance link, and semantic role (Widget, Notifier, Bloc…), each edge tagged with how confidently it was derived. Feed it to your AI, query it from CI, or explore it visually — without touching a single source file.

**[→ Live demo: dart_source_graph analyzing itself](https://guzcabq.github.io/dartgraph/doc/graph.html)**

![dart_source_graph HTML viewer — interactive architecture map](https://raw.githubusercontent.com/GuzCabQ/dartgraph/main/doc/viewer.png)

---

## Why dart_source_graph?

Every time an AI assistant starts working with your codebase, it reads files to understand what depends on what — consuming context budget before doing any real work. `dart_source_graph` solves this once, upfront: a single `dart_source_graph build` produces three artifacts your AI (or your CI) can reuse across every session.

```text
graph.json        ← structured graph, queryable in milliseconds
graph.html        ← interactive visual map of your architecture
GRAPH_REPORT.md   ← compact Markdown summary ready for AI context windows
```

**What makes it different:**

- **Honest about uncertainty.** Every edge is tagged `extracted` (from AST), `inferred` (resolved), or `ambiguous` (unconfirmed). When a relationship cannot be established with confidence, it is marked — never silently promoted. Your AI gets reliable data or a clear signal to be cautious, never a guess dressed as a fact.

- **Read-only.** `dart_source_graph` never modifies your source files. Analysis happens in a separate artifact — your codebase stays exactly as you left it.

- **Impact analysis.** Ask what transitively depends on any class or file before you change it. `query impact AuthRepository` answers in milliseconds from the prebuilt graph — no re-analysis needed.

- **Semantic roles, zero config.** Automatically identifies `riverpod.notifier`, `flutter.widget`, `bloc.cubit`, and 10+ more from supertype detection — no annotations, no manual tagging.

- **Built as a library.** Every capability is available as a Dart API (`package:dart_source_graph/dart_source_graph.dart`), not just a CLI. Embed it in your own tools, pipelines, or AI integrations.

---

## Install

```shell
# As a CLI tool
dart pub global activate dart_source_graph

# As a library dependency
dart pub add dart_source_graph
```

---

## Who is this for?

- **AI-assisted developers** — You use Claude Code, Cursor, or GitHub Copilot daily and want your assistant to understand your project instantly, without burning context budget on file traversal.
- **Tech leads and architects** — You need to audit dependency boundaries, detect import cycles, and identify over-coupled modules before they become production problems.
- **Tool builders** — You're building a CLI, a pipeline, or an AI integration and need a reliable Dart code intelligence layer you can query programmatically.

---

## Quick start — CLI

```shell
# Build graph + interactive HTML viewer in one command
dart_source_graph build --output graph.json --html

# Architecture report alongside the graph
dart_source_graph report --input graph.json

# Now you have:
#   graph.json          ← machine-readable graph
#   graph.html          ← interactive visual explorer
#   GRAPH_REPORT.md     ← AI-ready markdown report
```

**Explore the result in your browser — no server needed:**

```shell
open graph.html
```

---

## Quick start — Library

```dart
import 'package:dart_source_graph/dart_source_graph.dart';

// Minimal — zero config
final graph = await SourceGraphAnalyzer().analyze('.');
print('${graph.nodes.length} nodes, ${graph.edges.length} edges');

// With architectural layers + semantic type resolution
final graph = await SourceGraphAnalyzer(
  config: SourceGraphConfig(
    layers: [
      LayerConfig(name: 'domain',       paths: ['lib/src/domain/']),
      LayerConfig(name: 'presentation', paths: ['lib/src/presentation/']),
    ],
  ),
).analyze('.', resolve: true);

// Generate the HTML viewer programmatically
import 'package:dart_source_graph/viewer.dart';
writeHtmlViewer(graph: graph, meta: meta, outputDir: './output');
```

---

## CLI reference

| Command | Description |
| --- | --- |
| `build` | Analyze source code → `graph.json`. Add `--html` for the viewer. |
| `view` | Regenerate `graph.html` from an existing `graph.json` (no re-analysis). |
| `query impact <name>` | What transitively depends on this class/file? |
| `query neighbors <name>` | Direct incoming + outgoing edges. |
| `query god-nodes` | Top architectural hubs by connection count. |
| `report` | Generate `GRAPH_REPORT.md` with full architecture audit. |

```shell
dart_source_graph build --project-root . --output graph.json --html --resolve
dart_source_graph report --input graph.json
dart_source_graph query impact AuthRepository -i graph.json
dart_source_graph query god-nodes --limit 10 -i graph.json
dart_source_graph view --graph graph.json --output docs/viewer.html
```

---

## What gets analyzed

### Nodes

| Kind | Example |
| --- | --- |
| `file` | `lib/src/auth/auth_repo.dart` |
| `class` | `AuthRepository` |
| `mixin` | `LoggingMixin` |
| `enum` | `AuthStatus` |
| `method` | `AuthRepository.login` |
| `function` | `buildProviderScope` |

### Edges

| Relation | Detected from |
| --- | --- |
| `imports` / `exports` | Dart directives |
| `extends` / `implements` / `mixes_in` | Class declarations |
| `contains` | Class → method membership |
| `references` | Type usage in signatures (with `--resolve`) |
| `wiring` | DI / route manifest registrations |
| `calls` | Method invocations |

### Semantic roles (auto-detected)

| Supertype | Role tag |
| --- | --- |
| `Notifier`, `AsyncNotifier`, `StreamNotifier` | `riverpod.notifier` |
| `ConsumerWidget`, `HookConsumerWidget` | `riverpod.consumer_widget` |
| `Bloc` / `Cubit` | `bloc.bloc` / `bloc.cubit` |
| `StatelessWidget`, `StatefulWidget` | `flutter.widget` |
| `GetxController` / `GetxService` | `getx.controller` / `getx.service` |
| `ChangeNotifier` | `flutter.change_notifier` |

Extend with `SourceGraphConfig(roleOverrides: {'BaseViewModel': 'mvvm.viewmodel'})`.

---

## Configuration

```dart
SourceGraphConfig(
  // Files to skip (default excludes generated code)
  exclude: ['**/*.g.dart', '**/*.freezed.dart', 'lib/generated/**'],

  // Tag files by architectural layer
  layers: [
    LayerConfig(name: 'domain',          paths: ['lib/src/domain/']),
    LayerConfig(name: 'infrastructure',  paths: ['lib/src/infrastructure/']),
    LayerConfig(name: 'presentation',    paths: ['lib/src/presentation/']),
  ],

  // Detect DI / route registrations
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

---

## The confidence principle

Information is the most critical asset of any system. Its correct flow and governance determine whether a deployment succeeds or fails. Every system must validate the origin of its data — **incorrect data is more destructive to production than the absence of certainty.**

`dart_source_graph` applies this at every edge: rather than guessing, it tags each relationship with how it was derived.

| Level | How it was derived | Trust |
| --- | --- | --- |
| `extracted` | Directly observed in the AST | High — use freely |
| `inferred` | Resolved via the Dart analyzer element model | Medium — reliable for most uses |
| `ambiguous` | Name match only, could not be confirmed | Low — treat with caution |

When a relationship cannot be confidently established, it is marked `ambiguous` — never silently promoted to a higher confidence level. This makes `graph.json` safe to feed directly into AI context windows, CI gates, and architecture tooling: **every consumer knows exactly what it can trust**.

---

## Sample report output

Running `dart_source_graph report` on this package itself produces:

```markdown
# Graph Report — dart_source_graph  (2026-06-01)

## Summary

- 297 nodes · 826 edges · 7 clusters
- Nodes: class(23), enum(3), external(160), file(18), function(29), method(64)
- Edges: calls(602), contains(119), exports(10), extends(10), imports(85)

## God Nodes

1. `CodeGraphBuilder.build`  — 53 edges  (method · lib/src/core/builder.dart:92)
2. `BuildCommand.run`         — 45 edges  (method · lib/src/cli/build_command.dart:71)
3. `CodeGraphResolver.resolve` — 28 edges  (method · lib/src/core/resolver.dart:29)

## Architecture Clusters

| Cluster          | Files | Depends on                                        |
| --- | --- | --- |
| `lib/src/cli`    | 4     | lib/src/config, lib/src/contracts, lib/src/core   |
| `lib/src/core`   | 7     | lib/src/config, lib/src/contracts                 |
| `lib/src/viewer` | 2     | lib/src/contracts                                 |

## Knowledge Gaps

- No isolated or weakly connected nodes detected.
```

---

## graph.json schema

```json
{
  "schema_version": "1.0.0",
  "package": "my_app",
  "inputs_fingerprint": "sha256:...",
  "summary": { "nodes": 297, "edges": 826 },
  "nodes": [
    {
      "id": "class:lib/src/auth/auth_repo.dart#AuthRepository",
      "label": "AuthRepository",
      "kind": "class",
      "file": "lib/src/auth/auth_repo.dart",
      "line": 12,
      "layer": "domain",
      "role": null
    }
  ],
  "edges": [
    {
      "source": "class:lib/src/auth/auth_repo.dart#AuthRepository",
      "target": "class:lib/src/core/base_repo.dart#BaseRepository",
      "relation": "extends",
      "confidence": "inferred",
      "line": 12
    }
  ]
}
```

---

## Integrations

`dart_source_graph` is designed to be consumed by larger tools:

- **Custom AI tools** — import `package:dart_source_graph/viewer.dart` to embed the HTML viewer in your own CLI.
- **CI pipelines** — run `dart_source_graph report` to get a Markdown architecture audit on every PR.

---

## Contributing

Issues and pull requests are welcome. Please open an issue first to discuss significant changes. All contributions must go through a PR — direct pushes to `main` are not accepted.

[→ GitHub repository](https://github.com/GuzCabQ/dartgraph)

---

## License

BSD-3-Clause — see [LICENSE](LICENSE).
