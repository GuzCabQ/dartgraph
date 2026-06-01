import 'dart:io';

import 'package:dart_source_graph/src/config/source_graph_config.dart';
import 'package:dart_source_graph/src/contracts/code_graph.dart';
import 'package:dart_source_graph/src/core/builder.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Escribe un árbol de proyecto temporal y devuelve su directorio raíz.
Directory _fixture(Map<String, String> files) {
  final root = Directory.systemTemp.createTempSync('dsg_graph_');
  files.forEach((rel, contents) {
    final f = File(p.join(root.path, rel));
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(contents);
  });
  return root;
}

List<String> _dartFiles(String root) => Directory(p.join(root, 'lib'))
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .map((f) => p.normalize(f.absolute.path))
    .toList();

/// Config estándar con las dos capas que usan la mayoría de los tests.
const _configWithLayers = SourceGraphConfig(
  layers: [
    LayerConfig(name: 'domain', paths: ['lib/src/domain/']),
    LayerConfig(name: 'presentation', paths: ['lib/src/presentation/']),
  ],
);

void _declarationsGroup() {
  group('CodeGraphBuilder — declaraciones y herencia', () {
    test('nodos class/mixin/enum + contains + herencia-por-nombre', () async {
      final root = _fixture({
        'pubspec.yaml': 'name: demo\n',
        'lib/src/domain/types.dart': '''
class Base {}
mixin M {}
abstract class Bar {}
mixin M2 implements Bar {}
class Foo extends Base with M implements Bar {}
enum E implements Bar { a, b }
''',
      });
      addTearDown(() => root.deleteSync(recursive: true));

      final graph = CodeGraphBuilder().build(
        projectRoot: root.path,
        filePaths: _dartFiles(root.path),
        config: _configWithLayers,
      );

      const rel = 'lib/src/domain/types.dart';
      final fooId = GraphNodeId.declaration(
        relativePath: rel,
        name: 'Foo',
        kind: GraphNodeKind.class_,
      );
      final mId = GraphNodeId.declaration(
        relativePath: rel,
        name: 'M',
        kind: GraphNodeKind.mixin_,
      );
      final eId = GraphNodeId.declaration(
        relativePath: rel,
        name: 'E',
        kind: GraphNodeKind.enum_,
      );

      expect(
        graph.nodes.any((n) => n.id == fooId && n.kind == GraphNodeKind.class_),
        isTrue,
      );
      expect(
        graph.nodes.any((n) => n.id == mId && n.kind == GraphNodeKind.mixin_),
        isTrue,
      );
      expect(
        graph.nodes.any((n) => n.id == eId && n.kind == GraphNodeKind.enum_),
        isTrue,
      );

      expect(
        graph.edges.any(
          (e) =>
              e.relation == GraphRelation.contains &&
              e.source == GraphNodeId.file(rel) &&
              e.target == fooId,
        ),
        isTrue,
      );

      bool inh(GraphRelation r, String typeName) => graph.edges.any(
        (e) =>
            e.relation == r &&
            e.source == fooId &&
            e.target == GraphNodeId.external(typeName),
      );
      expect(inh(GraphRelation.extends_, 'Base'), isTrue);
      expect(inh(GraphRelation.mixesIn, 'M'), isTrue);
      expect(inh(GraphRelation.implements_, 'Bar'), isTrue);

      // mixin implements -> arista externa
      final m2Id = GraphNodeId.declaration(
        relativePath: rel,
        name: 'M2',
        kind: GraphNodeKind.mixin_,
      );
      expect(
        graph.nodes.any((n) => n.id == m2Id && n.kind == GraphNodeKind.mixin_),
        isTrue,
      );
      expect(
        graph.edges.any(
          (e) =>
              e.relation == GraphRelation.implements_ &&
              e.source == m2Id &&
              e.target == GraphNodeId.external('Bar'),
        ),
        isTrue,
      );
      // enum implements -> arista externa
      expect(
        graph.edges.any(
          (e) =>
              e.relation == GraphRelation.implements_ &&
              e.source == eId &&
              e.target == GraphNodeId.external('Bar'),
        ),
        isTrue,
      );
      // los nodos de declaración llevan una línea basada en 1
      final fooNode = graph.nodes.firstWhere((n) => n.id == fooId);
      expect(fooNode.line, isNotNull);
      expect(fooNode.line! > 0, isTrue);
    });
  });
}

