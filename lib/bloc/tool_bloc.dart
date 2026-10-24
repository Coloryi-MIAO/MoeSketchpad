// SPDX-License-Identifier: GPL-3.0-only
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:moesketchpad_core/moesketchpad_core.dart';

enum MoeTool {
  select,
  point,
  segment,
  line,
  circle,
  triangle,
  polygon,
  function,
  text,
  pan,
  zoom,
  rectangle,
  ellipse,
  freehand,
  fill,
  transparency,
  eyedropper,
  outline,
}

extension MoeToolCapability on MoeTool {
  bool get implementsGeometry =>
      this == MoeTool.select ||
      this == MoeTool.point ||
      this == MoeTool.segment ||
      this == MoeTool.line ||
      this == MoeTool.circle ||
      this == MoeTool.triangle ||
      this == MoeTool.polygon ||
      this == MoeTool.function ||
      this == MoeTool.pan ||
      this == MoeTool.zoom;
}

class ToolState {
  const ToolState({this.active = MoeTool.select, this.polygonDraft = const []});

  final MoeTool active;
  final List<Point2> polygonDraft;

  ToolState copyWith({MoeTool? active, List<Point2>? polygonDraft}) =>
      ToolState(
        active: active ?? this.active,
        polygonDraft: polygonDraft ?? this.polygonDraft,
      );
}

class ToolBloc extends Cubit<ToolState> {
  ToolBloc() : super(const ToolState());

  void select(MoeTool tool) => emit(ToolState(active: tool));
  void cancelDraft() => emit(state.copyWith(polygonDraft: const []));
}
