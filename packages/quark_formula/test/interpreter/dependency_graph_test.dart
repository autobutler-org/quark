import 'package:quark_formula/evaluation/evaluation.dart';
import 'package:test/test.dart';

void main() {
  group('DependencyGraph', () {
    test('ensureNode registers a node with empty adjacency sets', () {
      final g = DependencyGraph();
      g.ensureNode((0, 0));
      expect(g.dependsOn[(0, 0)], isEmpty);
      expect(g.dependedOnBy[(0, 0)], isEmpty);
    });

    test('addEdge records both directions and registers both endpoints', () {
      final g = DependencyGraph();
      g.addEdge((0, 1), (0, 0));
      expect(g.dependsOn[(0, 1)], contains((0, 0)));
      expect(g.dependedOnBy[(0, 0)], contains((0, 1)));
      expect(g.dependsOn.containsKey((0, 0)), isTrue);
      expect(g.dependedOnBy.containsKey((0, 1)), isTrue);
    });

    test('addEdge self-loop is recorded correctly', () {
      final g = DependencyGraph();
      g.addEdge((0, 0), (0, 0));
      expect(g.dependsOn[(0, 0)], contains((0, 0)));
      expect(g.dependedOnBy[(0, 0)], contains((0, 0)));
    });

    test(
      'multiple edges from one source and to one target are all recorded',
      () {
        final g = DependencyGraph();
        g.addEdge((0, 2), (0, 0));
        g.addEdge((0, 2), (0, 1));
        g.addEdge((1, 0), (1, 2));
        g.addEdge((1, 1), (1, 2));
        expect(g.dependsOn[(0, 2)], containsAll([(0, 0), (0, 1)]));
        expect(g.dependedOnBy[(1, 2)], containsAll([(1, 0), (1, 1)]));
      },
    );

    test('addEdge is idempotent for duplicate edges', () {
      final g = DependencyGraph();
      g.addEdge((0, 1), (0, 0));
      g.addEdge((0, 1), (0, 0));
      expect(g.dependsOn[(0, 1)], hasLength(1));
      expect(g.dependedOnBy[(0, 0)], hasLength(1));
    });
  });
}
