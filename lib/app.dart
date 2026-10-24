// SPDX-License-Identifier: GPL-3.0-only
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'bloc/ai_bloc.dart';
import 'bloc/animation_bloc.dart';
import 'bloc/canvas_bloc.dart';
import 'bloc/document_bloc.dart';
import 'bloc/locale_bloc.dart';
import 'bloc/measure_bloc.dart';
import 'bloc/selection_bloc.dart';
import 'bloc/theme_bloc.dart';
import 'bloc/tool_bloc.dart';
import 'l10n/app_localizations.dart';
import 'ui/workspace_page.dart';

class MoeSketchpadApp extends StatelessWidget {
  const MoeSketchpadApp({super.key, this.initialFilePath});

  final String? initialFilePath;

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => ThemeBloc()),
        BlocProvider(create: (_) => LocaleBloc()),
        BlocProvider(create: (_) => ToolBloc()),
        BlocProvider(create: (_) => SelectionBloc()),
        BlocProvider(create: (_) => CanvasBloc()),
        BlocProvider(create: (_) => DocumentBloc()),
        BlocProvider(create: (_) => MeasureBloc()),
        BlocProvider(create: (_) => AnimationBloc()),
        BlocProvider(create: (_) => AiBloc()),
      ],
      child: BlocBuilder<LocaleBloc, LocaleState>(
        builder: (context, localeState) => BlocBuilder<ThemeBloc, ThemeState>(
          builder: (context, themeState) => MaterialApp(
            debugShowCheckedModeBanner: false,
            onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
            locale: localeState.locale,
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            theme: _buildTheme(themeState),
            home: WorkspacePage(initialFilePath: initialFilePath),
          ),
        ),
      ),
    );
  }

  ThemeData _buildTheme(ThemeState state) {
    final cute = state.cute;
    final scheme = ColorScheme.fromSeed(
      seedColor: cute ? const Color(0xffb46685) : const Color(0xff376c98),
      brightness: Brightness.light,
    );
    return ThemeData(
      useMaterial3: false,
      colorScheme: scheme,
      fontFamily: state.fontFamily,
      fontFamilyFallback: const [
        'Microsoft YaHei UI',
        'PingFang SC',
        'Noto Sans CJK SC',
        'sans-serif',
      ],
      visualDensity: VisualDensity.compact,
      scaffoldBackgroundColor: cute
          ? const Color(0xffeeedf4)
          : const Color(0xffe4e7eb),
      dividerColor: cute ? const Color(0xffd8cfd9) : const Color(0xffc9cfd6),
      splashFactory: InkRipple.splashFactory,
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 500),
        decoration: BoxDecoration(
          color: const Color(0xee263746),
          borderRadius: BorderRadius.circular(cute ? 7 : 3),
        ),
        textStyle: const TextStyle(color: Colors.white, fontSize: 11),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cute ? 16 : 4),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cute ? 10 : 3),
        ),
      ),
    );
  }
}
