// Tests for the minimal glob matcher used by graph file selection (slice-2 WS-A).

import 'package:dart_source_graph/src/core/glob_match.dart';
import 'package:test/test.dart';

void main() {
  test('prefix dir matches the whole subtree', () {
    expect(globMatch('lib/src/feature/', 'lib/src/feature/a/b.dart'), isTrue);
    expect(globMatch('lib/src/feature/', 'lib/src/other/b.dart'), isFalse);
  });

  test('** matches any depth', () {
    expect(globMatch('**/*.g.dart', 'lib/a/b.g.dart'), isTrue);
    expect(globMatch('**/*.g.dart', 'b.g.dart'), isTrue);
    expect(globMatch('**/*.g.dart', 'lib/a.dart'), isFalse);
  });

  test('* matches exactly one segment', () {
    expect(
      globMatch(
        'lib/src/feature/*/presentation/',
        'lib/src/feature/auth/presentation/x.dart',
      ),
      isTrue,
    );
    expect(
      globMatch(
        'lib/src/feature/*/presentation/',
        'lib/src/feature/auth/data/y.dart',
      ),
      isFalse,
    );
  });

  test('* within a segment anchors correctly', () {
    expect(globMatch('lib/*.freezed.dart', 'lib/model.freezed.dart'), isTrue);
    expect(globMatch('lib/*.freezed.dart', 'lib/model.dart'), isFalse);
  });

  test('exact path with no meta', () {
    expect(globMatch('lib/a.dart', 'lib/a.dart'), isTrue);
    expect(globMatch('lib/a.dart', 'lib/b.dart'), isFalse);
  });
}
