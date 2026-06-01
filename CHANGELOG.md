## 0.1.0

Initial release.

- `SourceGraphAnalyzer` — builds a semantic code graph from Dart/Flutter source (AST + optional type resolution)
- `CodeGraphBuilder`, `CodeGraphResolver`, `addWiringEdges`, `CodeGraphQuery` — granular control API
- `SourceGraphConfig` — optional config: layers, role overrides, wiring rules, excludes
- CLI `build` — generates `graph.json` with `--html` flag for interactive HTML viewer
- CLI `view` — regenerates `graph.html` from an existing `graph.json`
- CLI `query` — `impact`, `neighbors`, `god-nodes` subcommands
- CLI `report` — generates `GRAPH_REPORT.md` with god nodes, clusters, cycles, knowledge gaps, and state flow
- `lib/viewer.dart` — public API for embedding the HTML viewer in other tools
