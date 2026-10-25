// SPDX-License-Identifier: GPL-3.0-only
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:moesketchpad_core/moesketchpad_core.dart';

enum MoeTool {
  select,
  point,
  segment,
  line,
  ray,
  vector,
  circle,
  arc,
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
