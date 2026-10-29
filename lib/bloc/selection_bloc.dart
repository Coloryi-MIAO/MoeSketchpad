// SPDX-License-Identifier: GPL-3.0-only
import 'package:flutter_bloc/flutter_bloc.dart';

class SelectionState {
  const SelectionState({this.ids = const <String>{}});
  final Set<String> ids;

  String? get primary => ids.isEmpty ? null : ids.first;
  bool contains(String id) => ids.contains(id);
}

class SelectionBloc extends Cubit<SelectionState> {
  SelectionBloc() : super(const SelectionState());

  void replace(String? id) =>
      emit(SelectionState(ids: id == null ? const {} : {id}));

  void replaceAll(Iterable<String> ids) =>
      emit(SelectionState(ids: ids.toSet()));

  void toggle(String id) {
    final next = {...state.ids};
    if (!next.add(id)) next.remove(id);
    emit(SelectionState(ids: next));
  }

  void clear() => emit(const SelectionState());
}
