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
