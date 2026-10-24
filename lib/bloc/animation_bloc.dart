// SPDX-License-Identifier: GPL-3.0-only
import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

class AnimationState {
  const AnimationState({
    this.playing = false,
    this.elapsedSeconds = 0,
    this.speed = 1,
    this.activeAnimationId,
  });

  final bool playing;
  final double elapsedSeconds;
  final double speed;
  final String? activeAnimationId;

  AnimationState copyWith({
    bool? playing,
    double? elapsedSeconds,
    double? speed,
    String? activeAnimationId,
    bool clearActive = false,
  }) => AnimationState(
    playing: playing ?? this.playing,
    elapsedSeconds: elapsedSeconds ?? this.elapsedSeconds,
    speed: speed ?? this.speed,
    activeAnimationId: clearActive
        ? null
        : (activeAnimationId ?? this.activeAnimationId),
  );
}

class AnimationBloc extends Cubit<AnimationState> {
  AnimationBloc() : super(const AnimationState());

  Timer? _timer;
  DateTime? _lastTick;

  void select(String? id) {
    if (id == null) {
      pause();
      emit(state.copyWith(clearActive: true, elapsedSeconds: 0));
    } else {
      emit(state.copyWith(activeAnimationId: id, elapsedSeconds: 0));
    }
  }

  void play() {
    if (state.playing) return;
    _lastTick = DateTime.now();
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      final now = DateTime.now();
      final previous = _lastTick ?? now;
      _lastTick = now;
      final delta =
          (now.difference(previous).inMicroseconds / 1e6) * state.speed;
      emit(state.copyWith(elapsedSeconds: state.elapsedSeconds + delta));
    });
    emit(state.copyWith(playing: true));
  }

  void pause() {
    _timer?.cancel();
    _timer = null;
    _lastTick = null;
    if (state.playing) emit(state.copyWith(playing: false));
  }

  void reset() {
    pause();
    emit(state.copyWith(elapsedSeconds: 0));
  }

  void setSpeed(double speed) {
    if (!speed.isFinite || speed <= 0) return;
    emit(state.copyWith(speed: speed.clamp(0.05, 20)));
  }

  @override
  Future<void> close() {
    _timer?.cancel();
    return super.close();
  }
}
