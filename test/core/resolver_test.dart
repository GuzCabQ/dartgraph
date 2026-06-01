import 'dart:convert';
import 'dart:io';

import 'package:dart_source_graph/src/config/source_graph_config.dart';
import 'package:dart_source_graph/src/contracts/code_graph.dart';
import 'package:dart_source_graph/src/core/builder.dart';
import 'package:dart_source_graph/src/core/query.dart';
import 'package:dart_source_graph/src/core/resolver.dart';
import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Resolver que construye una colección excluyendo [_excludedPath], de modo que
/// [contextFor] lanza [StateError] para ese path — ejercita la rama de degradación.
class _PartialResolver extends CodeGraphResolver {
  final String _excludedPath;
  _PartialResolver(this._excludedPath);

  @override
  AnalysisContextCollection buildCollection(List<String> normalizedPaths) =>
      AnalysisContextCollection(
        includedPaths: normalizedPaths
            .where((fp) => fp != _excludedPath)
            .toList(),
      );
}

Directory _fixture(Map<String, String> files) {
  final root = Directory.systemTemp.createTempSync('aflow_resolve_');
  files.forEach((rel, contents) {
    final f = File(p.join(root.path, rel));
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(contents);
  });
  // package_config mínimo para que el analyzer construya un contexto resolvedor
  // (resuelve dart:core via el SDK + imports intra-proyecto). Sin él,
  // getResolvedUnit puede devolver supertipos sin resolver y los tests fallan.
  // Vive bajo .dart_tool/ (fuera de lib/), por lo que no se escanea.
  File(p.join(root.path, '.dart_tool', 'package_config.json'))
    ..parent.createSync(recursive: true)
    ..writeAsStringSync('''
{
  "configVersion": 2,
  "packages": [
    { "name": "demo", "rootUri": "../", "packageUri": "lib/", "languageVersion": "3.0" }
  ]
}
''');
  return root;
}

List<String> _dartFiles(String root) => Directory(p.join(root, 'lib'))
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .map((f) => p.normalize(f.absolute.path))
    .toList();

Future<CodeGraph> _build(String root, {required bool resolve}) async {
  const config = SourceGraphConfig();
  final files = _dartFiles(root);
  final base = CodeGraphBuilder().build(
    projectRoot: root,
    filePaths: files,
    config: config,
  );
  if (!resolve) return base;
  return CodeGraphResolver().resolve(
    base,
    projectRoot: root,
    filePaths: files,
    config: config,
  );
}