void _fingerprintGroup() {
  group('CodeGraphBuilder.inputsFingerprint', () {
    test('determinístico, independiente del orden, sensible al contenido', () {
      final root = _fixture({
        'pubspec.yaml': 'name: demo\n',
        'lib/a.dart': "class A {}\n",
        'lib/b.dart': "class B {}\n",
      });
      addTearDown(() => root.deleteSync(recursive: true));

      final files = _dartFiles(root.path);
      final reversed = files.reversed.toList();

      final fp1 = CodeGraphBuilder.inputsFingerprint(root.path, files);
      final fp2 = CodeGraphBuilder.inputsFingerprint(root.path, reversed);
      expect(fp1, startsWith('sha256:'));
      expect(fp1, fp2); // independiente del orden (ordenado antes de hashear)

      // cambiar contenido -> fingerprint diferente
      File(p.join(root.path, 'lib/a.dart')).writeAsStringSync("class A2 {}\n");
      final fp3 = CodeGraphBuilder.inputsFingerprint(root.path, files);
      expect(fp3, isNot(fp1));
    });

    test('una ruta inexistente produce un sha256: estable (sin crash)', () {
      final fp = CodeGraphBuilder.inputsFingerprint('/tmp', [
        '/tmp/dsg_does_not_exist_xyz.dart',
      ]);
      expect(fp, startsWith('sha256:'));
    });

    test(
      'renombrar/mover cambia el fingerprint (la ruta es parte del hash)',
      () {
        final root = _fixture({
          'pubspec.yaml': 'name: demo\n',
          'lib/a.dart': "class A {}\n",
        });
        addTearDown(() => root.deleteSync(recursive: true));

        final fpBefore = CodeGraphBuilder.inputsFingerprint(
          root.path,
          _dartFiles(root.path),
        );
        File(
          p.join(root.path, 'lib/a.dart'),
        ).renameSync(p.join(root.path, 'lib/moved.dart'));
        final fpAfter = CodeGraphBuilder.inputsFingerprint(
          root.path,
          _dartFiles(root.path),
        );
        expect(fpAfter, isNot(fpBefore));
      },
    );
  });
}

