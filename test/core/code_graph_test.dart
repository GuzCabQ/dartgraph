import 'package:dart_source_graph/src/contracts/code_graph.dart';
import 'package:test/test.dart';

void main() {
  group('GraphRelation.instantiates', () {
    test('serializa a "instantiates" y vuelve', () {
      expect(graphRelationToJson(GraphRelation.instantiates), 'instantiates');
      expect(graphRelationFromJson('instantiates'), GraphRelation.instantiates);
    });

    test('una arista instantiates round-trips por JSON', () {
      const e = GraphEdge(
        source: 'method:lib/a.dart#A.m',
        target: 'class:lib/b.dart#B',
        relation: GraphRelation.instantiates,
        confidence: GraphConfidence.extracted,
        line: 7,
      );
      final back = GraphEdge.fromJson(e.toJson());
      expect(back.relation, GraphRelation.instantiates);
      expect(back.target, 'class:lib/b.dart#B');
    });
  });
}
