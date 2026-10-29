// SPDX-License-Identifier: GPL-3.0-only
/// A dynamic R-tree with quadratic split and exact object hit testing.
library;

import 'dart:math' as math;

import '../geometry/intersections.dart';
import '../geometry/object.dart';
import '../geometry/point.dart';

class RTreeEntry<T> {
  const RTreeEntry(this.id, this.bounds, this.value);
  final String id;
  final Bounds2 bounds;
  final T value;
}

class RTree<T> {
  RTree({this.maxEntries = 8, this.minEntries = 3})
    : assert(maxEntries >= 4),
      assert(minEntries >= 1 && minEntries <= maxEntries ~/ 2) {
    _root = _Node<T>(leaf: true);
  }

  final int maxEntries;
  final int minEntries;
  late _Node<T> _root;
  final Map<String, Bounds2> _known = {};

  int get length => _known.length;
  bool get isEmpty => _known.isEmpty;
  bool get isNotEmpty => _known.isNotEmpty;
  Bounds2? get bounds => _root.children.isEmpty ? null : _root.bounds;

  void insert(String id, Bounds2 bounds, T value) {
    if (!bounds.isValid) {
      throw ArgumentError.value(bounds, 'bounds', 'Finite bounds required.');
    }
    if (_known.containsKey(id)) {
      throw ArgumentError.value(id, 'id', 'Duplicate R-tree id.');
    }
    _known[id] = bounds;
    final sibling = _insertInto(_root, _Child<T>.leaf(id, bounds, value));
    if (sibling != null) {
      final oldRoot = _root;
      final newRoot = _Node<T>(leaf: false)
        ..children.add(_Child<T>.node(oldRoot.bounds, oldRoot))
        ..children.add(_Child<T>.node(sibling.bounds, sibling));
      newRoot.recomputeBounds();
      _root = newRoot;
    }
  }

  void insertEntry(RTreeEntry<T> entry) =>
      insert(entry.id, entry.bounds, entry.value);

  bool remove(String id) {
    final bounds = _known.remove(id);
    if (bounds == null) return false;
    _removeFrom(_root, id);
    _shrinkRoot();
    return true;
  }

  void clear() {
    _known.clear();
    _root = _Node<T>(leaf: true);
  }

  List<RTreeEntry<T>> query(Bounds2 area) {
    final result = <RTreeEntry<T>>[];
    if (_root.children.isEmpty) return result;
    _queryNode(_root, area, result);
    return result;
  }

  List<T> search(Bounds2 area) => [
    for (final entry in query(area)) entry.value,
  ];

  /// Marks the tree structure stale after moves. Callers can remove/insert
  /// individual items; this helper rebuilds from the supplied entries.
  void rebuild(Iterable<RTreeEntry<T>> entries) {
    clear();
    for (final entry in entries) {
      insertEntry(entry);
    }
  }

  /// Returns a newly split sibling node when this node overflowed.
  _Node<T>? _insertInto(_Node<T> node, _Child<T> child) {
    if (node.leaf) {
      node.children.add(child);
      node.recomputeBounds();
      if (node.children.length <= maxEntries) return null;
      return _splitNode(node);
    }
    var bestIndex = 0;
    var bestAreaGrowth = double.infinity;
    var bestArea = double.infinity;
    for (var i = 0; i < node.children.length; i++) {
      final entry = node.children[i];
      final childNode = entry.node;
      if (childNode == null) continue;
      final enlarged = entry.bounds.union(child.bounds).area;
      final growth = enlarged - entry.bounds.area;
      if (growth < bestAreaGrowth ||
          (growth == bestAreaGrowth && entry.bounds.area < bestArea)) {
        bestAreaGrowth = growth;
        bestArea = entry.bounds.area;
        bestIndex = i;
      }
    }
    final target = node.children[bestIndex].node!;
    final sibling = _insertInto(target, child);
    node.children[bestIndex].bounds = target.bounds;
    if (sibling != null) {
      node.children.add(_Child<T>.node(sibling.bounds, sibling));
    }
    node.recomputeBounds();
    if (node.children.length > maxEntries) return _splitNode(node);
    return null;
  }