void main() {
  _declarationsGroup();
  group('CodeGraphBuilder — clasificación de capa por glob (slice-2 WS-A)', () {
    test(
      '_layerOf coincide paths de capa glob; directorios sin match quedan sin capa',
      () async {
        // El path de capa es un glob: lib/src/feature/<any>/presentation/
        final root = _fixture({
          'pubspec.yaml': 'name: demo\n',
          'lib/src/feature/auth/presentation/login_view.dart':
              'class LoginView {}\n',
          'lib/src/feature/auth/data/auth_repo.dart': 'class AuthRepo {}\n',
        });
        addTearDown(() => root.deleteSync(recursive: true));

        final graph = CodeGraphBuilder().build(
          projectRoot: root.path,
          filePaths: _dartFiles(root.path),
          config: const SourceGraphConfig(
            layers: [
              LayerConfig(name: 'domain', paths: ['lib/src/domain/']),
              LayerConfig(
                name: 'presentation',
                paths: ['lib/src/feature/*/presentation/'],
              ),
            ],
          ),
        );

        GraphNode fileNode(String rel) =>
            graph.nodes.firstWhere((n) => n.id == GraphNodeId.file(rel));

        expect(
          fileNode('lib/src/feature/auth/presentation/login_view.dart').layer,
          'presentation',
          reason:
              'el path de capa glob clasifica archivos presentation feature-first',
        );
        expect(
          fileNode('lib/src/feature/auth/data/auth_repo.dart').layer,
          isNull,
          reason:
              'un dir que no coincide con ningún glob de capa queda sin capa',
        );
      },
    );
  });
  group('CodeGraphBuilder — etiquetado de rol (slice-2 WS-B)', () {
    String roleOf(graph, String rel, String name) =>
        graph.nodes
                .firstWhere(
                  (n) =>
                      n.id ==
                      GraphNodeId.declaration(
                        relativePath: rel,
                        name: name,
                        kind: GraphNodeKind.class_,
                      ),
                )
                .role
            as String;

    test(
      'etiqueta rol desde supertipo (Notifier, ConsumerWidget, GetxController)',
      () async {
        final root = _fixture({
          'pubspec.yaml': 'name: demo\n',
          'lib/src/domain/todo.dart': 'class TodoList extends Notifier {}\n',
          'lib/src/presentation/home.dart':
              'class HomeView extends ConsumerWidget {}\n',
          'lib/src/presentation/login.dart':
              'class LoginController extends GetxController {}\n',
        });
        addTearDown(() => root.deleteSync(recursive: true));

        final graph = CodeGraphBuilder().build(
          projectRoot: root.path,
          filePaths: _dartFiles(root.path),
          config: _configWithLayers,
        );

        expect(
          roleOf(graph, 'lib/src/domain/todo.dart', 'TodoList'),
          'riverpod.notifier',
        );
        expect(
          roleOf(graph, 'lib/src/presentation/home.dart', 'HomeView'),
          'riverpod.consumer_widget',
        );
        expect(
          roleOf(graph, 'lib/src/presentation/login.dart', 'LoginController'),
          'getx.controller',
        );
      },
    );

    test('etiqueta rol desde anotación @riverpod (codegen: class=notifier, '
        'function=provider) cuando el supertipo es generado', () async {
      final root = _fixture({
        'pubspec.yaml': 'name: demo\n',
        'lib/src/domain/counter.dart': '''
@riverpod
class Counter extends _\$Counter {
  int build() => 0;
}

@riverpod
int doubled(ref) => 0;
''',
      });
      addTearDown(() => root.deleteSync(recursive: true));

      final graph = CodeGraphBuilder().build(
        projectRoot: root.path,
        filePaths: _dartFiles(root.path),
        config: _configWithLayers,
      );

      const rel = 'lib/src/domain/counter.dart';
      final counter = graph.nodes.firstWhere(
        (n) =>
            n.id ==
            GraphNodeId.declaration(
              relativePath: rel,
              name: 'Counter',
              kind: GraphNodeKind.class_,
            ),
      );
      expect(counter.role, 'riverpod.notifier');

      final fn = graph.nodes.firstWhere(
        (n) =>
            n.id ==
            GraphNodeId.member(
              relativePath: rel,
              owner: '',
              name: 'doubled',
              kind: GraphNodeKind.function,
            ),
      );
      expect(fn.role, 'riverpod.provider');
    });

    test(
      'roleOverrides en config extiende/reemplaza el mapa built-in',
      () async {
        final root = _fixture({
          'pubspec.yaml': 'name: demo\n',
          'lib/src/domain/foo.dart':
              'class FooController extends BaseController {}\n',
        });
        addTearDown(() => root.deleteSync(recursive: true));

        final graph = CodeGraphBuilder().build(
          projectRoot: root.path,
          filePaths: _dartFiles(root.path),
          config: const SourceGraphConfig(
            layers: [
              LayerConfig(name: 'domain', paths: ['lib/src/domain/']),
              LayerConfig(
                name: 'presentation',
                paths: ['lib/src/presentation/'],
              ),
            ],
            roleOverrides: {'BaseController': 'getx.controller'},
          ),
        );

        expect(
          roleOf(graph, 'lib/src/domain/foo.dart', 'FooController'),
          'getx.controller',
        );
      },
    );
  });
  group('CodeGraphBuilder — nodos de método/función (slice-2 WS-C)', () {
    test('emite nodos de método (miembros de clase) y función (top-level) '
        'con aristas contains', () async {
      final root = _fixture({
        'pubspec.yaml': 'name: demo\n',
        'lib/src/domain/x.dart': '''
class Counter {
  int increment() => 0;
}
void helper() {}
''',
      });
      addTearDown(() => root.deleteSync(recursive: true));

      final graph = CodeGraphBuilder().build(
        projectRoot: root.path,
        filePaths: _dartFiles(root.path),
        config: _configWithLayers,
      );

      const rel = 'lib/src/domain/x.dart';
      final methodId = GraphNodeId.member(
        relativePath: rel,
        owner: 'Counter',
        name: 'increment',
        kind: GraphNodeKind.method,
      );
      final fnId = GraphNodeId.member(
        relativePath: rel,
        owner: '',
        name: 'helper',
        kind: GraphNodeKind.function,
      );
      final classId = GraphNodeId.declaration(
        relativePath: rel,
        name: 'Counter',
        kind: GraphNodeKind.class_,
      );

      expect(
        graph.nodes.any(
          (n) => n.id == methodId && n.kind == GraphNodeKind.method,
        ),
        isTrue,
      );
      expect(
        graph.nodes.any(
          (n) => n.id == fnId && n.kind == GraphNodeKind.function,
        ),
        isTrue,
      );
      // clase contains método
      expect(
        graph.edges.any(
          (e) =>
              e.source == classId &&
              e.target == methodId &&
              e.relation == GraphRelation.contains,
        ),
        isTrue,
      );
      // archivo contains función top-level
      expect(
        graph.edges.any(
          (e) =>
              e.source == GraphNodeId.file(rel) &&
              e.target == fnId &&
              e.relation == GraphRelation.contains,
        ),
        isTrue,
      );
    });
  });
  group('CodeGraphBuilder — sin aristas calls en fase sintáctica', () {
    test('el builder no emite ninguna arista calls (se resuelven en el resolver)',
        () {
      final dir = Directory.systemTemp.createTempSync('aflow_builder_nc_');
      addTearDown(() => dir.deleteSync(recursive: true));
      File('${dir.path}/lib/w.dart')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('''
class W {
  void build() {
    helper();
    something.watch();
  }
}
void helper() {}
''');
      final graph = CodeGraphBuilder().build(
        projectRoot: dir.path,
        filePaths: ['${dir.path}/lib/w.dart'],
        config: const SourceGraphConfig(),
      );
      expect(
        graph.edges.where((e) => e.relation == GraphRelation.calls),
        isEmpty,
      );
    });
  });
  group('CodeGraphBuilder — archivos y directivas', () {
    test(
      'nodos de archivo llevan capa; imports se convierten en aristas (internas y externas)',
      () async {
        final root = _fixture({
          'pubspec.yaml': 'name: demo\n',
          'lib/src/domain/entity.dart': "class Entity {}\n",
          'lib/src/presentation/page.dart':
              "import 'package:flutter/material.dart';\n"
              "import '../domain/entity.dart';\n"
              "class Page {}\n",
          'lib/src/util/helper.dart': "class Helper {}\n",
        });
        addTearDown(() => root.deleteSync(recursive: true));

        final graph = CodeGraphBuilder().build(
          projectRoot: root.path,
          filePaths: _dartFiles(root.path),
          config: _configWithLayers,
        );

        final pageFile = graph.nodes.firstWhere(
          (n) => n.id == GraphNodeId.file('lib/src/presentation/page.dart'),
        );
        expect(pageFile.kind, GraphNodeKind.file);
        expect(pageFile.layer, 'presentation');

        final entityFile = graph.nodes.firstWhere(
          (n) => n.id == GraphNodeId.file('lib/src/domain/entity.dart'),
        );
        expect(entityFile.layer, 'domain');

        expect(
          graph.edges.any(
            (e) =>
                e.source ==
                    GraphNodeId.file('lib/src/presentation/page.dart') &&
                e.target ==
                    GraphNodeId.external('package:flutter/material.dart') &&
                e.relation == GraphRelation.imports,
          ),
          isTrue,
        );
        expect(
          graph.edges.any(
            (e) =>
                e.source ==
                    GraphNodeId.file('lib/src/presentation/page.dart') &&
                e.target == GraphNodeId.file('lib/src/domain/entity.dart') &&
                e.relation == GraphRelation.imports,
          ),
          isTrue,
        );

        final helper = graph.nodes.firstWhere(
          (n) => n.id == GraphNodeId.file('lib/src/util/helper.dart'),
        );
        expect(helper.layer, isNull);
      },
    );

    test('export / part / part of se convierten en aristas', () async {
      final root = _fixture({
        'pubspec.yaml': 'name: demo\n',
        'lib/src/domain/barrel.dart':
            "export 'entity.dart';\n"
            "part 'piece.dart';\n",
        'lib/src/domain/entity.dart': "class Entity {}\n",
        'lib/src/domain/piece.dart': "part of 'barrel.dart';\n",
      });
      addTearDown(() => root.deleteSync(recursive: true));

      final graph = CodeGraphBuilder().build(
        projectRoot: root.path,
        filePaths: _dartFiles(root.path),
        config: const SourceGraphConfig(),
      );

      bool edge(GraphRelation r, String from, String to) => graph.edges.any(
        (e) => e.relation == r && e.source == from && e.target == to,
      );
      final barrel = GraphNodeId.file('lib/src/domain/barrel.dart');
      expect(
        edge(
          GraphRelation.exports,
          barrel,
          GraphNodeId.file('lib/src/domain/entity.dart'),
        ),
        isTrue,
      );
      expect(
        edge(
          GraphRelation.part,
          barrel,
          GraphNodeId.file('lib/src/domain/piece.dart'),
        ),
        isTrue,
      );
      expect(
        edge(
          GraphRelation.partOf,
          GraphNodeId.file('lib/src/domain/piece.dart'),
          barrel,
        ),
        isTrue,
      );
    });

    test(
      'un archivo faltante se omite y se contabiliza; la sintaxis incorrecta no lanza excepción',
      () async {
        final root = _fixture({
          'pubspec.yaml': 'name: demo\n',
          'lib/src/domain/ok.dart': "class Ok {}\n",
          'lib/src/domain/broken.dart': "class { this is not valid dart \n",
        });
        addTearDown(() => root.deleteSync(recursive: true));

        // Archivos reales más una ruta que no existe en disco.
        final files = _dartFiles(root.path)
          ..add(p.join(root.path, 'lib/src/domain/does_not_exist.dart'));

        final builder = CodeGraphBuilder();
        final graph = builder.build(
          projectRoot: root.path,
          filePaths: files,
          config: const SourceGraphConfig(),
        );

        // ok.dart todavía produce un nodo de archivo; broken.dart se parseó sin lanzar.
        expect(
          graph.nodes.any(
            (n) => n.id == GraphNodeId.file('lib/src/domain/ok.dart'),
          ),
          isTrue,
        );
        // broken.dart tiene sintaxis incorrecta pero aún se parsea (no se omite) —
        // produce un nodo con lo que el parser recuperó.
        expect(
          graph.nodes.any(
            (n) => n.id == GraphNodeId.file('lib/src/domain/broken.dart'),
          ),
          isTrue,
        );
        // la ruta faltante disparó FileSystemException -> omitida y contabilizada.
        expect(builder.skippedFiles, 1);
      },
    );
  });
  group('CodeGraphBuilder — miembros de mixin y enum', () {
    test('emite nodos method + contains para métodos de mixin y enum', () {
      final dir = Directory.systemTemp.createTempSync('aflow_builder_me_');
      addTearDown(() => dir.deleteSync(recursive: true));
      File('${dir.path}/lib/x.dart')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('''
mixin Retry {
  void retry() {}
}
enum Status {
  ok, bad;
  bool get isOk => this == Status.ok;
  void describe() {}
}
''');
      final graph = CodeGraphBuilder().build(
        projectRoot: dir.path,
        filePaths: ['${dir.path}/lib/x.dart'],
        config: const SourceGraphConfig(),
      );
      final methodIds = graph.nodes
          .where((n) => n.kind == GraphNodeKind.method)
          .map((n) => n.id)
          .toSet();
      expect(
        methodIds,
        contains(GraphNodeId.member(
          relativePath: 'lib/x.dart', owner: 'Retry', name: 'retry',
          kind: GraphNodeKind.method)),
      );
      expect(
        methodIds,
        contains(GraphNodeId.member(
          relativePath: 'lib/x.dart', owner: 'Status', name: 'describe',
          kind: GraphNodeKind.method)),
      );
      expect(
        graph.edges.any((e) =>
            e.relation == GraphRelation.contains &&
            e.source == GraphNodeId.declaration(
                relativePath: 'lib/x.dart', name: 'Retry',
                kind: GraphNodeKind.mixin_) &&
            e.target == GraphNodeId.member(
                relativePath: 'lib/x.dart', owner: 'Retry', name: 'retry',
                kind: GraphNodeKind.method)),
        isTrue,
      );
      expect(
        graph.edges.any((e) =>
            e.relation == GraphRelation.contains &&
            e.source == GraphNodeId.declaration(
                relativePath: 'lib/x.dart', name: 'Status',
                kind: GraphNodeKind.enum_)),
        isTrue,
      );
    });
  });
  _fingerprintGroup();

  group('CodeGraphBuilder — resolución de import de paquete propio', () {
    test(
      'imports/exports package:<self>/… resuelven a nodos de archivo internos',
      () {
        final root = _fixture({
          'pubspec.yaml': 'name: demo\n',
          'lib/src/domain/user.dart': 'class User {}\n',
          'lib/src/domain/barrel.dart':
              "export 'package:demo/src/domain/user.dart';\n",
          'lib/src/domain/repo.dart': '''
import 'package:demo/src/domain/user.dart';
import 'package:flutter/material.dart';
import 'dart:async';
class Repo {}
''',
        });
        addTearDown(() => root.deleteSync(recursive: true));

        final graph = CodeGraphBuilder().build(
          projectRoot: root.path,
          filePaths: _dartFiles(root.path),
          config: const SourceGraphConfig(),
          packageName: 'demo',
        );

        final repoId = GraphNodeId.file('lib/src/domain/repo.dart');
        final barrelId = GraphNodeId.file('lib/src/domain/barrel.dart');
        final userId = GraphNodeId.file('lib/src/domain/user.dart');

        // el import self-package resuelve al nodo de archivo interno
        expect(
          graph.edges.any(
            (e) =>
                e.relation == GraphRelation.imports &&
                e.source == repoId &&
                e.target == userId,
          ),
          isTrue,
        );
        // el export self-package resuelve igual
        expect(
          graph.edges.any(
            (e) =>
                e.relation == GraphRelation.exports &&
                e.source == barrelId &&
                e.target == userId,
          ),
          isTrue,
        );
        // no se creó nodo external-by-URI para el import self-package
        expect(
          graph.nodes.any(
            (n) =>
                n.id ==
                GraphNodeId.external('package:demo/src/domain/user.dart'),
          ),
          isFalse,
        );
        // imports de terceros + dart: permanecen externos
        expect(
          graph.nodes.any(
            (n) =>
                n.id == GraphNodeId.external('package:flutter/material.dart'),
          ),
          isTrue,
        );
        expect(
          graph.nodes.any((n) => n.id == GraphNodeId.external('dart:async')),
          isTrue,
        );
      },
    );

    test(
      'packageName null deja los URIs del paquete propio como externos (back-compat)',
      () {
        final root = _fixture({
          'pubspec.yaml': 'name: demo\n',
          'lib/src/domain/user.dart': 'class User {}\n',
          'lib/src/domain/repo.dart':
              "import 'package:demo/src/domain/user.dart';\nclass Repo {}\n",
        });
        addTearDown(() => root.deleteSync(recursive: true));

        final graph = CodeGraphBuilder().build(
          projectRoot: root.path,
          filePaths: _dartFiles(root.path),
          config: const SourceGraphConfig(),
        );

        expect(
          graph.nodes.any(
            (n) =>
                n.id ==
                GraphNodeId.external('package:demo/src/domain/user.dart'),
          ),
          isTrue,
        );
      },
    );
  });
}
