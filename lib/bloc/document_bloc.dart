// SPDX-License-Identifier: GPL-3.0-only
import 'dart:convert';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:moesketchpad_core/moesketchpad_core.dart';

class DocumentTab {
  const DocumentTab({
    required this.id,
    required this.untitledIndex,
    required this.document,
    this.path,
    this.dirty = false,
    this.undoStack = const [],
    this.redoStack = const [],
  });

  final String id;
  final int untitledIndex;
  final GeometryDocument document;
  final String? path;
  final bool dirty;
  final List<GeometryDocument> undoStack;
  final List<GeometryDocument> redoStack;

  DocumentTab copyWith({
    String? id,
    int? untitledIndex,
    GeometryDocument? document,
    String? path,
    bool clearPath = false,
    bool? dirty,
    List<GeometryDocument>? undoStack,
    List<GeometryDocument>? redoStack,
  }) => DocumentTab(
    id: id ?? this.id,
    untitledIndex: untitledIndex ?? this.untitledIndex,
    document: document ?? this.document,
    path: clearPath ? null : (path ?? this.path),
    dirty: dirty ?? this.dirty,
    undoStack: undoStack ?? this.undoStack,
    redoStack: redoStack ?? this.redoStack,
  );
}

class DocumentState {
  const DocumentState({required this.tabs, required this.activeIndex});

  final List<DocumentTab> tabs;
  final int activeIndex;

  DocumentTab get active => tabs[activeIndex.clamp(0, tabs.length - 1)];
  bool get anyDirty => tabs.any((tab) => tab.dirty);
  bool get canUndo => active.undoStack.isNotEmpty;
  bool get canRedo => active.redoStack.isNotEmpty;

  DocumentState copyWith({List<DocumentTab>? tabs, int? activeIndex}) =>
      DocumentState(
        tabs: tabs ?? this.tabs,
        activeIndex: activeIndex ?? this.activeIndex,
      );
}

class DocumentBloc extends Cubit<DocumentState> {
  DocumentBloc()
    : super(
        DocumentState(
          tabs: [
            DocumentTab(
              id: 'doc-1',
              untitledIndex: 1,
              document: GeometryDocument(objects: [], title: 'Untitled-1'),
            ),
          ],
          activeIndex: 0,
        ),
      );

  static const int _historyLimit = 100;
  int _tabSequence = 1;
  int _untitledSequence = 1;

  void newDocument() {
    _untitledSequence++;
    _tabSequence++;
    final tab = DocumentTab(
      id: 'doc-$_tabSequence',
      untitledIndex: _untitledSequence,
      document: GeometryDocument(
        objects: [],
        title: 'Untitled-$_untitledSequence',
      ),
    );
    emit(
      state.copyWith(
        tabs: [...state.tabs, tab],
        activeIndex: state.tabs.length,
      ),
    );
  }

  void openDocument(GeometryDocument document, {required String path}) {
    final normalized = path.replaceAll('\\', '/').toLowerCase();
    final existing = state.tabs.indexWhere(
      (tab) => tab.path?.replaceAll('\\', '/').toLowerCase() == normalized,
    );
    if (existing >= 0) {
      emit(state.copyWith(activeIndex: existing));
      return;
    }
    _tabSequence++;
    final tab = DocumentTab(
      id: 'doc-$_tabSequence',
      untitledIndex: 0,
      document: document,
      path: path,
    );
    emit(
      state.copyWith(
        tabs: [...state.tabs, tab],
        activeIndex: state.tabs.length,
      ),
    );
  }

  void setActive(int index) {
    if (index < 0 || index >= state.tabs.length) return;
    emit(state.copyWith(activeIndex: index));
  }

  void forceClose(int index) {
    if (index < 0 || index >= state.tabs.length) return;
    final remaining = [...state.tabs]..removeAt(index);
    if (remaining.isEmpty) {
      _untitledSequence++;
      remaining.add(
        DocumentTab(
          id: 'doc-${++_tabSequence}',
          untitledIndex: _untitledSequence,
          document: GeometryDocument(
            objects: [],
            title: 'Untitled-$_untitledSequence',
          ),
        ),
      );
    }
    final nextIndex = state.activeIndex >= remaining.length
        ? remaining.length - 1
        : state.activeIndex > index
        ? state.activeIndex - 1
        : state.activeIndex;
    emit(state.copyWith(tabs: remaining, activeIndex: nextIndex));
  }