void _referencesGroup() {
  group('CodeGraphResolver — references', () {
    test(
      'field/return/param internal types become references; dart: excluded',
      () async {
        final root = _fixture({
          'pubspec.yaml': 'name: demo\n',
          'lib/src/domain/user.dart': 'class User {}\n',
          'lib/src/domain/repo.dart': '''
import 'user.dart';
class Repo {
  final String name = '';
  final User current = User();
  Future<User> fetch() async => current;
  void save(User u) {}
}
''',
        });
        addTearDown(() => root.deleteSync(recursive: true));

        final graph = await _build(root.path, resolve: true);
        final repoId = GraphNodeId.declaration(
          relativePath: 'lib/src/domain/repo.dart',
          name: 'Repo',
          kind: GraphNodeKind.class_,
        );
        final userId = GraphNodeId.declaration(
          relativePath: 'lib/src/domain/user.dart',
          name: 'User',
          kind: GraphNodeKind.class_,
        );

        final refs = graph.edges.where(
          (e) => e.relation == GraphRelation.references && e.source == repoId,
        );

        // references User exactamente una vez (deduplicado entre field/return/param)
        expect(refs.where((e) => e.target == userId).length, 1);
        // no hay referencia a dart:core String
        expect(
          refs.any((e) => e.target == GraphNodeId.external('String')),
          isFalse,
        );
      },
    );

    test('nested generics unwrap to the inner type only', () async {
      final root = _fixture({
        'pubspec.yaml': 'name: demo\n',
        'lib/src/domain/user.dart': 'class User {}\n',
        'lib/src/domain/svc.dart': '''
import 'user.dart';
class Svc {
  final Map<String, List<User>> cache = const {};
}
''',
      });
      addTearDown(() => root.deleteSync(recursive: true));

      final graph = await _build(root.path, resolve: true);
      final svcId = GraphNodeId.declaration(
        relativePath: 'lib/src/domain/svc.dart',
        name: 'Svc',
        kind: GraphNodeKind.class_,
      );
      final userId = GraphNodeId.declaration(
        relativePath: 'lib/src/domain/user.dart',
        name: 'User',
        kind: GraphNodeKind.class_,
      );
      final refs = graph.edges.where(
        (e) => e.relation == GraphRelation.references && e.source == svcId,
      );
      // el User interno es referenciado; Map / String (dart:) no lo son
      expect(refs.any((e) => e.target == userId), isTrue);
      expect(refs.any((e) => e.target == GraphNodeId.external('Map')), isFalse);
      expect(
        refs.any((e) => e.target == GraphNodeId.external('String')),
        isFalse,
      );
    });

    test('constructor parameter types become references', () async {
      final root = _fixture({
        'pubspec.yaml': 'name: demo\n',
        'lib/src/domain/user.dart': 'class User {}\n',
        'lib/src/domain/repo.dart': '''
import 'user.dart';
class Repo {
  Repo(this.seed);
  final User seed;
}
''',
      });
      addTearDown(() => root.deleteSync(recursive: true));

      final graph = await _build(root.path, resolve: true);
      final repoId = GraphNodeId.declaration(
        relativePath: 'lib/src/domain/repo.dart',
        name: 'Repo',
        kind: GraphNodeKind.class_,
      );
      final userId = GraphNodeId.declaration(
        relativePath: 'lib/src/domain/user.dart',
        name: 'User',
        kind: GraphNodeKind.class_,
      );
      expect(
        graph.edges.any(
          (e) =>
              e.relation == GraphRelation.references &&
              e.source == repoId &&
              e.target == userId,
        ),
        isTrue,
      );
    });
  });
}

