import 'dart:io';

import 'package:dart_source_graph/src/config/source_graph_config.dart';
import 'package:dart_source_graph/src/core/files.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('collectDartFiles is opt-out: gathers ALL of lib/ (incl. dirs outside '
      'declared layers), minus graph.exclude defaults, deduped + sorted', () {
    final root = Directory.systemTemp.createTempSync('aflow_files_');
    addTearDown(() => root.deleteSync(recursive: true));
    File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('name: demo\n');

    // Dentro de una capa declarada:
    File(p.join(root.path, 'lib/src/domain/a.dart'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('class A {}\n');
    // FUERA de cualquier capa declarada (feature-first) — igual debe recolectarse:
    File(p.join(root.path, 'lib/src/feature/login/login_controller.dart'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('class LoginController {}\n');
    // Código generado — excluido por el glob **/*.g.dart por defecto:
    File(
      p.join(root.path, 'lib/src/feature/login/login.g.dart'),
    ).writeAsStringSync('// generated\n');

    final files = collectDartFiles(
      root.path,
      const SourceGraphConfig(),
    ).map((f) => p.relative(f, from: root.path).replaceAll(r'\', '/')).toList();

    expect(files, contains('lib/src/domain/a.dart'));
    expect(
      files,
      contains('lib/src/feature/login/login_controller.dart'),
      reason: 'opt-out: code outside declared layers is still collected',
    );
    expect(
      files,
      isNot(contains('lib/src/feature/login/login.g.dart')),
      reason: 'default exclude **/*.g.dart drops generated code',
    );
    expect(files.length, 2);
    expect(files, equals([...files]..sort())); // sorted
  });
}
