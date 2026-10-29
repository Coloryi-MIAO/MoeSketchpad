// SPDX-License-Identifier: GPL-3.0-only
/// Deterministic animation evaluation. Rendering time never mutates geometry
/// source data; only the derived animated position is returned.
library;

import 'dart:math' as math;

import 'functions.dart';
import 'geometry/object.dart';
import 'geometry/point.dart';

class AnimationSample {
  const AnimationSample({
    required this.position,
    required this.phase,
    required this.trail,
    this.finished = false,
    this.error,
  });

  final Point2? position;
  final double phase;
  final List<Point2> trail;
  final bool finished;
  final String? error;
}

class AnimationEvaluator {
  const AnimationEvaluator();

  double normalizedPhase(AnimationSpec spec, double elapsedSeconds) {
    if (!elapsedSeconds.isFinite || !spec.speed.isFinite) return spec.t0;
    final span = spec.t1 - spec.t0;
    if (span == 0) return spec.t0;
    var raw = (elapsedSeconds * spec.speed) % 1.0;
    if (raw < 0) raw += 1;
    if (spec.pingPong) {
      raw = raw <= 0.5 ? raw * 2 : (1 - raw) * 2;
    } else if (!spec.loop) {
      raw = ((elapsedSeconds * spec.speed) / span).clamp(0.0, 1.0);
    }
    return spec.t0 + span * raw;
  }

  AnimationSample sample(
    GeometryDocument document,
    AnimationSpec spec,
    double elapsedSeconds, {
    int trailSamples = 60,
  }) {
    final path = spec.pathObjectId == null
        ? document.objectById(spec.targetId)
        : document.objectById(spec.pathObjectId!);
    final target = document.objectById(spec.targetId);
    if (path == null || target == null) {
      return AnimationSample(
        position: null,
        phase: 0,
        trail: const [],
        error: 'Animation path or target is missing.',
      );
    }
    final phase = normalizedPhase(spec, elapsedSeconds);
    const sampler = PathSampler();
    final position = sampler.positionAt(path, phase);
    if (position == null) {
      return AnimationSample(
        position: null,
        phase: phase,
        trail: const [],
        error: 'This path type cannot be animated.',
      );
    }
    final trail = <Point2>[];
    if (spec.trail > 0) {
      final count = math.min(spec.trail, math.max(1, trailSamples));
      final lookback = (spec.t1 - spec.t0) / 60;
      for (var i = count; i >= 1; i--) {
        final trailPhase = (phase - lookback * i).clamp(spec.t0, spec.t1);
        final point = sampler.positionAt(path, trailPhase);
        if (point != null) trail.add(point);
      }
    }
    final finished =
        !spec.loop &&
        !spec.pingPong &&
        elapsedSeconds * spec.speed >= (spec.t1 - spec.t0);
    return AnimationSample(
      position: position,
      phase: phase,
      trail: trail,
      finished: finished,
    );
  }

  /// Moves the animated target for rendering without modifying the document.
  GeometryObject targetAt(
    GeometryDocument document,
    AnimationSpec spec,
    double elapsedSeconds,
  ) {
    final target = document.objectById(spec.targetId);
    if (target == null) {
      throw const FormatException('Animation target does not exist.');
    }
    final result = sample(document, spec, elapsedSeconds);
    if (result.position == null) return target;
    final points = [...target.points];
    points[target.kind == GeometryKind.vector ? 1 : 0] = result.position!;
    return target.copyWith(points: points);
  }
}