void main() {
  _referencesGroup();
  group('CodeGraphResolver — inheritance', () {
    test(
      'extends an internal class -> edge retargets to the internal node',
      () async {
        final root = _fixture({
          'pubspec.yaml': 'name: demo\n',
          'lib/src/domain/base.dart': 'class Base {}\n',
          'lib/src/domain/foo.dart':
              "import 'base.dart';\nclass Foo extends Base {}\n",
        });
        addTearDown(() => root.deleteSync(recursive: true));

        final graph = await _build(root.path, resolve: true);
        final fooId = GraphNodeId.declaration(
          relativePath: 'lib/src/domain/foo.dart',
          name: 'Foo',
          kind: GraphNodeKind.class_,
        );
        final baseInternal = GraphNodeId.declaration(
          relativePath: 'lib/src/domain/base.dart',
          name: 'Base',
          kind: GraphNodeKind.class_,
        );
        expect(
          graph.edges.any(
            (e) =>
                e.relation == GraphRelation.extends_ &&
                e.source == fooId &&
                e.target == baseInternal,
          ),
          isTrue,
        );
        expect(
          graph.edges.any(
            (e) =>
                e.relation == GraphRelation.extends_ &&
                e.source == fooId &&
                e.target == GraphNodeId.external('Base'),
          ),
          isFalse,
        );
      },
    );

    test(
      'without resolve, inheritance stays external-by-name (slice-1a)',
      () async {
        final root = _fixture({
          'pubspec.yaml': 'name: demo\n',
          'lib/src/domain/base.dart': 'class Base {}\n',
          'lib/src/domain/foo.dart':
              "import 'base.dart';\nclass Foo extends Base {}\n",
        });
        addTearDown(() => root.deleteSync(recursive: true));
        final graph = await _build(root.path, resolve: false);
        final fooId = GraphNodeId.declaration(
          relativePath: 'lib/src/domain/foo.dart',
          name: 'Foo',
          kind: GraphNodeKind.class_,
        );
        expect(
          graph.edges.any(
            (e) =>
                e.relation == GraphRelation.extends_ &&
                e.source == fooId &&
                e.target == GraphNodeId.external('Base'),
          ),
          isTrue,
        );
      },
    );

    test('implements/with internal types retarget too', () async {
      final root = _fixture({
        'pubspec.yaml': 'name: demo\n',
        'lib/src/domain/iface.dart': 'abstract class Iface {}\nmixin Mix {}\n',
        'lib/src/domain/foo.dart':
            "import 'iface.dart';\nclass Foo with Mix implements Iface {}\n",
      });
      addTearDown(() => root.deleteSync(recursive: true));
      final graph = await _build(root.path, resolve: true);
      final fooId = GraphNodeId.declaration(
        relativePath: 'lib/src/domain/foo.dart',
        name: 'Foo',
        kind: GraphNodeKind.class_,
      );
      final ifaceId = GraphNodeId.declaration(
        relativePath: 'lib/src/domain/iface.dart',
        name: 'Iface',
        kind: GraphNodeKind.class_,
      );
      final mixId = GraphNodeId.declaration(
        relativePath: 'lib/src/domain/iface.dart',
        name: 'Mix',
        kind: GraphNodeKind.mixin_,
      );
      expect(
        graph.edges.any(
          (e) =>
              e.relation == GraphRelation.implements_ &&
              e.source == fooId &&
              e.target == ifaceId,
        ),
        isTrue,
      );
      expect(
        graph.edges.any(
          (e) =>
              e.relation == GraphRelation.mixesIn &&
              e.source == fooId &&
              e.target == mixId,
        ),
        isTrue,
      );
    });

    test('resolve is deterministic (byte-identical twice)', () async {
      final root = _fixture({
        'pubspec.yaml': 'name: demo\n',
        'lib/src/domain/base.dart': 'class Base {}\n',
        'lib/src/domain/foo.dart':
            "import 'base.dart';\nclass Foo extends Base {}\n",
      });
      addTearDown(() => root.deleteSync(recursive: true));
      final g1 = await _build(root.path, resolve: true);
      final g2 = await _build(root.path, resolve: true);
      const meta = CodeGraphMeta(
        schemaVersion: '1.0.0',
        package: 'demo',
        generatedAt: 't',
        inputsFingerprint: 'sha256:x',
        root: '.',
        resolved: true,
      );
      expect(
        jsonEncode(g1.toJson(meta: meta)),
        jsonEncode(g2.toJson(meta: meta)),
      );
    });

    test(
      'an unresolvable file keeps its base by-name edges and is counted',
      () async {
        final root = _fixture({
          'pubspec.yaml': 'name: demo\n',
          'lib/src/domain/base.dart': 'class Base {}\n',
          'lib/src/domain/foo.dart':
              "import 'base.dart';\nclass Foo extends Base {}\n",
        });
        addTearDown(() => root.deleteSync(recursive: true));

        const config = SourceGraphConfig();
        final files = _dartFiles(root.path);
        final base = CodeGraphBuilder().build(
          projectRoot: root.path,
          filePaths: files,
          config: config,
        );

        // _PartialResolver excluye foo.dart del AnalysisContextCollection,
        // así que contextFor(fooPath) lanza StateError -> capturado por el bloque
        // catch por archivo -> _unresolved++ y la arista por-nombre se conserva.
        final fooAbsPath = p.normalize(
          p.join(root.path, 'lib', 'src', 'domain', 'foo.dart'),
        );
        final resolver = _PartialResolver(fooAbsPath);
        final graph = await resolver.resolve(
          base,
          projectRoot: root.path,
          filePaths: files,
          config: config,
        );

        expect(resolver.unresolvedFiles, greaterThanOrEqualTo(1));
        final fooId = GraphNodeId.declaration(
          relativePath: 'lib/src/domain/foo.dart',
          name: 'Foo',
          kind: GraphNodeKind.class_,
        );
        // La arista por-nombre de Foo de slice-1a sobrevive porque foo.dart no se resolvió.
        expect(
          graph.edges.any(
            (e) =>
                e.relation == GraphRelation.extends_ &&
                e.source == fooId &&
                e.target == GraphNodeId.external('Base'),
          ),
          isTrue,
        );
      },
    );
  });

  group('resolver — calls internas', () {
    test('resuelve call método→método interno a la declaración real', () async {
      final root = _fixture({
        'lib/a.dart': '''
class Svc {
  int helper() => 1;
  int run() => helper();
}
''',
      });
      addTearDown(() => Directory(root.path).deleteSync(recursive: true));
      final g = await _build(root.path, resolve: true);
      final call = g.edges.firstWhere(
        (e) => e.relation == GraphRelation.calls,
        orElse: () => throw StateError('no calls'),
      );
      expect(call.source, GraphNodeId.member(relativePath: 'lib/a.dart', owner: 'Svc', name: 'run', kind: GraphNodeKind.method));
      expect(call.target, GraphNodeId.member(relativePath: 'lib/a.dart', owner: 'Svc', name: 'helper', kind: GraphNodeKind.method));
      expect(call.confidence, GraphConfidence.extracted);
    });

    test('homónimos: resuelve al owner correcto, no por nombre', () async {
      final root = _fixture({
        'lib/a.dart': '''
class A { int m() => 1; }
class B {
  final A a = A();
  int call2() => a.m();
}
''',
      });
      addTearDown(() => Directory(root.path).deleteSync(recursive: true));
      final g = await _build(root.path, resolve: true);
      final hasCorrect = g.edges.any((e) =>
          e.relation == GraphRelation.calls &&
          e.source == GraphNodeId.member(relativePath: 'lib/a.dart', owner: 'B', name: 'call2', kind: GraphNodeKind.method) &&
          e.target == GraphNodeId.member(relativePath: 'lib/a.dart', owner: 'A', name: 'm', kind: GraphNodeKind.method));
      expect(hasCorrect, isTrue);
    });

    test('call a método de mixin interno resuelve a su nodo', () async {
      final root = _fixture({
        'lib/a.dart': '''
mixin Retry { void retry() {} }
class C with Retry {
  void go() { retry(); }
}
''',
      });
      addTearDown(() => Directory(root.path).deleteSync(recursive: true));
      final g = await _build(root.path, resolve: true);
      final hit = g.edges.any((e) =>
          e.relation == GraphRelation.calls &&
          e.target == GraphNodeId.member(relativePath: 'lib/a.dart', owner: 'Retry', name: 'retry', kind: GraphNodeKind.method));
      expect(hit, isTrue);
    });

    test('call a función top-level interna resuelve', () async {
      final root = _fixture({
        'lib/a.dart': '''
int helper() => 1;
int caller() => helper();
''',
      });
      addTearDown(() => Directory(root.path).deleteSync(recursive: true));
      final g = await _build(root.path, resolve: true);
      final hit = g.edges.any((e) =>
          e.relation == GraphRelation.calls &&
          e.source == GraphNodeId.member(relativePath: 'lib/a.dart', owner: '', name: 'caller', kind: GraphNodeKind.function) &&
          e.target == GraphNodeId.member(relativePath: 'lib/a.dart', owner: '', name: 'helper', kind: GraphNodeKind.function));
      expect(hit, isTrue);
    });

    test('call a método del SDK fuera de allowlist se descarta', () async {
      final root = _fixture({
        'lib/a.dart': '''
class P {
  void go() { print('hi'); }
}
''',
      });
      addTearDown(() => Directory(root.path).deleteSync(recursive: true));
      final g = await _build(root.path, resolve: true);
      expect(g.edges.where((e) => e.relation == GraphRelation.calls), isEmpty);
    });

    test('archivo no resoluble degrada sin emitir calls ni romper', () async {
      final root = _fixture({
        'lib/a.dart': '''
class Svc {
  int helper() => 1;
  int run() => helper();
}
''',
      });
      addTearDown(() => Directory(root.path).deleteSync(recursive: true));
      final files = _dartFiles(root.path);
      final base = CodeGraphBuilder().build(projectRoot: root.path, filePaths: files, config: const SourceGraphConfig());
      final g = await _PartialResolver(files.first).resolve(base, projectRoot: root.path, filePaths: files, config: const SourceGraphConfig());
      expect(g.edges.where((e) => e.relation == GraphRelation.calls), isEmpty);
    });
  });

  group('CodeGraphResolver — orphan external GC', () {
    test(
      'orphan external twin left by inheritance retargeting is dropped',
      () async {
        final root = _fixture({
          'pubspec.yaml': 'name: demo\n',
          'lib/src/domain/base.dart': 'class Base {}\n',
          'lib/src/domain/child.dart': '''
import 'base.dart';
class Child extends Base {}
''',
          'lib/src/domain/widgetish.dart': '''
class StatelessWidget {}
class View extends StatelessWidget {}
''',
        });
        addTearDown(() => root.deleteSync(recursive: true));

        final graph = await _build(root.path, resolve: true);

        // El builder emitió external:Base para la herencia por-nombre; después de
        // que la resolución lo retargetea a la clase interna, el gemelo externo
        // debe desaparecer (ningún nodo externo sin aristas).
        final referenced = <String>{};
        for (final e in graph.edges) {
          referenced.add(e.source);
          referenced.add(e.target);
        }
        final orphanExternals = graph.nodes.where(
          (n) => n.kind == GraphNodeKind.external && !referenced.contains(n.id),
        );
        expect(orphanExternals, isEmpty);

        // Base se resolvió a interno: no queda ningún nodo external:Base.
        expect(
          graph.nodes.any((n) => n.id == GraphNodeId.external('Base')),
          isFalse,
        );

        // StatelessWidget se declara internamente, así que View->StatelessWidget
        // también resuelve interno; la arista extends_ apunta al interno.
        final viewId = GraphNodeId.declaration(
          relativePath: 'lib/src/domain/widgetish.dart',
          name: 'View',
          kind: GraphNodeKind.class_,
        );
        final swId = GraphNodeId.declaration(
          relativePath: 'lib/src/domain/widgetish.dart',
          name: 'StatelessWidget',
          kind: GraphNodeKind.class_,
        );
        expect(
          graph.edges.any(
            (e) =>
                e.relation == GraphRelation.extends_ &&
                e.source == viewId &&
                e.target == swId,
          ),
          isTrue,
        );
      },
    );

    test(
      'genuinely-external supertype is kept when its by-name edge survives (unresolved file)',
      () async {
        // Cuando un archivo falla al resolverse, su arista por-nombre del builder
        // se preserva en `kept`. Esa arista mantiene el nodo externo referenciado,
        // así que el GC NO debe eliminarlo.
        final root = _fixture({
          'pubspec.yaml': 'name: demo\n',
          'lib/src/domain/base.dart': 'class Base {}\n',
          'lib/src/domain/child.dart': '''
import 'base.dart';
class Child extends Base {}
''',
        });
        addTearDown(() => root.deleteSync(recursive: true));

        const config = SourceGraphConfig();
        final files = _dartFiles(root.path);
        final base = CodeGraphBuilder().build(
          projectRoot: root.path,
          filePaths: files,
          config: config,
        );

        // Excluir child.dart del AnalysisContextCollection para que permanezca
        // sin resolver. Su arista extends_ por-nombre (→ external:Base) se preserva
        // en `kept`, así que external:Base debe sobrevivir al paso GC.
        final childAbsPath = p.normalize(
          p.join(root.path, 'lib', 'src', 'domain', 'child.dart'),
        );
        final resolver = _PartialResolver(childAbsPath);
        final graph = await resolver.resolve(
          base,
          projectRoot: root.path,
          filePaths: files,
          config: config,
        );

        // external:Base aún está referenciado por la arista por-nombre sobreviviente de child.dart.
        final ext = graph.nodes.where(
          (n) => n.id == GraphNodeId.external('Base'),
        );
        expect(ext.length, 1);

        final referenced = <String>{};
        for (final e in graph.edges) {
          referenced.add(e.source);
          referenced.add(e.target);
        }
        expect(referenced.contains(GraphNodeId.external('Base')), isTrue);
      },
    );

    test(
      'resolveNodes is unambiguous after orphan external twin is GCd',
      () async {
        final root = _fixture({
          'pubspec.yaml': 'name: demo\n',
          'lib/src/domain/base.dart': 'class Base {}\n',
          'lib/src/domain/child.dart': '''
import 'base.dart';
class Child extends Base {}
''',
        });
        addTearDown(() => root.deleteSync(recursive: true));

        final graph = await _build(root.path, resolve: true);

        // Antes del GC, existían class:…#Base (interno) y external:Base (gemelo
        // huérfano), así que resolveNodes('Base') era ambiguo. Después del GC el
        // gemelo desaparece y el nombre resuelve exactamente a la clase interna.
        final matches = CodeGraphQuery(graph).resolveNodes('Base');
        expect(matches.length, 1);
        expect(matches.single.kind, GraphNodeKind.class_);
        expect(
          matches.single.id,
          GraphNodeId.declaration(
            relativePath: 'lib/src/domain/base.dart',
            name: 'Base',
            kind: GraphNodeKind.class_,
          ),
        );
      },
    );
  });

  group('resolver — allowlist de estado', () {
    test('llamada a un nombre del allowlist no resoluble se conserva como external inferred',
        () async {
      final root = _fixture({
        'lib/a.dart': '''
class Widget {
  final dynamic ref = null;
  void build() { ref.watch(0); }
}
''',
      });
      addTearDown(() => Directory(root.path).deleteSync(recursive: true));
      final g = await _build(root.path, resolve: true);
      final watchEdge = g.edges.where((e) =>
          e.relation == GraphRelation.calls &&
          e.target == GraphNodeId.external('watch'));
      expect(watchEdge, isNotEmpty,
          reason: 'watch está en kStateApiCalls; al no resolver a interno cae al allowlist');
      expect(watchEdge.first.confidence, GraphConfidence.inferred);
    });
  });

  group('resolver — instantiates', () {
    test('creación de clase interna emite instantiates extracted', () async {
      final root = _fixture({
        'lib/a.dart': '''
class Dep {}
class Owner {
  Dep make() => Dep();
}
''',
      });
      addTearDown(() => Directory(root.path).deleteSync(recursive: true));
      final g = await _build(root.path, resolve: true);
      final inst = g.edges.where((e) => e.relation == GraphRelation.instantiates);
      expect(inst, isNotEmpty);
      expect(inst.first.source, GraphNodeId.member(relativePath: 'lib/a.dart', owner: 'Owner', name: 'make', kind: GraphNodeKind.method));
      expect(inst.first.target, GraphNodeId.declaration(relativePath: 'lib/a.dart', name: 'Dep', kind: GraphNodeKind.class_));
      expect(inst.first.confidence, GraphConfidence.extracted);
    });

    test('creación de clase del SDK no emite instantiates', () async {
      final root = _fixture({
        'lib/a.dart': '''
class Owner {
  Object make() => Object();
}
''',
      });
      addTearDown(() => Directory(root.path).deleteSync(recursive: true));
      final g = await _build(root.path, resolve: true);
      expect(g.edges.where((e) => e.relation == GraphRelation.instantiates), isEmpty);
    });

    test('factory redirigido apunta a la clase NOMBRADA, no a la construida', () async {
      final root = _fixture({
        'lib/a.dart': '''
class Facade {
  factory Facade() = _FacadeImpl;
  Facade._();
}
class _FacadeImpl extends Facade {
  _FacadeImpl() : super._();
}
class Owner {
  Facade build() => Facade();
}
''',
      });
      addTearDown(() => Directory(root.path).deleteSync(recursive: true));
      final g = await _build(root.path, resolve: true);
      final inst = g.edges.where((e) => e.relation == GraphRelation.instantiates);
      expect(
        inst.any((e) => e.target == GraphNodeId.declaration(relativePath: 'lib/a.dart', name: 'Facade', kind: GraphNodeKind.class_)),
        isTrue,
        reason: 'apunta a la clase nombrada Facade',
      );
      expect(
        inst.any((e) => e.target == GraphNodeId.declaration(relativePath: 'lib/a.dart', name: '_FacadeImpl', kind: GraphNodeKind.class_)),
        isFalse,
        reason: 'NO apunta a la implementación redirigida',
      );
    });
  });
}
