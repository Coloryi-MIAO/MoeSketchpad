// SPDX-License-Identifier: GPL-3.0-only
import 'package:flutter_bloc/flutter_bloc.dart';

class ThemeState {
  const ThemeState({this.cute = true, this.fontFamily = 'Microsoft YaHei'});

  final bool cute;
  final String fontFamily;

  ThemeState copyWith({bool? cute, String? fontFamily}) => ThemeState(
    cute: cute ?? this.cute,
    fontFamily: fontFamily ?? this.fontFamily,
  );
}

class ThemeBloc extends Cubit<ThemeState> {
  ThemeBloc() : super(const ThemeState());

  void toggleCute() => emit(state.copyWith(cute: !state.cute));
  void setFont(String family) => emit(state.copyWith(fontFamily: family));
}
