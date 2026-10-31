// SPDX-License-Identifier: GPL-3.0-only
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
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
import '../platform/device_document_key_store.dart';
import '../platform/document_file_name.dart';
import '../platform/file_service.dart';
import '../platform/recent_files_store.dart';
import '../platform/update_service.dart';
import '../services/animated_apng_exporter.dart';
import '../services/animated_gif_exporter.dart';
import '../services/document_command_executor.dart';
import 'canvas/sketchpad_canvas.dart';
import 'dialogs/about_dialog.dart';
import 'dialogs/password_dialog.dart';
import 'widgets/right_dock.dart';
import 'widgets/toolbox.dart';
import 'widgets/window_caption_bar.dart';

class WorkspacePage extends StatefulWidget {
  const WorkspacePage({super.key, this.initialFilePath});
  final String? initialFilePath;

  @override
  State<WorkspacePage> createState() => _WorkspacePageState();
}

Future<String> _resolvePasswordChoice(
  PasswordChoice choice, {
  required bool saving,
}) async {
  if (!choice.useDeviceKey) return choice.password;
  const keyStore = DeviceDocumentKeyStore();
  if (saving) return keyStore.readOrCreate();
  final key = await keyStore.read();
  if (key == null) {
    throw StateError(
      'No device key is stored here. Open the document with its password '
      'or on the device where it was created.',
    );
  }
  return key;
}