  bool _removeFrom(_Node<T> node, String id) {
    if (node.leaf) {
      final before = node.children.length;
      node.children.removeWhere((child) => child.id == id);
      node.recomputeBounds();
      return node.children.length != before;
    }
    var removed = false;
    for (final child in [...node.children]) {
      final childNode = child.node;
      if (childNode == null) continue;
      if (_removeFrom(childNode, id)) {
        removed = true;
        child.bounds = childNode.children.isEmpty
            ? const Bounds2(0, 0, 0, 0)
            : childNode.bounds;
      }
    }
    node.children.removeWhere(
      (child) => child.node != null && child.node!.children.isEmpty,
    );
    node.recomputeBounds();
    return removed;
  }

  void _shrinkRoot() {
    while (!_root.leaf && _root.children.length == 1) {
      final only = _root.children.single.node;
      if (only == null) break;
      _root = only;
    }
  }

  void _queryNode(_Node<T> node, Bounds2 area, List<RTreeEntry<T>> result) {
    for (final child in node.children) {
      if (!child.bounds.intersects(area)) continue;
      if (node.leaf) {
        result.add(RTreeEntry(child.id, child.bounds, child.value as T));
      } else {
        final childNode = child.node;
        if (childNode != null) _queryNode(childNode, area, result);
      }
    }
  }

  _Node<T> _splitNode(_Node<T> node) {
    final entries = [...node.children];
    if (entries.length <= maxEntries) return node;
    final assignedA = <_Child<T>>[];
    final assignedB = <_Child<T>>[];
    var seedA = 0;
    var seedB = 1;
    var worst = -double.infinity;
    for (var i = 0; i < entries.length; i++) {
      for (var j = i + 1; j < entries.length; j++) {
        final waste =
            entries[i].bounds.union(entries[j].bounds).area -
            entries[i].bounds.area -
            entries[j].bounds.area;
        if (waste > worst) {
          worst = waste;
          seedA = i;
          seedB = j;
        }
      }
    }
    final first = entries.removeAt(seedB);
    final second = entries.removeAt(seedA);
    assignedA.add(first);
    assignedB.add(second);
    var boundsA = first.bounds;
    var boundsB = second.bounds;
    while (entries.isNotEmpty) {
      _Child<T> next;
      final remaining = entries.length;
      if (assignedA.length + remaining <= minEntries) {
        next = entries.removeLast();
        assignedA.add(next);
        boundsA = boundsA.union(next.bounds);
        continue;
      }
      if (assignedB.length + remaining <= minEntries) {
        next = entries.removeLast();
        assignedB.add(next);
        boundsB = boundsB.union(next.bounds);
        continue;
      }
      var candidateIndex = 0;
      var bestDifference = -double.infinity;
      for (var i = 0; i < entries.length; i++) {
        final bounds = entries[i].bounds;
        final growthA = boundsA.union(bounds).area - boundsA.area;
        final growthB = boundsB.union(bounds).area - boundsB.area;
        final difference = (growthA - growthB).abs();
        if (difference > bestDifference) {
          bestDifference = difference;
          candidateIndex = i;
        }
      }
      next = entries.removeAt(candidateIndex);
      final growthA = boundsA.union(next.bounds).area - boundsA.area;
      final growthB = boundsB.union(next.bounds).area - boundsB.area;
      if (growthA < growthB ||
          (growthA == growthB && assignedA.length <= assignedB.length)) {
        assignedA.add(next);
        boundsA = boundsA.union(next.bounds);
      } else {
        assignedB.add(next);
        boundsB = boundsB.union(next.bounds);
      }
    }
    node.children
      ..clear()
      ..addAll(assignedA);
    node.recomputeBounds();
    final sibling = _Node<T>(leaf: node.leaf)..children.addAll(assignedB);
    sibling.recomputeBounds();
    return sibling;
  }
}

class _Node<T> {
  _Node({required this.leaf});
  final bool leaf;
  final List<_Child<T>> children = [];
  Bounds2 bounds = const Bounds2(0, 0, 0, 0);

  void recomputeBounds() {
    if (children.isEmpty) {
      bounds = const Bounds2(0, 0, 0, 0);
      return;
    }
    var result = children.first.bounds;
    for (final child in children.skip(1)) {
      result = result.union(child.bounds);
    }
    bounds = result;
  }
}

