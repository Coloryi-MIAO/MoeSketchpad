// SPDX-License-Identifier: GPL-3.0-only
import 'dart:ui';

import 'package:flutter_bloc/flutter_bloc.dart';

class LocaleState {
  const LocaleState(this.locale);
  final Locale locale;
}

class LocaleBloc extends Cubit<LocaleState> {
  LocaleBloc() : super(const LocaleState(Locale('zh')));

  void setLanguage(String code) {
    if (code != 'zh' && code != 'en') return;
    emit(LocaleState(Locale(code)));
  }

  void toggle() => setLanguage(state.locale.languageCode == 'zh' ? 'en' : 'zh');
}
