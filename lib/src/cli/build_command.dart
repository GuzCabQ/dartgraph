// lib/src/cli/build_command.dart
//
// Subcomando `build`: genera graph.json desde el AST de Dart.
// Sin acoplamiento a ningún archivo de config externo — la config es opcional vía --config.

import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../analyzer.dart' show inferPackageName;
import '../viewer/html_exporter.dart' show writeHtmlViewerFromJson;
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
        help: 'Directorio raíz del proyecto a analizar.',
      )
      ..addOption(
        'output',
        abbr: 'o',
        help: 'Ruta de salida (graph.json). Por defecto: stdout.',
        valueHelp: 'graph.json',
      )
      ..addOption(
        'config',
        abbr: 'c',
        help: 'Archivo de config YAML opcional.',
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
      )
      ..addFlag(
        'html',
        defaultsTo: false,
        negatable: false,
        help: 'Genera también un visor graph.html junto al JSON de salida.',
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
    final html = res['html'] as bool;

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
          final current = CodeGraphBuilder.inputsFingerprint(
            projectRoot,
            files,
          );
          if (stored != null && stored == current) {
            if (html) {
              stderr.writeln(
                'Grafo al día — sin reconstruir JSON. Regenerando visor HTML.',
              );
              final htmlPath = writeHtmlViewerFromJson(
                jsonString: existing.readAsStringSync(),
                outputDir: p.dirname(target),
              );
              stdout.writeln('Visor:   $htmlPath');
              return 0;
            }
            stderr.writeln(
              'Grafo al día (${files.length} archivos) — sin reconstruir.',
            );
            return 0;
          }
        } catch (_) {
          // Archivo anterior inválido → reconstruir.
        }
      }
    }

    final packageName = inferPackageName(projectRoot);
    final builder = CodeGraphBuilder();
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

    final encoded = const JsonEncoder.withIndent(
      '  ',
    ).convert(graph.toJson(meta: meta));

    if (output == null) {
      stdout.writeln(encoded);
      if (html) {
        final htmlPath = writeHtmlViewerFromJson(
          jsonString: encoded,
          outputDir: './graph',
        );
        stderr.writeln('Visor:   $htmlPath');
      }
      return 0;
    }

    try {
      // Ruta absoluta se usa tal cual; ruta relativa se resuelve bajo projectRoot.
      final target = p.isAbsolute(output)
          ? output
          : p.join(projectRoot, output);
      final file = File(target);
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(encoded);
      stdout.writeln(
        'Escrito: ${graph.nodes.length} nodos / ${graph.edges.length} aristas → $target',
      );
      if (html) {
        final htmlPath = writeHtmlViewerFromJson(
          jsonString: encoded,
          outputDir: p.dirname(target),
        );
        stdout.writeln('Visor:   $htmlPath');
      }
      return 0;
    } on FileSystemException catch (e) {
      stderr.writeln('Error al escribir graph.json: $e');
      return 2;
    }
  }
}

/// Lee [SourceGraphConfig] desde un YAML. Retorna defaults si [configPath] es null.
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
      exclude:
          (yaml['exclude'] as YamlList?)?.cast<String>() ??
          const ['**/*.g.dart', '**/*.freezed.dart'],
      layers: [
        for (final l in (yaml['layers'] as YamlList?) ?? const [])
          LayerConfig(
            name: (l as YamlMap)['name'] as String,
            paths: (l['paths'] as YamlList).cast<String>(),
          ),
      ],
      roleOverrides: {
        for (final e in ((yaml['role_overrides'] as YamlMap?) ?? {}).entries)
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
                    scanPaths:
                        (r['scan_paths'] as YamlList?)?.cast<String>() ??
                        const [],
                  ),
              ],
            ),
    );
  } catch (e) {
    stderr.writeln('Error al leer config: $e');
    exit(2);
  }
}