class _Child<T> {
  _Child.leaf(this.id, this.bounds, T this.value) : node = null;
  _Child.node(this.bounds, _Node<T> this.node) : id = '', value = null;

  final String id;
  Bounds2 bounds;
  final T? value;
  final _Node<T>? node;
}

/// Document-aware spatial index. Unbounded objects (lines, function graphs,
/// axes) are always returned because they may cross any finite viewport.
class SpatialIndex {
  SpatialIndex(Iterable<GeometryObject> objects) {
    for (final object in objects) {
      add(object);
    }
  }

  final RTree<GeometryObject> _tree = RTree<GeometryObject>();
  final Map<String, GeometryObject> _unbounded = {};

  int get length => _tree.length + _unbounded.length;
  int get indexedObjectCount => _tree.length;

  void add(GeometryObject object) {
    final bounds = object.bounds;
    if (bounds == null) {
      _unbounded[object.id] = object;
    } else {
      _tree.insert(object.id, bounds, object);
    }
  }

  void remove(String id) {
    _unbounded.remove(id);
    _tree.remove(id);
  }

  void clear() {
    _unbounded.clear();
    _tree.clear();
  }

  List<GeometryObject> query(Bounds2 viewport) {
    final result = <GeometryObject>[
      ..._tree.search(viewport).where(_isObjectVisible),
      ..._unbounded.values.where(_isObjectVisible),
    ]..sort((a, b) => a.id.compareTo(b.id));
    return result;
  }

  GeometryObject? hitTest(
    Point2 point, {
    double tolerance = 6,
    bool Function(GeometryObject object)? filter,
  }) {
    final area = Bounds2(
      point.x - tolerance,
      point.y - tolerance,
      point.x + tolerance,
      point.y + tolerance,
    );
    final candidates = query(area);
    GeometryObject? best;
    var bestDistance = double.infinity;
    for (final object in candidates) {
      if (filter != null && !filter(object)) continue;
      final distance = distanceToObject(object, point);
      if (distance <= tolerance && distance < bestDistance) {
        best = object;
        bestDistance = distance;
      }
    }
    return best;
  }

  static bool _isObjectVisible(GeometryObject object) => object.visible;

  static double distanceToObject(GeometryObject object, Point2 point) {
    switch (object.kind) {
      case GeometryKind.point:
        return point.distanceTo(object.points.first);
      case GeometryKind.vector:
      case GeometryKind.segment:
        return distancePointToSegment(
          point,
          object.points[0],
          object.points[1],
        );
      case GeometryKind.line:
        return distancePointToLine(point, object.points[0], object.points[1]);
      case GeometryKind.ray:
        final a = object.points[0];
        final b = object.points[1];
        final t =
            (point - a).dot(b - a) /
            (b - a).dot(b - a).clamp(1e-30, double.infinity);
        return t < 0 ? point.distanceTo(a) : distancePointToLine(point, a, b);
      case GeometryKind.circle:
        final center = object.points[0];
        final radius = center.distanceTo(object.points[1]);
        return (point.distanceTo(center) - radius).abs();
      case GeometryKind.arc:
        final center = object.points[0];
        final radius = center.distanceTo(object.points[1]);
        return (point.distanceTo(center) - radius).abs();
      case GeometryKind.triangle:
      case GeometryKind.polygon:
        if (pointInPolygon(point, object.points)) return 0;
        var result = double.infinity;
        for (var i = 0; i < object.points.length; i++) {
          result = math.min(
            result,
            distancePointToSegment(
              point,
              object.points[i],
              object.points[(i + 1) % object.points.length],
            ),
          );
        }
        return result;
      case GeometryKind.conic:
        if (object.points.isEmpty) return double.infinity;
        return distancePointToSegment(
          point,
          object.points.first,
          object.points.last,
        );
      case GeometryKind.function:
      case GeometryKind.coordinate:
        return double.infinity;
      case GeometryKind.solid:
        var result = double.infinity;
        for (var i = 0; i < object.points.length; i++) {
          for (var j = i + 1; j < object.points.length; j++) {
            result = math.min(
              result,
              distancePointToSegment(point, object.points[i], object.points[j]),
            );
          }
        }
        return result;
    }
  }
}
