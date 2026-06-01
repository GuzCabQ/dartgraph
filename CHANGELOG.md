## 0.1.2

- Precise call resolution: with `--resolve`, `calls` and `instantiates` edges now resolve to
  the real internal declaration (`extracted`), state-management API calls (`watch`, `read`,
  `put`, …) are flagged as `external` (`inferred`), and the report gains a **State Flow** section.
- Add a `--version` / `-v` flag to the CLI; reads the package version at runtime.
- Bump `analyzer` to `^13.0.0` (latest); drop the obsolete 12.x pin. No API changes required.

## 0.1.1

- Improved README: tagline, "Who is this for?", sample report output, contributing section.
- Added `flutter` to pub.dev topics for better discoverability.
- Fixed dartdoc warning in `LayerConfig.paths`.
- Added interactive viewer screenshot to documentation.

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
