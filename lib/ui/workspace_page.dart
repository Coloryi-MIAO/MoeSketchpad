// SPDX-License-Identifier: GPL-3.0-only
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:moesketchpad_core/moesketchpad_core.dart';
import 'package:path/path.dart' as p;

import '../bloc/animation_bloc.dart';
import '../bloc/canvas_bloc.dart';
import '../bloc/document_bloc.dart';
import '../bloc/locale_bloc.dart';
import '../bloc/measure_bloc.dart';
import '../bloc/selection_bloc.dart';
import '../bloc/theme_bloc.dart';
import '../bloc/tool_bloc.dart';
import '../build_info.dart';
import '../l10n/app_localizations.dart';
import '../platform/close_guard.dart';
import '../platform/file_service.dart';
import 'canvas/sketchpad_canvas.dart';
import 'dialogs/about_dialog.dart';
import 'dialogs/password_dialog.dart';
import 'widgets/right_dock.dart';
import 'widgets/toolbox.dart';

class WorkspacePage extends StatefulWidget {
  const WorkspacePage({super.key, this.initialFilePath});
  final String? initialFilePath;

  @override
  State<WorkspacePage> createState() => _WorkspacePageState();
}

class _WorkspacePageState extends State<WorkspacePage> {
  bool _dockCollapsed = false;
  bool _closeRegistered = false;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _installCloseGuard();
      final initial = widget.initialFilePath;
      if (initial != null && mounted) {
        final picked = await FileService.readFromPath(initial);
        if (picked != null && mounted) {
          await _openPicked(picked);
        }
      }
    });
  }

  @override
  void dispose() {
    if (_closeRegistered) {
      CloseGuard.uninstall();
    }
    super.dispose();
  }

  Future<void> _installCloseGuard() async {
    if (_closeRegistered) return;
    try {
      await CloseGuard.install(
        confirmClose: _confirmWindowClose,
        hasUnsavedChanges: () =>
            mounted && context.read<DocumentBloc>().state.anyDirty,
      );
      _closeRegistered = true;
    } on Object {
      // In widget tests and unsupported shells the native close hook may be
      // unavailable. In-app tab close prompts still protect unsaved edits.
      _closeRegistered = false;
    }
  }

  Future<bool> _confirmWindowClose() async {
    if (_closing) return false;
    _closing = true;
    try {
      final bloc = context.read<DocumentBloc>();
      if (!bloc.state.anyDirty) return true;
      for (var index = 0; index < bloc.state.tabs.length; index++) {
        if (!mounted) return false;
        if (!bloc.state.tabs[index].dirty) continue;
        _activateTab(index);
        final tab = bloc.state.active;
        final l10n = AppLocalizations.of(context);
        final decision = await showSaveChangesDialog(
          context,
          _tabName(l10n, tab),
        );
        if (decision == SaveDecision.cancel) return false;
        if (decision == SaveDecision.save) {
          final saved = await _saveActive();
          if (!saved) return false;
        }
      }
      return true;
    } finally {
      _closing = false;
    }
  }

  Future<void> _newTab() async {
    final documentBloc = context.read<DocumentBloc>()..newDocument();
    context.read<CanvasBloc>().applyView(
      documentBloc.state.active.document.view,
    );
    context.read<SelectionBloc>().clear();
    context.read<AnimationBloc>().reset();
  }

  void _updateCanvasSetting(void Function(CanvasBloc bloc) update) {
    final canvas = context.read<CanvasBloc>();
    update(canvas);
    final documents = context.read<DocumentBloc>();
    documents.updateView(
      canvas.withCurrentSettings(documents.state.active.document.view),
    );
  }

  void _activateTab(int index) {
    final documents = context.read<DocumentBloc>();
    if (index == documents.state.activeIndex) return;
    documents.setActive(index);
    context.read<CanvasBloc>().applyView(documents.state.active.document.view);
    context.read<SelectionBloc>().clear();
    context.read<AnimationBloc>().reset();
  }

  Future<bool> _saveActive({bool saveAs = false}) async {
    final l10n = AppLocalizations.of(context);
    final documentBloc = context.read<DocumentBloc>();
    final canvasBloc = context.read<CanvasBloc>();
    final tab = documentBloc.state.active;
    final password = await showPasswordDialog(
      context,
      saving: true,
      fileName: _tabName(l10n, tab),
    );
    if (password == null) return false;
    try {
      final view = canvasBloc.toViewState();
      final document = documentBloc.documentForSave(view);
      final bytes = await MspCodec().encode(
        document,
        password: password,
        compress: true,
      );
      String? path;
      if (saveAs || tab.path == null) {
        path = await FileService.saveDocument(
          suggestedName: tab.path == null
              ? '${l10n.untitled(tab.untitledIndex)}.msp'
              : p.basename(tab.path!),
          bytes: bytes,
        );
      } else {
        final existing = tab.path!;
        path = existing;
        await FileService.writeToPath(existing, bytes);
      }
      if (path == null) return false;
      documentBloc.saveSucceeded(path, document);
      return true;
    } on MspFormatException catch (error) {
      _showError(l10n.saveFailed(error.message));
    } on FormatException catch (error) {
      _showError(l10n.saveFailed(error.message));
    } on Object catch (error) {
      _showError(l10n.saveFailed('$error'));
    }
    return false;
  }

  Future<void> _openFile() async {
    final picked = await FileService.openDocument();
    if (picked == null || !mounted) return;
    await _openPicked(picked);
  }

  Future<void> _openPicked(PickedFile picked) async {
    final l10n = AppLocalizations.of(context);
    final password = await showPasswordDialog(
      context,
      saving: false,
      fileName: picked.name,
    );
    if (password == null) return;
    try {
      final document = await MspCodec().decode(
        picked.bytes,
        password: password,
      );
      if (!mounted) return;
      context.read<DocumentBloc>().openDocument(
        document,
        path: picked.path ?? picked.name,
      );
      context.read<CanvasBloc>().applyView(document.view);
      context.read<SelectionBloc>().clear();
      context.read<AnimationBloc>().reset();
    } on MspDecryptionException {
      _showError(l10n.invalidPassword);
    } on MspFormatException catch (error) {
      _showError(l10n.openFailed(error.message));
    } on FormatException catch (error) {
      _showError(l10n.openFailed(error.message));
    } on Object catch (error) {
      _showError(l10n.openFailed('$error'));
    }
  }

  Future<void> _closeTab(int index) async {
    final l10n = AppLocalizations.of(context);
    final bloc = context.read<DocumentBloc>();
    if (index < 0 || index >= bloc.state.tabs.length) return;
    final tab = bloc.state.tabs[index];
    if (tab.dirty) {
      _activateTab(index);
      final decision = await showSaveChangesDialog(
        context,
        _tabName(l10n, tab),
      );
      if (decision == SaveDecision.cancel) return;
      if (decision == SaveDecision.save) {
        final saved = await _saveActive();
        if (!saved) return;
      }
    }
    if (!mounted) return;
    final previousActiveId = bloc.state.active.id;
    bloc.forceClose(index);
    if (bloc.state.active.id != previousActiveId) {
      context.read<CanvasBloc>().applyView(bloc.state.active.document.view);
    }
    context.read<SelectionBloc>().clear();
    context.read<AnimationBloc>().reset();
  }

  String _tabName(AppLocalizations l10n, DocumentTab tab) => tab.path == null
      ? l10n.untitled(tab.untitledIndex)
      : p.basename(tab.path!);

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xff9e3f3a),
        duration: const Duration(seconds: 5),
      ),
    );
  }

  void _showInfo(String message) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  void _deleteSelection() {
    final selection = context.read<SelectionBloc>().state.ids;
    if (selection.isEmpty) return;
    context.read<DocumentBloc>().deleteObjects(selection);
    context.read<SelectionBloc>().clear();
  }

  Future<void> _addMeasurement(MeasurementType type) async {
    final l10n = AppLocalizations.of(context);
    final selection = context.read<SelectionBloc>().state.ids;
    if (selection.isEmpty) {
      _showInfo(l10n.selectObjectFirst);
      return;
    }
    final object = context
        .read<DocumentBloc>()
        .state
        .active
        .document
        .objectById(selection.first);
    if (object == null) return;
    try {
      final measurement = Measurement(
        id: 'measure-${DateTime.now().microsecondsSinceEpoch}',
        type: type,
        targetIds: [object.id],
        unit: switch (context.read<CanvasBloc>().state.unit) {
          'mm' => MeasureUnit.mm,
          'cm' => MeasureUnit.cm,
          'px' => MeasureUnit.px,
          _ => MeasureUnit.unitless,
        },
      );
      const MeasurementEngine().measure(
        measurement,
        context.read<DocumentBloc>().state.active.document,
      );
      context.read<DocumentBloc>().addMeasurement(measurement);
    } on FormatException catch (error) {
      _showInfo(error.message);
    }
  }

  Future<void> _addAnimation() async {
    final document = context.read<DocumentBloc>().state.active.document;
    final points = document.objects
        .where(
          (object) =>
              object.kind == GeometryKind.point ||
              object.kind == GeometryKind.vector,
        )
        .toList();
    final paths = document.objects.where((object) {
      return [
        GeometryKind.segment,
        GeometryKind.line,
        GeometryKind.ray,
        GeometryKind.circle,
        GeometryKind.arc,
        GeometryKind.polygon,
        GeometryKind.triangle,
        GeometryKind.function,
      ].contains(object.kind);
    }).toList();
    final l10n = AppLocalizations.of(context);
    if (points.isEmpty || paths.isEmpty) {
      _showInfo(l10n.addAnimationRequirement);
      return;
    }
    final selection = context.read<SelectionBloc>().state.ids.toList();
    final selectedPoint = points.where((point) => selection.contains(point.id));
    final selectedPath = paths.where((path) => selection.contains(path.id));
    final spec = await showDialog<({String point, String path})>(
      context: context,
      builder: (_) => _AnimationDialog(
        points: points,
        paths: paths,
        initialPoint: selectedPoint.isNotEmpty
            ? selectedPoint.first.id
            : points.first.id,
        initialPath: selectedPath.isNotEmpty
            ? selectedPath.first.id
            : paths.first.id,
      ),
    );
    if (spec == null || !mounted) return;
    context.read<DocumentBloc>().addAnimation(
      AnimationSpec(
        id: 'animation-${DateTime.now().microsecondsSinceEpoch}',
        targetId: spec.point,
        pathObjectId: spec.path,
        loop: true,
        trail: 30,
      ),
    );
    final state = context.read<DocumentBloc>().state;
    final animation = state.active.document.animations.last;
    context.read<AnimationBloc>()
      ..select(animation.id)
      ..play();
  }

  void _applyAi(GeometryDocument preview) {
    context.read<DocumentBloc>().commitDocument(preview);
    context.read<SelectionBloc>().clear();
    context.read<MeasureBloc>().refresh(preview);
    context.read<AnimationBloc>().reset();
  }

  void _onMenuAction(String action) {
    final l10n = AppLocalizations.of(context);
    switch (action) {
      case 'new':
        _newTab();
      case 'open':
        _openFile();
      case 'save':
        _saveActive();
      case 'saveAs':
        _saveActive(saveAs: true);
      case 'undo':
        context.read<DocumentBloc>().undo();
      case 'redo':
        context.read<DocumentBloc>().redo();
      case 'delete':
        _deleteSelection();
      case 'toggleGrid':
        _updateCanvasSetting((canvas) => canvas.toggleGrid());
      case 'snapGrid':
        final canvas = context.read<CanvasBloc>().state;
        _updateCanvasSetting((bloc) => bloc.setSnapGrid(!canvas.snapGrid));
      case 'snapObjects':
        final canvas = context.read<CanvasBloc>().state;
        _updateCanvasSetting(
          (bloc) => bloc.setSnapObjects(!canvas.snapObjects),
        );
      case 'fitView':
        context.read<CanvasBloc>().fitBounds(
          context.read<DocumentBloc>().state.active.document.contentBounds,
        );
      case 'resetOrigin':
        context.read<CanvasBloc>().resetOrigin();
      case 'toggleDock':
        setState(() => _dockCollapsed = !_dockCollapsed);
      case 'settings':
        _showSettings();
      case 'about':
        showAboutMoeSketchpad(context);
      case 'closeTab':
        _closeTab(context.read<DocumentBloc>().state.activeIndex);
      case 'exportPage':
        _showInfo(l10n.notImplemented(l10n.exportPage));
      default:
        _showInfo(l10n.notImplemented(action));
    }
  }

  Future<void> _showSettings() async {
    final l10n = AppLocalizations.of(context);
    var cute = context.read<ThemeBloc>().state.cute;
    var font = context.read<ThemeBloc>().state.fontFamily;
    var language = context.read<LocaleBloc>().state.locale.languageCode;
    const fonts = [
      'Microsoft YaHei',
      'Microsoft YaHei UI',
      'PingFang SC',
      'Noto Sans CJK SC',
      'Segoe UI',
      'sans-serif',
      'monospace',
    ];
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(l10n.settings),
          content: SizedBox(
            width: 430,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.cuteTheme),
                  value: cute,
                  onChanged: (value) {
                    setDialogState(() => cute = value);
                    context.read<ThemeBloc>().toggleCute();
                  },
                ),
                const SizedBox(height: 5),
                DropdownButtonFormField<String>(
                  key: ValueKey(font),
                  initialValue: fonts.contains(font) ? font : fonts.first,
                  decoration: InputDecoration(labelText: l10n.font),
                  items: [
                    for (final item in fonts)
                      DropdownMenuItem(value: item, child: Text(item)),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setDialogState(() => font = value);
                    context.read<ThemeBloc>().setFont(value);
                  },
                ),
                const SizedBox(height: 6),
                Text(
                  l10n.fontCuratedNotice,
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xff778696),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  key: ValueKey(language),
                  initialValue: language,
                  decoration: InputDecoration(labelText: l10n.language),
                  items: const [
                    DropdownMenuItem(value: 'zh', child: Text('简体中文')),
                    DropdownMenuItem(value: 'en', child: Text('English')),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setDialogState(() => language = value);
                    context.read<LocaleBloc>().setLanguage(value);
                  },
                ),
                const SizedBox(height: 12),
                Text(
                  '${BuildInfo.version}+${BuildInfo.buildNumber} · ${BuildInfo.license}',
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xff778696),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(l10n.close),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final documentState = context.watch<DocumentBloc>().state;
    final themeState = context.watch<ThemeBloc>().state;
    final active = documentState.active;
    context.watch<SelectionBloc>();
    return MultiBlocListener(
      listeners: [
        BlocListener<DocumentBloc, DocumentState>(
          listenWhen: (previous, current) =>
              !identical(previous.active.document, current.active.document),
          listener: (context, state) {
            context.read<MeasureBloc>().refresh(state.active.document);
            final selection = context.read<SelectionBloc>();
            final ids = selection.state.ids
                .where((id) => state.active.document.objectById(id) != null)
                .toSet();
            if (ids.length != selection.state.ids.length) {
              selection.replaceAll(ids);
            }
          },
        ),
        BlocListener<DocumentBloc, DocumentState>(
          listenWhen: (previous, current) =>
              previous.activeIndex != current.activeIndex,
          listener: (context, state) {
            context.read<CanvasBloc>().applyView(state.active.document.view);
            context.read<SelectionBloc>().clear();
            context.read<AnimationBloc>().reset();
          },
        ),
      ],
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyN, control: true):
              _newTab,
          const SingleActivator(LogicalKeyboardKey.keyO, control: true):
              _openFile,
          const SingleActivator(LogicalKeyboardKey.keyS, control: true):
              _saveActive,
          const SingleActivator(
            LogicalKeyboardKey.keyS,
            control: true,
            shift: true,
          ): () =>
              _saveActive(saveAs: true),
          const SingleActivator(LogicalKeyboardKey.keyZ, control: true): () =>
              context.read<DocumentBloc>().undo(),
          const SingleActivator(LogicalKeyboardKey.keyY, control: true): () =>
              context.read<DocumentBloc>().redo(),
          const SingleActivator(
            LogicalKeyboardKey.keyZ,
            control: true,
            shift: true,
          ): () =>
              context.read<DocumentBloc>().redo(),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            backgroundColor: themeState.cute
                ? const Color(0xfff1edf3)
                : const Color(0xffe2e5e9),
            body: SafeArea(
              child: Column(
                children: [
                  _menuBar(l10n),
                  _standardBar(l10n, documentState),
                  _contextBar(l10n, documentState),
                  Expanded(
                    child: Row(
                      children: [
                        BlocBuilder<ToolBloc, ToolState>(
                          builder: (context, toolState) => ToolBox(
                            active: toolState.active,
                            cute: themeState.cute,
                            onSelected: (tool) =>
                                context.read<ToolBloc>().select(tool),
                          ),
                        ),
                        Expanded(
                          child: SketchpadCanvas(
                            onNewDocument: _newTab,
                            onOpenFile: _openFile,
                            onSave: () => _saveActive(),
                            onUndo: documentState.canUndo
                                ? () => context.read<DocumentBloc>().undo()
                                : null,
                            onRedo: documentState.canRedo
                                ? () => context.read<DocumentBloc>().redo()
                                : null,
                            onFitView: () =>
                                context.read<CanvasBloc>().fitBounds(
                                  documentState.active.document.contentBounds,
                                ),
                            onToggleGrid: () => _updateCanvasSetting(
                              (canvas) => canvas.toggleGrid(),
                            ),
                            onToggleGridSnap: () {
                              final snapGrid = context
                                  .read<CanvasBloc>()
                                  .state
                                  .snapGrid;
                              _updateCanvasSetting(
                                (canvas) => canvas.setSnapGrid(!snapGrid),
                              );
                            },
                            onToggleObjectSnap: () {
                              final snapObjects = context
                                  .read<CanvasBloc>()
                                  .state
                                  .snapObjects;
                              _updateCanvasSetting(
                                (canvas) => canvas.setSnapObjects(!snapObjects),
                              );
                            },
                          ),
                        ),
                        RightDock(
                          cute: themeState.cute,
                          collapsed: _dockCollapsed,
                          onToggle: () =>
                              setState(() => _dockCollapsed = !_dockCollapsed),
                          onAddMeasurement: _addMeasurement,
                          onAddAnimation: _addAnimation,
                          onApplyAi: _applyAi,
                        ),
                      ],
                    ),
                  ),
                  _documentTabs(l10n, documentState),
                  _statusBar(l10n, active),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _menuBar(AppLocalizations l10n) {
    final menus = <Widget>[
      _topMenu(l10n.menuFile, [
        _menuItem('new', l10n.newDocument, Icons.note_add_outlined),
        _menuItem('open', l10n.open, Icons.folder_open_outlined),
        _menuItem('save', l10n.save, Icons.save_outlined),
        _menuItem('saveAs', l10n.saveAs, Icons.save_as_outlined),
        _menuItem('exportPage', l10n.exportPage, Icons.ios_share),
        _menuItem('closeTab', l10n.closeTab, Icons.close),
      ]),
      _topMenu(l10n.menuEdit, [
        _menuItem('undo', l10n.undo, Icons.undo),
        _menuItem('redo', l10n.redo, Icons.redo),
        _menuItem('delete', l10n.deleteSelection, Icons.delete_outline),
      ]),
      _topMenu(l10n.menuView, [
        _menuItem('toggleGrid', l10n.grid, Icons.grid_4x4),
        _menuItem('snapGrid', l10n.snapGrid, Icons.grid_on),
        _menuItem('snapObjects', l10n.snapObjects, Icons.hub_outlined),
        _menuItem('fitView', l10n.fitView, Icons.fit_screen),
        _menuItem('resetOrigin', l10n.resetOrigin, Icons.my_location),
      ]),
      _topMenu(l10n.menuLayout, [
        _menuItem('toggleDock', l10n.properties, Icons.view_sidebar_outlined),
      ]),
      _topMenu(l10n.menuObject, [
        _menuItem('delete', l10n.deleteSelection, Icons.delete_outline),
      ]),
      _topMenu(l10n.menuEffects, [
        _menuItem(
          'planned',
          l10n.notImplemented(l10n.menuEffects),
          Icons.construction,
        ),
      ]),
      _topMenu(l10n.menuText, [
        _menuItem(
          'planned',
          l10n.notImplemented(l10n.menuText),
          Icons.construction,
        ),
      ]),
      _topMenu(l10n.menuTable, [
        _menuItem(
          'planned',
          l10n.notImplemented(l10n.menuTable),
          Icons.construction,
        ),
      ]),
      _topMenu(l10n.menuTools, [
        _menuItem('settings', l10n.settings, Icons.settings_outlined),
      ]),
      _topMenu(l10n.menuWindow, [
        _menuItem('toggleDock', l10n.properties, Icons.view_sidebar_outlined),
      ]),
      _topMenu(l10n.menuHelp, [
        _menuItem('about', l10n.about, Icons.info_outline),
      ]),
    ];
    final compact = MediaQuery.sizeOf(context).width < 1100;
    return Container(
      height: compact ? 68 : 40,
      decoration: BoxDecoration(
        color: context.watch<ThemeBloc>().state.cute
            ? const Color(0xfff3eaf1)
            : const Color(0xffe4eaf0),
        border: const Border(bottom: BorderSide(color: Color(0xffb8c3ce))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          const Icon(Icons.gesture, size: 20, color: Color(0xff914967)),
          const SizedBox(width: 6),
          Text(
            l10n.appTitle,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Color(0xff203548),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: compact
                ? Wrap(
                    spacing: 0,
                    runSpacing: 0,
                    alignment: WrapAlignment.start,
                    children: menus,
                  )
                : SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(children: menus),
                  ),
          ),
          _barButton(
            Icons.translate,
            l10n.language,
            context.read<LocaleBloc>().toggle,
          ),
          _barButton(
            context.read<ThemeBloc>().state.cute
                ? Icons.auto_awesome
                : Icons.tune,
            context.read<ThemeBloc>().state.cute
                ? l10n.professionalTheme
                : l10n.cuteTheme,
            context.read<ThemeBloc>().toggleCute,
          ),
        ],
      ),
    );
  }

  PopupMenuItem<String> _menuItem(String action, String label, IconData icon) =>
      PopupMenuItem(
        value: action,
        height: 34,
        child: Row(
          children: [
            Icon(icon, size: 15, color: const Color(0xff526576)),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(fontSize: 11.5)),
          ],
        ),
      );

  Widget _topMenu(String label, List<PopupMenuItem<String>> items) {
    return PopupMenuButton<String>(
      tooltip: '',
      position: PopupMenuPosition.under,
      onSelected: _onMenuAction,
      itemBuilder: (context) => items,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xfffbfcfd),
          border: Border.all(color: const Color(0xffb8c3ce)),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 11.5,
            color: Color(0xff203548),
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _standardBar(AppLocalizations l10n, DocumentState documentState) {
    return Container(
      height: 43,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: const BoxDecoration(
        color: Color(0xfffdfdfd),
        border: Border(bottom: BorderSide(color: Color(0xffd6dade))),
      ),
      child: Row(
        children: [
          _barButton(Icons.note_add_outlined, l10n.newDocument, _newTab),
          _barButton(Icons.folder_open_outlined, l10n.open, _openFile),
          _barButton(Icons.save_outlined, l10n.save, () => _saveActive()),
          const _BarDivider(),
          _barButton(
            Icons.undo,
            l10n.undo,
            documentState.canUndo
                ? () => context.read<DocumentBloc>().undo()
                : null,
          ),
          _barButton(
            Icons.redo,
            l10n.redo,
            documentState.canRedo
                ? () => context.read<DocumentBloc>().redo()
                : null,
          ),
          const _BarDivider(),
          BlocBuilder<CanvasBloc, CanvasState>(
            builder: (context, canvas) {
              final percent = (canvas.zoom * 100).round();
              return PopupMenuButton<String>(
                tooltip: l10n.zoom,
                onSelected: (value) {
                  if (value == 'fit') {
                    context.read<CanvasBloc>().fitBounds(
                      context
                          .read<DocumentBloc>()
                          .state
                          .active
                          .document
                          .contentBounds,
                    );
                  } else {
                    context.read<CanvasBloc>().setZoom(
                      double.parse(value) / 100,
                    );
                  }
                },
                itemBuilder: (context) => [
                  for (final value in [25, 50, 75, 100, 150, 200, 400, 800])
                    PopupMenuItem(
                      value: '$value',
                      height: 32,
                      child: Text(
                        '$value%',
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                  PopupMenuItem(
                    value: 'fit',
                    height: 32,
                    child: Text(
                      l10n.fitView,
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                ],
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xffd4dbe2)),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Row(
                    children: [
                      Text('$percent%', style: const TextStyle(fontSize: 11)),
                      const Icon(Icons.arrow_drop_down, size: 15),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(width: 6),
          BlocBuilder<CanvasBloc, CanvasState>(
            builder: (context, canvas) => DropdownButton<String>(
              value: const ['mm', 'cm', 'px'].contains(canvas.unit)
                  ? canvas.unit
                  : 'mm',
              isDense: true,
              underline: const SizedBox.shrink(),
              style: const TextStyle(fontSize: 11, color: Color(0xff34495d)),
              items: const [
                DropdownMenuItem(value: 'mm', child: Text('mm')),
                DropdownMenuItem(value: 'cm', child: Text('cm')),
                DropdownMenuItem(value: 'px', child: Text('px')),
              ],
              onChanged: (value) {
                if (value == null) return;
                _updateCanvasSetting((canvas) => canvas.setUnit(value));
              },
            ),
          ),
          const _BarDivider(),
          BlocBuilder<CanvasBloc, CanvasState>(
            builder: (context, canvas) => Row(
              children: [
                _barButton(
                  canvas.showGrid ? Icons.grid_on : Icons.grid_off,
                  l10n.grid,
                  () => _updateCanvasSetting((bloc) => bloc.toggleGrid()),
                  active: canvas.showGrid,
                ),
                _barButton(
                  Icons.grid_4x4,
                  l10n.snapGrid,
                  () => _updateCanvasSetting(
                    (bloc) => bloc.setSnapGrid(!canvas.snapGrid),
                  ),
                  active: canvas.snapGrid,
                ),
                _barButton(
                  Icons.hub_outlined,
                  l10n.snapObjects,
                  () => _updateCanvasSetting(
                    (bloc) => bloc.setSnapObjects(!canvas.snapObjects),
                  ),
                  active: canvas.snapObjects,
                ),
              ],
            ),
          ),
          const Spacer(),
          Text(
            l10n.experimental,
            style: const TextStyle(fontSize: 9, color: Color(0xff9a7a85)),
          ),
        ],
      ),
    );
  }

  Widget _barButton(
    IconData icon,
    String tooltip,
    VoidCallback? onPressed, {
    bool active = false,
  }) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
      style: IconButton.styleFrom(
        foregroundColor: active
            ? const Color(0xff164f79)
            : const Color(0xff263b4f),
        backgroundColor: active
            ? const Color(0xffdcecf8)
            : const Color(0xfffbfcfd),
        side: BorderSide(
          color: active ? const Color(0xff6394b9) : const Color(0xffb8c3ce),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
        padding: const EdgeInsets.all(5),
      ),
    );
  }

  Widget _contextBar(AppLocalizations l10n, DocumentState documentState) {
    final selection = context.watch<SelectionBloc>().state;
    final object = selection.ids.isEmpty
        ? null
        : documentState.active.document.objectById(selection.primary!);
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: const BoxDecoration(
        color: Color(0xfff6f7f9),
        border: Border(bottom: BorderSide(color: Color(0xffd6dade))),
      ),
      child: Row(
        children: [
          if (object == null) ...[
            Text(
              l10n.contextCanvas,
              style: const TextStyle(fontSize: 11, color: Color(0xff556779)),
            ),
            const Spacer(),
            BlocBuilder<CanvasBloc, CanvasState>(
              builder: (context, canvas) => Text(
                l10n.statusOrigin(
                  _number(canvas.origin.x),
                  _number(canvas.origin.y),
                ),
                style: const TextStyle(fontSize: 10, color: Color(0xff7a8897)),
              ),
            ),
          ] else ...[
            Icon(Icons.select_all, size: 15, color: const Color(0xff55728b)),
            const SizedBox(width: 6),
            Text(
              '${object.kind.name} · ${object.id}',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
            ),
            if (object.label?.isNotEmpty == true) ...[
              const SizedBox(width: 8),
              Text(
                object.label!,
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xff9a4f6d),
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
            const Spacer(),
            TextButton.icon(
              onPressed: () => _addMeasurement(MeasurementType.length),
              icon: const Icon(Icons.straighten, size: 14),
              label: Text(
                l10n.addMeasure,
                style: const TextStyle(fontSize: 11),
              ),
            ),
            IconButton(
              tooltip: l10n.deleteSelection,
              onPressed: _deleteSelection,
              icon: const Icon(Icons.delete_outline, size: 17),
            ),
          ],
        ],
      ),
    );
  }

  String _number(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1);

  Widget _documentTabs(AppLocalizations l10n, DocumentState state) {
    return Container(
      height: 30,
      decoration: const BoxDecoration(
        color: Color(0xffeef0f3),
        border: Border(top: BorderSide(color: Color(0xffd0d5db))),
      ),
      child: Row(
        children: [
          const SizedBox(width: 64),
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (var index = 0; index < state.tabs.length; index++)
                  _documentTab(
                    l10n,
                    state.tabs[index],
                    index,
                    state.activeIndex,
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: l10n.newTab,
            onPressed: _newTab,
            icon: const Icon(Icons.add, size: 16),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  Widget _documentTab(
    AppLocalizations l10n,
    DocumentTab tab,
    int index,
    int activeIndex,
  ) {
    final isActive = index == activeIndex;
    final cute = context.watch<ThemeBloc>().state.cute;
    return GestureDetector(
      onTap: () => _activateTab(index),
      child: Container(
        constraints: const BoxConstraints(minWidth: 140, maxWidth: 220),
        padding: const EdgeInsets.only(left: 12, right: 4),
        decoration: BoxDecoration(
          color: isActive ? Colors.white : const Color(0xffe7eaee),
          border: const Border(right: BorderSide(color: Color(0xffcdd3da))),
          borderRadius: isActive && cute
              ? const BorderRadius.vertical(top: Radius.circular(8))
              : null,
        ),
        child: Row(
          children: [
            Icon(
              Icons.description_outlined,
              size: 13,
              color: tab.dirty
                  ? const Color(0xffb2546f)
                  : const Color(0xff718293),
            ),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                '${_tabName(l10n, tab)}${tab.dirty ? ' *' : ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
            const Spacer(),
            InkWell(
              onTap: () => _closeTab(index),
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.close, size: 12, color: Color(0xff758493)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusBar(AppLocalizations l10n, DocumentTab tab) {
    return BlocBuilder<CanvasBloc, CanvasState>(
      builder: (context, canvas) => Container(
        height: 23,
        padding: const EdgeInsets.symmetric(horizontal: 9),
        decoration: const BoxDecoration(
          color: Color(0xfffcfcfc),
          border: Border(top: BorderSide(color: Color(0xffd8dce1))),
        ),
        child: Row(
          children: [
            Text(
              l10n.statusObjects(tab.document.objects.length),
              style: const TextStyle(fontSize: 10, color: Color(0xff485c6e)),
            ),
            const SizedBox(width: 14),
            if (canvas.cursorWorld != null)
              Text(
                'x ${canvas.cursorWorld!.x.toStringAsFixed(2)}  y ${canvas.cursorWorld!.y.toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 10, color: Color(0xff5e7080)),
              ),
            const Spacer(),
            Text(
              l10n.statusOrigin(
                canvas.origin.x.toStringAsFixed(1),
                canvas.origin.y.toStringAsFixed(1),
              ),
              style: const TextStyle(fontSize: 9.5, color: Color(0xff77899a)),
            ),
            const SizedBox(width: 12),
            Text(
              l10n.statusZoom((canvas.zoom * 100).round()),
              style: const TextStyle(fontSize: 10, color: Color(0xff485c6e)),
            ),
            const SizedBox(width: 12),
            Text(
              tab.path ?? l10n.untitled(tab.untitledIndex),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 9.5, color: Color(0xff77899a)),
            ),
          ],
        ),
      ),
    );
  }
}

class _BarDivider extends StatelessWidget {
  const _BarDivider();

  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    height: 22,
    margin: const EdgeInsets.symmetric(horizontal: 5),
    color: const Color(0xffd6dbe1),
  );
}

class _AnimationDialog extends StatefulWidget {
  const _AnimationDialog({
    required this.points,
    required this.paths,
    required this.initialPoint,
    required this.initialPath,
  });

  final List<GeometryObject> points;
  final List<GeometryObject> paths;
  final String initialPoint;
  final String initialPath;

  @override
  State<_AnimationDialog> createState() => _AnimationDialogState();
}

class _AnimationDialogState extends State<_AnimationDialog> {
  late String _point = widget.initialPoint;
  late String _path = widget.initialPath;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.addAnimation),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              key: ValueKey(_point),
              initialValue: _point,
              decoration: const InputDecoration(labelText: 'moving point'),
              items: [
                for (final object in widget.points)
                  DropdownMenuItem(
                    value: object.id,
                    child: Text(
                      '${object.label ?? object.id} (${object.kind.name})',
                    ),
                  ),
              ],
              onChanged: (value) => setState(() => _point = value ?? _point),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              key: ValueKey(_path),
              initialValue: _path,
              decoration: const InputDecoration(labelText: 'path'),
              items: [
                for (final object in widget.paths)
                  DropdownMenuItem(
                    value: object.id,
                    child: Text(object.label ?? object.id),
                  ),
              ],
              onChanged: (value) => setState(() => _path = value ?? _path),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(context).pop((point: _point, path: _path)),
          child: Text(l10n.playAnimation),
        ),
      ],
    );
  }
}