class _WorkspacePageState extends State<WorkspacePage> {
  final _canvasKey = GlobalKey<SketchpadCanvasState>();
  bool _dockCollapsed = false;
  bool _closeRegistered = false;
  bool _closing = false;
  List<String> _recentFiles = const [];
  final Map<String, String> _recoveryPasswords = {};
  Timer? _autoSaveTimer;
  bool _autoSaveBusy = false;
  final TextEditingController _widthController = TextEditingController();
  final TextEditingController _heightController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _installCloseGuard();
      await _loadRecentFiles();
      final initial = widget.initialFilePath;
      if (initial != null && mounted) {
        final picked = await FileService.readFromPath(initial);
        if (picked != null && mounted) {
          await _openPicked(picked);
        }
      }
      if (mounted) await _offerDraftRecovery();
    });
    _autoSaveTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => _autoSaveDirtyTabs(),
    );
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    _widthController.dispose();
    _heightController.dispose();
    if (_closeRegistered) {
      CloseGuard.uninstall();
    }
    super.dispose();
  }

  Future<void> _loadRecentFiles() async {
    try {
      final files = await const RecentFilesStore().read();
      if (mounted) setState(() => _recentFiles = files);
    } on Object catch (error) {
      if (mounted) _showError('Could not load recent files: $error');
    }
  }

  Future<void> _recordRecentPath(String path) async {
    try {
      final files = await const RecentFilesStore().record(path);
      if (mounted) setState(() => _recentFiles = files);
    } on Object catch (error) {
      if (mounted) _showError('Could not save recent files: $error');
    }
  }

  Future<void> _openRecent(String path) async {
    if (kIsWeb) {
      await _openFile();
      return;
    }
    try {
      final picked = await FileService.readFromPath(path);
      if (!mounted) return;
      if (picked == null) {
        _showError('Recent document no longer exists: $path');
        return;
      }
      await _openPicked(picked);
    } on Object catch (error) {
      if (mounted) {
        _showError(AppLocalizations.of(context).openFailed('$error'));
      }
    }
  }

  Future<void> _autoSaveDirtyTabs() async {
    if (!mounted || _autoSaveBusy) return;
    _autoSaveBusy = true;
    try {
      final documents = context.read<DocumentBloc>().state;
      final codec = MspCodec();
      for (final tab in documents.tabs) {
        if (!tab.dirty) continue;
        final password = _recoveryPasswords[tab.id];
        if (password == null) continue;
        try {
          final bytes = await codec.encode(tab.document, password: password);
          await FileService.writeRecovery(tab.id, Uint8List.fromList(bytes));
        } on Object catch (error) {
          if (mounted) _showError('Autosave failed: $error');
        }
      }
    } finally {
      _autoSaveBusy = false;
    }
  }

  Future<void> _offerDraftRecovery() async {
    if (!mounted) return;
    late final List<RecoveryDraft> drafts;
    try {
      drafts = await FileService.listRecovery();
    } on Object catch (error) {
      if (mounted) _showError('Could not inspect recovery drafts: $error');
      return;
    }
    if (drafts.isEmpty || !mounted) return;
    final selected = await showDialog<RecoveryDraft>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Recover an autosaved document?'),
        content: SizedBox(
          width: 360,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final draft in drafts)
                ListTile(
                  leading: const Icon(Icons.restore),
                  title: Text('Draft ${draft.key}'),
                  onTap: () => Navigator.of(dialogContext).pop(draft),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(AppLocalizations.of(context).cancel),
          ),
        ],
      ),
    );
    if (selected == null || !mounted) return;
    final choice = await showPasswordDialog(
      context,
      saving: false,
      fileName: 'Draft ${selected.key}',
    );
    if (choice == null || !mounted) return;
    try {
      final password = await _resolvePasswordChoice(choice, saving: false);
      final document = await MspCodec().decode(
        selected.bytes,
        password: password,
      );
      if (!mounted) return;
      final bloc = context.read<DocumentBloc>();
      bloc.recoverDocument(document);
      _recoveryPasswords[bloc.state.active.id] = password;
      context.read<CanvasBloc>().applyView(document.view);
      context.read<SelectionBloc>().clear();
      await FileService.deleteRecovery(selected.key);
    } on Object catch (error) {
      _showError('Could not recover draft: $error');
    }
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
      if (!bloc.state.anyDirty) {
        for (final tab in bloc.state.tabs) {
          await _deleteRecovery(tab.id);
        }
        return true;
      }
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
      for (final tab in bloc.state.tabs) {
        await _deleteRecovery(tab.id);
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
    final webFileName = kIsWeb ? await _requestWebFileName(tab, l10n) : null;
    if (!mounted) return false;
    if (kIsWeb && webFileName == null) return false;
    final choice = await showPasswordDialog(
      context,
      saving: true,
      fileName: webFileName ?? _tabName(l10n, tab),
    );
    if (choice == null) return false;
    try {
      final password = await _resolvePasswordChoice(choice, saving: true);
      final view = canvasBloc.toViewState();
      final document = documentBloc.documentForSave(view);
      final bytes = await MspCodec().encode(
        document,
        password: password,
        compress: true,
      );
      String? path;
      if (kIsWeb) {
        path = await FileService.saveDocument(
          suggestedName: webFileName!,
          bytes: bytes,
        );
      } else if (saveAs || tab.path == null) {
        path = await FileService.saveDocument(
          suggestedName: tab.path == null
              ? '${l10n.untitled(tab.untitledIndex)}.moesp'
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
      _recoveryPasswords[tab.id] = password;
      await _recordRecentPath(path);
      await _deleteRecovery(tab.id);
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

  Future<String?> _requestWebFileName(
    DocumentTab tab,
    AppLocalizations l10n,
  ) async {
    final controller = TextEditingController(
      text: tab.path == null
          ? l10n.untitled(tab.untitledIndex)
          : p.basenameWithoutExtension(tab.path!),
    );
    String? error;
    try {
      return await showDialog<String>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            void submit() {
              late String normalized;
              try {
                normalized = normalizeMoespFileName(controller.text);
              } on FormatException {
                setDialogState(() => error = l10n.invalidSaveFileName);
                return;
              }
              Navigator.of(dialogContext).pop(normalized);
            }

            return AlertDialog(
              title: Text(l10n.saveFileNameTitle),
              content: TextField(
                key: const ValueKey('web-save-file-name'),
                controller: controller,
                autofocus: true,
                maxLength: 120,
                decoration: InputDecoration(
                  labelText: l10n.saveFileNameLabel,
                  suffixText: '.moesp',
                  errorText: error,
                ),
                onSubmitted: (_) => submit(),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: Text(l10n.cancel),
                ),
                FilledButton(
                  key: const ValueKey('web-save-file-name-confirm'),
                  onPressed: submit,
                  child: Text(l10n.continueLabel),
                ),
              ],
            );
          },
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  Future<void> _openFile() async {
    final l10n = AppLocalizations.of(context);
    try {
      final picked = await FileService.openDocument();
      if (picked == null || !mounted) return;
      await _openPicked(picked);
    } on Object catch (error) {
      _showError(l10n.openFailed('$error'));
    }
  }

  Future<void> _openPicked(PickedFile picked) async {
    final l10n = AppLocalizations.of(context);
    final choice = await showPasswordDialog(
      context,
      saving: false,
      fileName: picked.name,
    );
    if (choice == null) return;
    try {
      final password = await _resolvePasswordChoice(choice, saving: false);
      final document = await MspCodec().decode(
        picked.bytes,
        password: password,
      );
      if (!mounted) return;
      context.read<DocumentBloc>().openDocument(
        document,
        path: picked.path ?? picked.name,
      );
      final documentBloc = context.read<DocumentBloc>();
      _recoveryPasswords[documentBloc.state.active.id] = password;
      await _recordRecentPath(picked.path ?? picked.name);
      if (!mounted) return;
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

  Future<void> _deleteRecovery(String id) async {
    try {
      await FileService.deleteRecovery(id);
    } on Object catch (error) {
      if (mounted) _showError('Could not clear recovery draft: $error');
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
    await _deleteRecovery(tab.id);
    if (!mounted) return;
    _recoveryPasswords.remove(tab.id);
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

  void _resizeSelected(GeometryObject object, double width, double height) {
    final bounds = object.bounds;
    if (bounds == null || bounds.width <= 0 || bounds.height <= 0) return;
    final sx = width / bounds.width;
    final sy = height / bounds.height;
    final center = bounds.center;
    final updated = object.copyWith(
      points: [
        for (final point in object.points)
          Point2(
            center.x + (point.x - center.x) * sx,
            center.y + (point.y - center.y) * sy,
          ),
      ],
    );
    context.read<DocumentBloc>().updateObject(updated);
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

  Future<String> _runDocumentCommand(String command) async {
    final documentBloc = context.read<DocumentBloc>();
    final current = documentBloc.state.active.document;
    final result = const DocumentCommandExecutor().execute(command, current);
    if (!identical(result.document, current)) {
      documentBloc.commitDocument(result.document);
      context.read<MeasureBloc>().refresh(result.document);
    }
    return result.message;
  }

  void _onMenuAction(String action) {
    final l10n = AppLocalizations.of(context);
    if (action.startsWith('recent-')) {
      final index = int.tryParse(action.substring('recent-'.length));
      if (index != null && index >= 0 && index < _recentFiles.length) {
        _openRecent(_recentFiles[index]);
        return;
      }
    }
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
      case 'measure':
        _addMeasurement(MeasurementType.length);
      case 'animate':
        _addAnimation();
      case 'label':
        _addTextAnnotation();
      case 'exportPage':
        _exportSvg();
      case 'exportGif':
        _exportAnimationGif();
      case 'exportApng':
        _exportAnimationApng();
      case 'closeTab':
        _closeTab(context.read<DocumentBloc>().state.activeIndex);
      case 'selectTool':
        context.read<ToolBloc>().select(MoeTool.select);
      case 'pointTool':
        context.read<ToolBloc>().select(MoeTool.point);
      case 'settings':
        _showSettings();
      case 'about':
        showAboutMoeSketchpad(context);
      case 'updates':
        _checkForUpdates();
      default:
        _showInfo(l10n.notImplemented(action));
    }
  }

  Future<void> _checkForUpdates() async {
    final l10n = AppLocalizations.of(context);
    if (kIsWeb || !const UpdateService().supported) {
      _showInfo(l10n.updateUnsupported);
      return;
    }
    try {
      final update = await const UpdateService().check(
        currentVersion: BuildInfo.version,
      );
      if (!mounted) return;
      if (update == null) {
        _showInfo(l10n.updateCurrent);
        return;
      }
      final shouldInstall = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(l10n.updateAvailable),
          content: Text(l10n.updateVersion(update.version)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.cancel),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              icon: const Icon(Icons.download),
              label: Text(l10n.updateDownload),
            ),
          ],
        ),
      );
      if (shouldInstall != true || !mounted) return;
      _showInfo(l10n.updateDownloading);
      final installer = await const UpdateService().downloadInstaller(update);
      if (!mounted) return;
      final canClose = await _confirmWindowClose();
      if (!canClose || !mounted) return;
      await const UpdateService().launchInstaller(installer);
    } on Object catch (error) {
      if (mounted) _showError(l10n.updateFailed('$error'));
    }
  }

  Future<void> _addTextAnnotation() async {
    final documentBloc = context.read<DocumentBloc>();
    final selection = context.read<SelectionBloc>().state;
    final selected = selection.primary == null
        ? null
        : documentBloc.state.active.document.objectById(selection.primary!);
    final controller = TextEditingController(text: selected?.label ?? '');
    try {
      final text = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(AppLocalizations.of(context).toolText),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 512,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'A',
            ),
            onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(AppLocalizations.of(context).cancel),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(controller.text.trim()),
              child: Text(AppLocalizations.of(context).save),
            ),
          ],
        ),
      );
      if (!mounted || text == null || text.trim().isEmpty) return;
      final value = text.trim();
      if (selected != null) {
        documentBloc.setLabel(selected.id, value);
        return;
      }
      final origin = context.read<CanvasBloc>().state.origin;
      documentBloc.addObject(
        GeometryObject(
          id: 'text-${DateTime.now().microsecondsSinceEpoch}',
          kind: GeometryKind.point,
          points: [origin],
          label: value,
          labelStyle: const LabelStyle(italic: false, fontSize: 18),
          style: const ObjectStyle(strokeColor: 0xff203548),
          params: const {'hideMarker': true},
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  Future<void> _exportSvg() async {
    final l10n = AppLocalizations.of(context);
    final document = context.read<DocumentBloc>().state.active.document;
    try {
      final viewport = _canvasKey.currentState?.viewportWorldBounds;
      if (viewport == null) {
        throw StateError('Canvas viewport is not ready for export.');
      }

      final svg = SvgExporter().exportViewport(document, viewport);
      await FileService.saveExport(
        suggestedName: '${document.title}.svg',
        bytes: Uint8List.fromList(utf8.encode(svg)),
        extension: 'svg',
        mimeType: 'image/svg+xml',
      );
    } on Object catch (error) {
      _showError(l10n.saveFailed('$error'));
    }
  }

  Future<void> _exportAnimationGif() async {
    await _exportAnimation(apng: false);
  }

  Future<void> _exportAnimationApng() async {
    await _exportAnimation(apng: true);
  }

  Future<void> _exportAnimation({required bool apng}) async {
    final document = context.read<DocumentBloc>().state.active.document;
    final format = apng ? 'APNG' : 'GIF';
    if (document.animations.isEmpty) {
      _showInfo(
        Localizations.localeOf(context).languageCode == 'zh'
            ? '请先为文档添加动点动画，才能导出 $format。'
            : 'Add a point animation before exporting $format.',
      );
      return;
    }
    final animation = document.animations.length == 1
        ? document.animations.single
        : await showDialog<AnimationSpec>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: Text(
                Localizations.localeOf(context).languageCode == 'zh'
                    ? '选择要导出的动画'
                    : 'Choose an animation to export',
              ),
              content: SizedBox(
                width: 360,
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final item in document.animations)
                      ListTile(
                        leading: const Icon(Icons.animation),
                        title: Text(item.id),
                        onTap: () => Navigator.of(dialogContext).pop(item),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: Text(AppLocalizations.of(context).cancel),
                ),
              ],
            ),
          );
    if (animation == null || !mounted) return;
    final language = Localizations.localeOf(context).languageCode;
    try {
      final viewport = _canvasKey.currentState?.viewportWorldBounds;
      if (viewport == null) {
        throw StateError('Canvas viewport is not ready for export.');
      }
      final bytes = apng
          ? const AnimatedApngExporter().export(
              document: document,
              animation: animation,
              viewport: viewport,
            )
          : const AnimatedGifExporter().export(
              document: document,
              animation: animation,
              viewport: viewport,
            );
      final tab = context.read<DocumentBloc>().state.active;
      final baseName = tab.path == null
          ? AppLocalizations.of(context).untitled(tab.untitledIndex)
          : p.basenameWithoutExtension(tab.path!);
      final extension = apng ? 'png' : 'gif';
      await FileService.saveExport(
        suggestedName: '$baseName.$extension',
        bytes: Uint8List.fromList(bytes),
        extension: extension,
        mimeType: apng ? 'image/apng' : 'image/gif',
      );
    } on Object catch (error) {
      if (mounted) {
        _showError(
          language == 'zh'
              ? '$format 导出失败：$error'
              : '$format export failed: $error',
        );
      }
    }
  }

  Future<void> _showSettings() async {
    final l10n = AppLocalizations.of(context);
    var cute = context.read<ThemeBloc>().state.cute;
    var font = context.read<ThemeBloc>().state.fontFamily;
    var language = context.read<LocaleBloc>().state.locale.languageCode;
    final fonts = kIsWeb
        ? const ['sans-serif', 'serif', 'monospace']
        : const [
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
                  style: TextStyle(fontSize: 10, color: Color(0xff778696)),
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
            body: Column(
              children: [
                // The desktop build hides the native title bar, so the app has
                // to draw its own caption. It stays outside SafeArea so the drag
                // strip reaches the very top edge of the window.
                if (usesCustomWindowChrome)
                  WindowCaptionBar(title: l10n.appTitle, cute: themeState.cute),
                Expanded(
                  child: SafeArea(
                    top: !usesCustomWindowChrome,
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
                              Expanded(child: SketchpadCanvas(key: _canvasKey)),
                              RightDock(
                                cute: themeState.cute,
                                collapsed:
                                    _dockCollapsed ||
                                    MediaQuery.sizeOf(context).width < 640,
                                onToggle: () => setState(
                                  () => _dockCollapsed = !_dockCollapsed,
                                ),
                                onAddMeasurement: _addMeasurement,
                                onAddAnimation: _addAnimation,
                                onApplyAi: _applyAi,
                                onRunCommand: _runDocumentCommand,
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
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _menuBar(AppLocalizations l10n) {
    final width = MediaQuery.sizeOf(context).width;
    final menus = <Widget>[
      _topMenu(l10n.menuFile, [
        _menuItem('new', l10n.newDocument, Icons.note_add_outlined),
        _menuItem('open', l10n.open, Icons.folder_open_outlined),
        if (_recentFiles.isNotEmpty) const PopupMenuDivider(height: 8),
        for (var index = 0; index < _recentFiles.length; index++)
          _menuItem(
            'recent-$index',
            p.basename(_recentFiles[index]),
            Icons.history,
          ),
        _menuItem('save', l10n.save, Icons.save_outlined),
        _menuItem('saveAs', l10n.saveAs, Icons.save_as_outlined),
        _menuItem('exportPage', l10n.exportPage, Icons.ios_share),
        _menuItem(
          'exportGif',
          Localizations.localeOf(context).languageCode == 'zh'
              ? '导出动画 GIF'
              : 'Export animation GIF',
          Icons.animation,
        ),
        _menuItem(
          'exportApng',
          Localizations.localeOf(context).languageCode == 'zh'
              ? '导出动画 APNG'
              : 'Export animation APNG',
          Icons.animation,
        ),
        _menuItem('closeTab', l10n.closeTab, Icons.close),
      ], compact: width < 860),
      _topMenu(l10n.menuEdit, [
        _menuItem('undo', l10n.undo, Icons.undo),
        _menuItem('redo', l10n.redo, Icons.redo),
        _menuItem('delete', l10n.deleteSelection, Icons.delete_outline),
      ], compact: width < 860),
      _topMenu(l10n.menuView, [
        _menuItem('toggleGrid', l10n.grid, Icons.grid_4x4),
        _menuItem('snapGrid', l10n.snapGrid, Icons.grid_on),
        _menuItem('snapObjects', l10n.snapObjects, Icons.hub_outlined),
        _menuItem('fitView', l10n.fitView, Icons.fit_screen),
        _menuItem('resetOrigin', l10n.resetOrigin, Icons.my_location),
      ], compact: width < 860),
      _topMenu(l10n.menuLayout, [
        _menuItem('toggleDock', l10n.properties, Icons.view_sidebar_outlined),
      ], compact: width < 860),
      _topMenu(l10n.menuObject, [
        _menuItem('delete', l10n.deleteSelection, Icons.delete_outline),
        _menuItem('label', l10n.toolText, Icons.text_fields),
      ], compact: width < 860),
      _topMenu(l10n.menuEffects, [
        _menuItem('measure', l10n.addMeasure, Icons.straighten),
        _menuItem('animate', l10n.addAnimation, Icons.play_circle_outline),
      ], compact: width < 860),
      _topMenu(l10n.menuText, [
        _menuItem('label', l10n.toolText, Icons.text_fields),
      ], compact: width < 860),
      _topMenu(l10n.menuTools, [
        _menuItem('settings', l10n.settings, Icons.settings_outlined),
      ], compact: width < 860),
      _topMenu(l10n.menuWindow, [
        _menuItem('toggleDock', l10n.properties, Icons.view_sidebar_outlined),
      ], compact: width < 860),
      _topMenu(l10n.menuHelp, [
        _menuItem('updates', l10n.checkUpdates, Icons.system_update_alt),
        _menuItem('about', l10n.about, Icons.info_outline),
      ], compact: width < 860),
    ];
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: context.watch<ThemeBloc>().state.cute
            ? const Color(0xffeadde6)
            : const Color(0xffd3dde7),
        border: const Border(
          bottom: BorderSide(color: Color(0xff8e9eae), width: 1.4),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      child: Row(
        children: [
          if (width >= 1100) ...[
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
          ],
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: menus),
            ),
          ),
          if (width >= 1200) ...[
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

  Widget _topMenu(
    String label,
    List<PopupMenuEntry<String>> items, {
    bool compact = false,
  }) {
    return PopupMenuButton<String>(
      key: ValueKey('menu-$label'),
      tooltip: '',
      position: PopupMenuPosition.under,
      onSelected: _onMenuAction,
      itemBuilder: (context) => items,
      child: Container(
        margin: EdgeInsets.symmetric(horizontal: compact ? 1 : 2, vertical: 2),
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 3 : 9,
          vertical: compact ? 7 : 6,
        ),
        decoration: BoxDecoration(
          color: const Color(0xfffdfefe),
          border: Border.all(color: const Color(0xff8293a3), width: 1.2),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: compact ? 10.5 : 12.5,
            color: Color(0xff172b3d),
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  /// Width below which the standard toolbar switches to its stacked, icon-only
  /// layout.
  ///
  /// English labels are substantially wider than their Chinese counterparts, so
  /// English needs a higher threshold. Without this the English bar squeezes its
  /// labels out of view at widths that still fit Chinese comfortably.
  double _toolbarCompactWidth(BuildContext context) =>
      Localizations.localeOf(context).languageCode == 'en' ? 1780 : 1500;

  Widget _standardBar(AppLocalizations l10n, DocumentState documentState) {
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < _toolbarCompactWidth(context);
    final toolColumns = ((width - 20) / 56).floor().clamp(
      1,
      MoeTool.values.length,
    );
    final toolRows = compact
        ? (MoeTool.values.length + toolColumns - 1) ~/ toolColumns
        : 1;
    final toolRowHeight = compact ? toolRows * 54.0 + 6 : 43.0;
    return Container(
      height: 53 + toolRowHeight,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: const BoxDecoration(
        color: Color(0xfff5f7f9),
        border: Border(
          bottom: BorderSide(color: Color(0xff9ba9b7), width: 1.2),
        ),
      ),
      child: Column(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact =
                    constraints.maxWidth < _toolbarCompactWidth(context);
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _barButton(
                        Icons.note_add_outlined,
                        l10n.newDocument,
                        _newTab,
                        key: const ValueKey('toolbar-new'),
                        showLabel: !compact,
                      ),
                      _barButton(
                        Icons.folder_open_outlined,
                        l10n.open,
                        _openFile,
                        key: const ValueKey('toolbar-open'),
                        showLabel: !compact,
                      ),
                      _barButton(
                        Icons.save_outlined,
                        l10n.save,
                        () => _saveActive(),
                        key: const ValueKey('toolbar-save'),
                        showLabel: !compact,
                      ),
                      const _BarDivider(),
                      _barButton(
                        Icons.undo,
                        l10n.undo,
                        documentState.canUndo
                            ? () => context.read<DocumentBloc>().undo()
                            : null,
                        key: const ValueKey('toolbar-undo'),
                        showLabel: !compact,
                      ),
                      _barButton(
                        Icons.redo,
                        l10n.redo,
                        documentState.canRedo
                            ? () => context.read<DocumentBloc>().redo()
                            : null,
                        key: const ValueKey('toolbar-redo'),
                        showLabel: !compact,
                      ),
                      const _BarDivider(),
                      BlocBuilder<CanvasBloc, CanvasState>(
                        builder: (context, canvas) {
                          final percent = (canvas.zoom * 100).round();
                          return PopupMenuButton<String>(
                            key: const ValueKey('toolbar-zoom'),
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
                              for (final value in [
                                25,
                                50,
                                75,
                                100,
                                150,
                                200,
                                400,
                                800,
                              ])
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
                                horizontal: 10,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xfffdfefe),
                                border: Border.all(
                                  color: const Color(0xff899aaa),
                                  width: 1.1,
                                ),
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Row(
                                children: [
                                  Text(
                                    '$percent%',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xff203548),
                                    ),
                                  ),
                                  const Icon(Icons.arrow_drop_down, size: 17),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(width: 6),
                      BlocBuilder<CanvasBloc, CanvasState>(
                        builder: (context, canvas) => DropdownButton<String>(
                          key: const ValueKey('toolbar-unit'),
                          value: const ['mm', 'cm', 'px'].contains(canvas.unit)
                              ? canvas.unit
                              : 'mm',
                          isDense: true,
                          underline: const SizedBox.shrink(),
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xff203548),
                            fontWeight: FontWeight.w700,
                          ),
                          items: const [
                            DropdownMenuItem(value: 'mm', child: Text('mm')),
                            DropdownMenuItem(value: 'cm', child: Text('cm')),
                            DropdownMenuItem(value: 'px', child: Text('px')),
                          ],
                          onChanged: (value) {
                            if (value == null) return;
                            _updateCanvasSetting(
                              (canvas) => canvas.setUnit(value),
                            );
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
                              () => _updateCanvasSetting(
                                (bloc) => bloc.toggleGrid(),
                              ),
                              key: const ValueKey('toolbar-grid'),
                              active: canvas.showGrid,
                              showLabel: !compact,
                            ),
                            _barButton(
                              Icons.grid_4x4,
                              l10n.snapGrid,
                              () => _updateCanvasSetting(
                                (bloc) => bloc.setSnapGrid(!canvas.snapGrid),
                              ),
                              key: const ValueKey('toolbar-snap-grid'),
                              active: canvas.snapGrid,
                              showLabel: !compact,
                            ),
                            _barButton(
                              Icons.hub_outlined,
                              l10n.snapObjects,
                              () => _updateCanvasSetting(
                                (bloc) =>
                                    bloc.setSnapObjects(!canvas.snapObjects),
                              ),
                              key: const ValueKey('toolbar-snap-objects'),
                              active: canvas.snapObjects,
                              showLabel: !compact,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          const Divider(height: 1, thickness: 1),
          SizedBox(
            height: toolRowHeight,
            child: BlocBuilder<ToolBloc, ToolState>(
              builder: (context, toolState) {
                final tools = <(MoeTool, String, IconData)>[
                  (MoeTool.select, l10n.toolSelect, Icons.near_me_outlined),
                  (MoeTool.point, l10n.toolPoint, Icons.circle),
                  (MoeTool.segment, l10n.toolSegment, Icons.show_chart),
                  (MoeTool.line, l10n.toolLine, Icons.horizontal_rule),
                  (MoeTool.ray, l10n.toolRay, Icons.arrow_right_alt),
                  (MoeTool.vector, l10n.toolVector, Icons.trending_flat),
                  (MoeTool.circle, l10n.toolCircle, Icons.circle_outlined),
                  (MoeTool.arc, l10n.toolArc, Icons.rounded_corner),
                  (MoeTool.triangle, l10n.toolTriangle, Icons.change_history),
                  (MoeTool.polygon, l10n.toolPolygon, Icons.pentagon_outlined),
                  (MoeTool.function, l10n.toolFunction, Icons.functions),
                  (MoeTool.text, l10n.toolText, Icons.text_fields),
                  (MoeTool.pan, l10n.toolPan, Icons.pan_tool_alt_outlined),
                  (MoeTool.zoom, l10n.toolZoom, Icons.zoom_in),
                  (MoeTool.rectangle, l10n.toolRectangle, Icons.crop_square),
                  (MoeTool.ellipse, l10n.toolEllipse, Icons.circle_outlined),
                  (MoeTool.freehand, l10n.toolFreehand, Icons.gesture),
                  (MoeTool.fill, l10n.toolFill, Icons.format_color_fill),
                  (MoeTool.transparency, l10n.toolTransparency, Icons.opacity),
                  (MoeTool.eyedropper, l10n.toolEyedropper, Icons.colorize),
                  (MoeTool.outline, l10n.toolOutline, Icons.line_weight),
                ];
                return LayoutBuilder(
                  builder: (context, constraints) {
                    final compact =
                        constraints.maxWidth < _toolbarCompactWidth(context);
                    final children = [
                      for (final (tool, label, icon) in tools)
                        Padding(
                          padding: EdgeInsets.only(right: compact ? 2 : 4),
                          child: _toolShortcut(
                            tool,
                            label,
                            icon,
                            compact: compact,
                            selected: toolState.active == tool,
                          ),
                        ),
                    ];
                    if (compact) {
                      return Align(
                        alignment: Alignment.centerLeft,
                        child: Wrap(
                          spacing: 0,
                          runSpacing: 0,
                          children: children,
                        ),
                      );
                    }
                    return SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(children: children),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _toolShortcut(
    MoeTool tool,
    String label,
    IconData icon, {
    required bool selected,
    required bool compact,
  }) {
    final foreground = selected
        ? const Color(0xff103f63)
        : const Color(0xff263b4f);
    final background = selected
        ? const Color(0xffc9e5f8)
        : const Color(0xfffbfcfd);
    final border = selected ? const Color(0xff17689e) : const Color(0xff899aaa);
    if (compact) {
      return Tooltip(
        message: '$label\n${_toolHint(AppLocalizations.of(context), tool)}',
        child: SizedBox(
          key: ValueKey('top-tool-${tool.name}'),
          width: 56,
          height: 50,
          child: Material(
            color: background,
            shape: RoundedRectangleBorder(
              side: BorderSide(color: border, width: selected ? 2 : 1.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: InkWell(
              onTap: () => context.read<ToolBloc>().select(tool),
              borderRadius: BorderRadius.circular(4),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 18, color: foreground),
                  const SizedBox(height: 2),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 8,
                        height: 1.15,
                        color: foreground,
                        fontWeight: selected
                            ? FontWeight.w800
                            : FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return OutlinedButton.icon(
      key: ValueKey('top-tool-${tool.name}'),
      onPressed: () => context.read<ToolBloc>().select(tool),
      icon: Icon(icon, size: 17),
      label: Text(
        label,
        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: foreground,
        backgroundColor: background,
        minimumSize: const Size(0, 38),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        side: BorderSide(color: border, width: selected ? 1.5 : 1.1),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  Widget _barButton(
    IconData icon,
    String tooltip,
    VoidCallback? onPressed, {
    bool active = false,
    bool showLabel = false,
    Key? key,
  }) {
    final foreground = active
        ? const Color(0xff164f79)
        : const Color(0xff263b4f);
    final background = active
        ? const Color(0xffdcecf8)
        : const Color(0xfffbfcfd);
    final border = active ? const Color(0xff477da5) : const Color(0xff899aaa);
    if (showLabel) {
      return OutlinedButton.icon(
        key: key,
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(
          tooltip,
          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: foreground,
          backgroundColor: background,
          minimumSize: const Size(0, 38),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          side: BorderSide(color: border, width: active ? 1.4 : 1.1),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
          visualDensity: VisualDensity.compact,
        ),
      );
    }
    final buttonStyle = IconButton.styleFrom(
      foregroundColor: foreground,
      backgroundColor: background,
      side: BorderSide(color: border, width: active ? 1.4 : 1.1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
      padding: const EdgeInsets.symmetric(horizontal: 7),
    );
    return IconButton(
      key: key,
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
      style: buttonStyle,
    );
  }

  Widget _contextBar(AppLocalizations l10n, DocumentState documentState) {
    final selection = context.watch<SelectionBloc>().state;
    final object = selection.ids.isEmpty
        ? null
        : documentState.active.document.objectById(selection.primary!);
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: const BoxDecoration(
        color: Color(0xffe8eef4),
        border: Border(
          bottom: BorderSide(color: Color(0xff8798a9), width: 1.2),
        ),
      ),
      // The selection controls (W/H, measurement, delete) do not fit at every
      // window width, so that row scrolls horizontally. It cannot use a Spacer,
      // because a horizontally unbounded Row forbids flexible children.
      child: object == null
          ? Row(
              children: [
                const Icon(Icons.tune, size: 17, color: Color(0xff315775)),
                const SizedBox(width: 6),
                Text(
                  '${l10n.contextCanvas} · ${l10n.geometrySettings}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xff203548),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                BlocBuilder<CanvasBloc, CanvasState>(
                  builder: (context, canvas) => Text(
                    l10n.statusOrigin(
                      _number(canvas.origin.x),
                      _number(canvas.origin.y),
                    ),
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xff455b70),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            )
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  Icon(
                    Icons.select_all,
                    size: 15,
                    color: const Color(0xff55728b),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${object.kind.name} · ${object.id}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
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
                  if (object.bounds != null) ...[
                    const SizedBox(width: 12),
                    _SizeEditor(
                      object: object,
                      widthController: _widthController,
                      heightController: _heightController,
                      onApply: (width, height) =>
                          _resizeSelected(object, width, height),
                    ),
                  ],
                  const SizedBox(width: 12),
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
              ),
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

  String _toolHint(AppLocalizations l10n, MoeTool tool) => switch (tool) {
    MoeTool.select => l10n.statusToolHintSelect,
    MoeTool.point => l10n.statusToolHintPoint,
    MoeTool.segment => l10n.statusToolHintSegment,
    MoeTool.line => l10n.statusToolHintLine,
    MoeTool.ray => l10n.statusToolHintRay,
    MoeTool.vector => l10n.statusToolHintVector,
    MoeTool.circle => l10n.statusToolHintCircle,
    MoeTool.arc => l10n.statusToolHintArc,
    MoeTool.triangle => l10n.statusToolHintTriangle,
    MoeTool.polygon => l10n.statusToolHintPolygon,
    MoeTool.function => l10n.statusToolHintFunction,
    MoeTool.text => l10n.statusToolHintText,
    MoeTool.pan => l10n.statusToolHintPan,
    MoeTool.zoom => l10n.statusToolHintZoom,
    MoeTool.rectangle => l10n.statusToolHintRectangle,
    MoeTool.ellipse => l10n.statusToolHintEllipse,
    MoeTool.freehand => l10n.statusToolHintFreehand,
    MoeTool.fill => l10n.statusToolHintFill,
    MoeTool.transparency => l10n.statusToolHintTransparency,
    MoeTool.eyedropper => l10n.statusToolHintEyedropper,
    MoeTool.outline => l10n.statusToolHintOutline,
  };

  Widget _statusBar(AppLocalizations l10n, DocumentTab tab) {
    return BlocBuilder<CanvasBloc, CanvasState>(
      builder: (context, canvas) {
        final width = MediaQuery.sizeOf(context).width;
        final tool = context.watch<ToolBloc>().state.active;
        return Container(
          height: 25,
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
              const SizedBox(width: 10),
              Icon(Icons.info_outline, size: 13, color: Color(0xff35688d)),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  _toolHint(l10n, tool),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xff314f67),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (width >= 1000 && canvas.cursorWorld != null) ...[
                const SizedBox(width: 12),
                Text(
                  'x ${canvas.cursorWorld!.x.toStringAsFixed(2)}  '
                  'y ${canvas.cursorWorld!.y.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xff5e7080),
                  ),
                ),
              ],
              if (width >= 820) ...[
                const SizedBox(width: 12),
                Text(
                  l10n.statusOrigin(
                    canvas.origin.x.toStringAsFixed(1),
                    canvas.origin.y.toStringAsFixed(1),
                  ),
                  style: const TextStyle(
                    fontSize: 9.5,
                    color: Color(0xff77899a),
                  ),
                ),
              ],
              const SizedBox(width: 12),
              Text(
                l10n.statusZoom((canvas.zoom * 100).round()),
                style: const TextStyle(fontSize: 10, color: Color(0xff485c6e)),
              ),
              if (width >= 1200) ...[
                const SizedBox(width: 12),
                Text(
                  tab.path ?? l10n.untitled(tab.untitledIndex),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 9.5,
                    color: Color(0xff77899a),
                  ),
                ),
              ],
            ],
          ),
        );
      },
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

/// Inline width/height editor shown in the context bar for a selected object
/// that has finite bounds. Owns its own controllers so the fields are always
/// editable independently of canvas-driven document updates.
class _SizeEditor extends StatefulWidget {
  const _SizeEditor({
    required this.object,
    required this.onApply,
  });

  final GeometryObject object;
  final void Function(double width, double height) onApply;

  @override
  State<_SizeEditor> createState() => _SizeEditorState();
}

class _SizeEditorState extends State<_SizeEditor> {
  final _widthController = TextEditingController();
  final _heightController = TextEditingController();
  bool _focused = false;
  bool _pendingSync = true; // true until the next frame so we initialize

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() => _pendingSync = false);
        _syncFromObject(force: true);
      }
    });
  }

  @override
  void didUpdateWidget(_SizeEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-sync when the selection changes to a different object. While the user
    // is actively editing we defer syncing until focus is lost, so a
    // canvas-driven resize never clobbers the in-progress edit.
    if (widget.object.id != oldWidget.object.id) {
      _pendingSync = true;
      _syncFromObject(force: true);
    }
  }

  @override
  void dispose() {
    _widthController.dispose();
    _heightController.dispose();
    super.dispose();
  }

  /// Mirrors the selected object's bounds into the text fields when not editing.
  void _syncFromObject({bool force = false}) {
    if (!force && _focused) return;
    final bounds = widget.object.bounds;
    if (bounds == null) return;
    final width = bounds.width.toStringAsFixed(2);
    final height = bounds.height.toStringAsFixed(2);
    if (_widthController.text != width) _widthController.text = width;
    if (_heightController.text != height) _heightController.text = height;
  }

  void _apply() {
    final width = double.tryParse(_widthController.text.trim());
    final height = double.tryParse(_heightController.text.trim());
    if (width == null || height == null || width <= 0 || height <= 0) return;
    widget.onApply(width, height);
    // Re-sync to the new bounds now that the edit is committed.
    _syncFromObject(force: true);
  }

  String _stripZero(String v) => v.endsWith('.00') ? v.substring(0, v.length - 3) : v;

  void _nextField(TextEditingController from, TextEditingController to) {
    _apply();
    FocusScope.of(context).nextFocus();
  }
}


          child: const Text('Apply', style: TextStyle(fontSize: 10)),
        ),
      ],
    );
  }
}