  void _replaceActive(
    GeometryDocument document, {
    required bool dirty,
    bool history = true,
    String? path,
  }) {
    final tabs = [...state.tabs];
    final active = state.active;
    final undo = history
        ? [...active.undoStack, active.document]
        : active.undoStack;
    if (undo.length > _historyLimit) undo.removeAt(0);
    tabs[state.activeIndex] = active.copyWith(
      document: document,
      dirty: dirty,
      undoStack: undo,
      redoStack: history ? const [] : active.redoStack,
      path: path,
    );
    emit(state.copyWith(tabs: tabs));
  }

  void commitDocument(GeometryDocument document, {bool markDirty = true}) {
    _replaceActive(document, dirty: markDirty || state.active.dirty);
  }

  void updateView(ViewState view) {
    final document = state.active.document;
    if (jsonEncode(document.view.toJson()) == jsonEncode(view.toJson())) return;
    _replaceActive(document.copyWith(view: view), dirty: true, history: false);
  }

  void addObject(GeometryObject object) {
    _replaceActive(state.active.document.withObject(object), dirty: true);
  }

  void updateObject(GeometryObject object) {
    commitDocument(state.active.document.withObject(object));
  }

  /// One undo entry for a gesture that previewed many intermediate states.
  void commitDrag(GeometryDocument before, GeometryDocument after) {
    final tabs = [...state.tabs];
    final active = state.active;
    final undo = [...active.undoStack, before];
    if (undo.length > _historyLimit) undo.removeAt(0);
    tabs[state.activeIndex] = active.copyWith(
      document: after,
      dirty: true,
      undoStack: undo,
      redoStack: const [],
    );
    emit(state.copyWith(tabs: tabs));
  }

  void deleteObjects(Iterable<String> ids) {
    var document = state.active.document;
    for (final id in ids) {
      document = document.withoutObject(id);
    }
    commitDocument(document);
  }

  void addMeasurement(Measurement measurement) {
    commitDocument(
      state.active.document.copyWith(
        measurements: [...state.active.document.measurements, measurement],
      ),
    );
  }

  void addAnimation(AnimationSpec animation) {
    commitDocument(
      state.active.document.copyWith(
        animations: [...state.active.document.animations, animation],
      ),
    );
  }

  void addConstraint(Constraint constraint) {
    commitDocument(
      state.active.document.copyWith(
        constraints: [...state.active.document.constraints, constraint],
      ),
    );
  }

  void setLabel(String id, String? label) {
    final object = state.active.document.objectById(id);
    if (object == null) return;
    updateObject(
      label == null
          ? object.copyWith(clearLabel: true)
          : object.copyWith(label: label),
    );
  }

  void undo() {
    final active = state.active;
    if (active.undoStack.isEmpty) return;
    final previous = active.undoStack.last;
    final tabs = [...state.tabs];
    tabs[state.activeIndex] = active.copyWith(
      document: previous,
      undoStack: active.undoStack.sublist(0, active.undoStack.length - 1),
      redoStack: [...active.redoStack, active.document],
      dirty: true,
    );
    emit(state.copyWith(tabs: tabs));
  }

  void redo() {
    final active = state.active;
    if (active.redoStack.isEmpty) return;
    final next = active.redoStack.last;
    final tabs = [...state.tabs];
    tabs[state.activeIndex] = active.copyWith(
      document: next,
      redoStack: active.redoStack.sublist(0, active.redoStack.length - 1),
      undoStack: [...active.undoStack, active.document],
      dirty: true,
    );
    emit(state.copyWith(tabs: tabs));
  }

  void saveSucceeded(String path, GeometryDocument document) {
    final tabs = [...state.tabs];
    tabs[state.activeIndex] = state.active.copyWith(
      path: path,
      document: document,
      dirty: false,
    );
    emit(state.copyWith(tabs: tabs));
  }

  /// Mirrors the live canvas view into the active document without creating a
  /// dirty edit. Called immediately before persistence.
  GeometryDocument documentForSave(ViewState view) {
    final document = state.active.document.copyWith(view: view);
    final tabs = [...state.tabs];
    tabs[state.activeIndex] = state.active.copyWith(document: document);
    emit(state.copyWith(tabs: tabs));
    return document;
  }

  void syncView(ViewState view) {
    final document = state.active.document.copyWith(view: view);
    final tabs = [...state.tabs];
    tabs[state.activeIndex] = state.active.copyWith(document: document);
    emit(state.copyWith(tabs: tabs));
  }
}
