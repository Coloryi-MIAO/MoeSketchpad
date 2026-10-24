// SPDX-License-Identifier: GPL-3.0-only
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:moesketchpad_core/moesketchpad_core.dart';

import '../../bloc/ai_bloc.dart';
import '../../bloc/animation_bloc.dart';
import '../../bloc/canvas_bloc.dart';
import '../../bloc/document_bloc.dart';
import '../../bloc/measure_bloc.dart';
import '../../bloc/selection_bloc.dart';
import '../../l10n/app_localizations.dart';

class RightDock extends StatefulWidget {
  const RightDock({
    super.key,
    required this.cute,
    required this.collapsed,
    required this.onToggle,
    required this.onAddMeasurement,
    required this.onAddAnimation,
    required this.onApplyAi,
  });

  final bool cute;
  final bool collapsed;
  final VoidCallback onToggle;
  final void Function(MeasurementType type) onAddMeasurement;
  final VoidCallback onAddAnimation;
  final void Function(GeometryDocument preview) onApplyAi;

  @override
  State<RightDock> createState() => _RightDockState();
}

class _RightDockState extends State<RightDock> {
  final TextEditingController _aiInput = TextEditingController();
  final TextEditingController _aiEndpoint = TextEditingController(
    text: 'https://api.openai.com/v1',
  );
  final TextEditingController _aiModel = TextEditingController();
  final TextEditingController _aiApiKey = TextEditingController();
  bool _aiConfigEdited = false;
  bool _aiControllersInitialized = false;
  bool _showAiApiKey = false;
  MeasurementType _measureType = MeasurementType.length;

  @override
  void dispose() {
    _aiInput.dispose();
    _aiEndpoint.dispose();
    _aiModel.dispose();
    _aiApiKey.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ai = context.read<AiBloc>().state;
    if (!_aiControllersInitialized && ai.settingsLoaded) {
      _aiEndpoint.text = ai.endpoint;
      _aiModel.text = ai.model;
      _aiControllersInitialized = true;
    }
  }

  void _updateCanvasSetting(void Function(CanvasBloc bloc) update) {
    final canvas = context.read<CanvasBloc>();
    update(canvas);
    final documents = context.read<DocumentBloc>();
    documents.updateView(
      canvas.withCurrentSettings(documents.state.active.document.view),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (widget.collapsed) {
      return Container(
        width: 40,
        decoration: BoxDecoration(
          color: widget.cute
              ? const Color(0xfff5eaf1)
              : const Color(0xffe5ebf1),
          border: const Border(left: BorderSide(color: Color(0xffc8ced6))),
        ),
        child: Column(
          children: [
            IconButton(
              tooltip: l10n.dockExpand,
              onPressed: widget.onToggle,
              icon: const Icon(Icons.chevron_left, size: 17),
              style: IconButton.styleFrom(
                foregroundColor: const Color(0xff263b4f),
                backgroundColor: const Color(0xfffbfcfd),
                side: const BorderSide(color: Color(0xffb8c3ce)),
              ),
            ),
            RotatedBox(
              quarterTurns: 1,
              child: Text(
                l10n.properties,
                style: const TextStyle(
                  fontSize: 12,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w700,
                  color: Color(0xff33485c),
                ),
              ),
            ),
          ],
        ),
      );
    }
    return Container(
      width: MediaQuery.sizeOf(context).width < 860 ? 248 : 292,
      decoration: BoxDecoration(
        color: widget.cute ? const Color(0xfff5edf2) : const Color(0xffe7edf3),
        border: const Border(
          left: BorderSide(color: Color(0xff899aaa), width: 1.4),
        ),
      ),
      child: Column(
        children: [
          _DockTitle(
            title: l10n.properties,
            cute: widget.cute,
            onCollapse: widget.onToggle,
            collapseTooltip: l10n.dockCollapse,
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _geometrySection(l10n),
                  _objectsSection(l10n),
                  _propertiesSection(l10n),
                  _measureSection(l10n),
                  _animationSection(l10n),
                  _aiSection(l10n),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _geometrySection(AppLocalizations l10n) {
    return BlocBuilder<CanvasBloc, CanvasState>(
      builder: (context, canvas) => _DockSection(
        title: l10n.geometrySettings,
        icon: Icons.tune,
        cute: widget.cute,
        initiallyExpanded: true,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 3, 10, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String>(
                key: const ValueKey('geometry-unit'),
                initialValue: canvas.unit,
                isDense: true,
                decoration: InputDecoration(
                  labelText: l10n.geometryUnit,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 8,
                  ),
                  border: const OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'mm', child: Text('mm')),
                  DropdownMenuItem(value: 'cm', child: Text('cm')),
                  DropdownMenuItem(value: 'px', child: Text('px')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    _updateCanvasSetting((canvas) => canvas.setUnit(value));
                  }
                },
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<double>(
                key: ValueKey('geometry-grid-${canvas.gridBaseSpacing}'),
                initialValue: canvas.gridBaseSpacing,
                isDense: true,
                decoration: InputDecoration(
                  labelText: l10n.geometryGridSpacing,
                  helperText: l10n.geometryGridSpacingHint,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 8,
                  ),
                  border: const OutlineInputBorder(),
                ),
                items: const [1, 2, 5, 10, 20, 24, 50, 100]
                    .map(
                      (value) => DropdownMenuItem<double>(
                        value: value.toDouble(),
                        child: Text('$value'),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) {
                    _updateCanvasSetting(
                      (canvas) => canvas.setGridBaseSpacing(value),
                    );
                  }
                },
              ),
              const SizedBox(height: 5),
              DropdownButtonFormField<double>(
                key: ValueKey(
                  'geometry-tolerance-${canvas.geometryTolerance.relative}',
                ),
                initialValue: canvas.geometryTolerance.relative,
                isDense: true,
                decoration: InputDecoration(
                  labelText: l10n.geometryTolerance,
                  helperText: l10n.geometryToleranceHint,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 8,
                  ),
                  border: const OutlineInputBorder(),
                ),
                items: const [1e-6, 1e-9, 1e-12]
                    .map(
                      (value) => DropdownMenuItem<double>(
                        value: value,
                        child: Text(value.toStringAsExponential(0)),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) {
                    _updateCanvasSetting(
                      (canvas) => canvas.setGeometryTolerance(
                        GeometryTolerance(relative: value, absolute: value),
                      ),
                    );
                  }
                },
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.geometrySnapTolerance,
                      style: const TextStyle(fontSize: 10.5),
                    ),
                  ),
                  Text(
                    '${canvas.snapTolerancePx.toStringAsFixed(0)} px',
                    style: const TextStyle(
                      fontSize: 10,
                      color: Color(0xff718191),
                    ),
                  ),
                ],
              ),
              Slider(
                key: const ValueKey('geometry-snap-tolerance'),
                value: canvas.snapTolerancePx,
                min: 2,
                max: 24,
                divisions: 22,
                label: '${canvas.snapTolerancePx.toStringAsFixed(0)} px',
                onChanged: (value) => _updateCanvasSetting(
                  (canvas) => canvas.setSnapTolerancePx(value),
                ),
              ),
              SwitchListTile(
                key: const ValueKey('geometry-snap-grid'),
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(
                  l10n.snapGrid,
                  style: const TextStyle(fontSize: 10.5),
                ),
                value: canvas.snapGrid,
                onChanged: (value) =>
                    _updateCanvasSetting((canvas) => canvas.setSnapGrid(value)),
              ),
              SwitchListTile(
                key: const ValueKey('geometry-snap-objects'),
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(
                  l10n.snapObjects,
                  style: const TextStyle(fontSize: 10.5),
                ),
                value: canvas.snapObjects,
                onChanged: (value) => _updateCanvasSetting(
                  (canvas) => canvas.setSnapObjects(value),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _objectsSection(AppLocalizations l10n) {
    return BlocBuilder<DocumentBloc, DocumentState>(
      builder: (context, state) {
        final objects = [...state.active.document.objects]
          ..sort((a, b) => a.id.compareTo(b.id));
        return _DockSection(
          title: '${l10n.objects} (${objects.length})',
          icon: Icons.layers_outlined,
          cute: widget.cute,
          child: objects.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(10),
                  child: Text(
                    l10n.noObjects,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xff7b8997),
                    ),
                  ),
                )
              : Column(
                  children: [
                    for (final object in objects)
                      BlocBuilder<SelectionBloc, SelectionState>(
                        buildWhen: (previous, current) =>
                            previous.ids != current.ids,
                        builder: (context, selection) {
                          final selected = selection.contains(object.id);
                          return InkWell(
                            onTap: () => context.read<SelectionBloc>().replace(
                              object.id,
                            ),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              color: selected
                                  ? (widget.cute
                                        ? const Color(0xfff4e2e9)
                                        : const Color(0xffe2edf6))
                                  : null,
                              child: Row(
                                children: [
                                  Icon(
                                    _kindIcon(object.kind),
                                    size: 14,
                                    color: selected
                                        ? (widget.cute
                                              ? const Color(0xffaa5276)
                                              : const Color(0xff2d6fa7))
                                        : const Color(0xff627384),
                                  ),
                                  const SizedBox(width: 7),
                                  Expanded(
                                    child: Text(
                                      '${object.label?.isNotEmpty == true ? '${object.label} · ' : ''}${object.id}',
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                  ),
                                  Text(
                                    object.kind.name,
                                    style: const TextStyle(
                                      fontSize: 9,
                                      color: Color(0xff8a96a3),
                                    ),
                                  ),
                                  const SizedBox(width: 3),
                                  InkWell(
                                    onTap: () => context
                                        .read<DocumentBloc>()
                                        .updateObject(
                                          object.copyWith(
                                            visible: !object.visible,
                                          ),
                                        ),
                                    child: Icon(
                                      object.visible
                                          ? Icons.visibility_outlined
                                          : Icons.visibility_off_outlined,
                                      size: 14,
                                      color: const Color(0xff7b8997),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                  ],
                ),
        );
      },
    );
  }

  Widget _propertiesSection(AppLocalizations l10n) {
    return _DockSection(
      title: l10n.contextSelection,
      icon: Icons.tune,
      cute: widget.cute,
      child: BlocBuilder<SelectionBloc, SelectionState>(
        builder: (context, selection) {
          if (selection.ids.isEmpty) {
            return Padding(
              padding: const EdgeInsets.all(10),
              child: Text(
                l10n.selectObjectFirst,
                style: const TextStyle(fontSize: 11, color: Color(0xff7b8997)),
              ),
            );
          }
          return BlocBuilder<DocumentBloc, DocumentState>(
            builder: (context, state) {
              final objects = [
                for (final id in selection.ids)
                  state.active.document.objectById(id),
              ].whereType<GeometryObject>().toList();
              if (objects.isEmpty) {
                return const SizedBox.shrink();
              }
              final object = objects.first;
              return Padding(
                padding: const EdgeInsets.fromLTRB(10, 4, 10, 9),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _PropertyRow(l10n.objectIdLabel, object.id),
                    _PropertyRow('kind', object.kind.name),
                    _PropertyRow(
                      l10n.labelEdit,
                      object.label?.isNotEmpty == true ? object.label! : '—',
                    ),
                    if (object.points.isNotEmpty)
                      _PropertyRow('points', object.points.length.toString()),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () => _editLabel(context, object),
                          icon: const Icon(Icons.text_fields, size: 14),
                          label: Text(l10n.labelEdit),
                          style: OutlinedButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                        if (object.kind == GeometryKind.point ||
                            object.kind == GeometryKind.vector)
                          OutlinedButton.icon(
                            onPressed: widget.onAddAnimation,
                            icon: const Icon(
                              Icons.play_circle_outline,
                              size: 14,
                            ),
                            label: Text(l10n.addAnimation),
                            style: OutlinedButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                      ],
                    ),
                    if (object.kind == GeometryKind.function)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          object.params.toString(),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 9.5,
                            color: Color(0xff617181),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _editLabel(BuildContext context, GeometryObject object) async {
    final controller = TextEditingController(text: object.label ?? '');
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(AppLocalizations.of(context).labelEdit),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 64,
          decoration: const InputDecoration(labelText: 'label'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(AppLocalizations.of(context).cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: Text(AppLocalizations.of(context).apply),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value != null && context.mounted) {
      context.read<DocumentBloc>().setLabel(
        object.id,
        value.isEmpty ? null : value,
      );
    }
  }

  Widget _measureSection(AppLocalizations l10n) {
    final types = MeasurementType.values
        .where((type) => type != MeasurementType.functionValue)
        .toList();
    return _DockSection(
      title: l10n.measurements,
      icon: Icons.straighten,
      cute: widget.cute,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(9, 3, 9, 4),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButton<MeasurementType>(
                    value: _measureType,
                    isExpanded: true,
                    isDense: true,
                    underline: const SizedBox.shrink(),
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xff34495d),
                    ),
                    items: [
                      for (final type in types)
                        DropdownMenuItem(
                          value: type,
                          child: Text(_measureName(l10n, type)),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => _measureType = value);
                    },
                  ),
                ),
                IconButton(
                  tooltip: l10n.addMeasure,
                  onPressed: () => widget.onAddMeasurement(_measureType),
                  icon: const Icon(Icons.add, size: 16),
                ),
              ],
            ),
          ),
          BlocBuilder<MeasureBloc, MeasureState>(
            builder: (context, state) {
              if (state.items.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                  child: Text(
                    l10n.noMeasurements,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xff7b8997),
                    ),
                  ),
                );
              }
              return Column(
                children: [
                  for (final item in state.items)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 2, 10, 2),
                      child: Row(
                        children: [
                          Text(
                            _measureName(l10n, item.measurement.type),
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xff647587),
                            ),
                          ),
                          const Spacer(),
                          Text(
                            item.value?.display ?? item.error ?? '—',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xff2e536f),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _animationSection(AppLocalizations l10n) {
    return _DockSection(
      title: l10n.animations,
      icon: Icons.motion_photos_on_outlined,
      cute: widget.cute,
      child: BlocBuilder<DocumentBloc, DocumentState>(
        builder: (context, documentState) =>
            BlocBuilder<AnimationBloc, AnimationState>(
              builder: (context, animationState) {
                final animations = documentState.active.document.animations;
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(9, 2, 9, 3),
                      child: Row(
                        children: [
                          OutlinedButton.icon(
                            onPressed: widget.onAddAnimation,
                            icon: const Icon(Icons.add, size: 14),
                            label: Text(l10n.addAnimation),
                            style: OutlinedButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            tooltip: animationState.playing
                                ? l10n.pauseAnimation
                                : l10n.playAnimation,
                            onPressed: animationState.activeAnimationId == null
                                ? null
                                : () {
                                    final bloc = context.read<AnimationBloc>();
                                    if (animationState.playing) {
                                      bloc.pause();
                                    } else {
                                      bloc.play();
                                    }
                                  },
                            icon: Icon(
                              animationState.playing
                                  ? Icons.pause
                                  : Icons.play_arrow,
                              size: 17,
                            ),
                          ),
                          IconButton(
                            tooltip: l10n.resetAnimation,
                            onPressed: () =>
                                context.read<AnimationBloc>().reset(),
                            icon: const Icon(Icons.restart_alt, size: 17),
                          ),
                        ],
                      ),
                    ),
                    if (animations.isEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                        child: Text(
                          l10n.noAnimationsHint,
                          style: const TextStyle(
                            fontSize: 10.5,
                            color: Color(0xff7b8997),
                          ),
                        ),
                      )
                    else
                      for (final animation in animations)
                        InkWell(
                          onTap: () {
                            context.read<AnimationBloc>()
                              ..select(animation.id)
                              ..play();
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            color:
                                animationState.activeAnimationId == animation.id
                                ? (widget.cute
                                      ? const Color(0xfff4e2e9)
                                      : const Color(0xffe2edf6))
                                : null,
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.circle,
                                  size: 8,
                                  color: Color(0xffa65576),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    '${animation.targetId} → ${animation.pathObjectId ?? animation.targetId}',
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 10.5),
                                  ),
                                ),
                                Text(
                                  't ${animation.speed.toStringAsFixed(1)}×',
                                  style: const TextStyle(
                                    fontSize: 9,
                                    color: Color(0xff7b8997),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                  ],
                );
              },
            ),
      ),
    );
  }

  Widget _aiSection(AppLocalizations l10n) {
    return BlocListener<AiBloc, AiState>(
      listenWhen: (previous, current) =>
          !previous.settingsLoaded && current.settingsLoaded,
      listener: (context, state) {
        if (_aiConfigEdited) return;
        _aiEndpoint.text = state.endpoint;
        _aiModel.text = state.model;
        _aiControllersInitialized = true;
      },
      child: _DockSection(
        title: l10n.aiAssistant,
        icon: Icons.auto_awesome,
        cute: widget.cute,
        initiallyExpanded: true,
        child: BlocBuilder<AiBloc, AiState>(
          builder: (context, state) {
            final preview = state.preview;
            return Padding(
              padding: const EdgeInsets.fromLTRB(10, 3, 10, 9),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l10n.aiConnectionHelp,
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: Color(0xff6d7d8d),
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    key: const ValueKey('ai-endpoint'),
                    controller: _aiEndpoint,
                    keyboardType: TextInputType.url,
                    onChanged: (_) => _aiConfigEdited = true,
                    style: const TextStyle(fontSize: 11),
                    decoration: InputDecoration(
                      labelText: l10n.aiEndpoint,
                      hintText: 'https://api.openai.com/v1',
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    key: const ValueKey('ai-model'),
                    controller: _aiModel,
                    onChanged: (_) => _aiConfigEdited = true,
                    style: const TextStyle(fontSize: 11),
                    decoration: InputDecoration(
                      labelText: l10n.aiModel,
                      hintText: 'gpt-4o-mini',
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    key: const ValueKey('ai-api-key'),
                    controller: _aiApiKey,
                    obscureText: !_showAiApiKey,
                    onChanged: (_) => _aiConfigEdited = true,
                    style: const TextStyle(fontSize: 11),
                    decoration: InputDecoration(
                      labelText: l10n.aiApiKey,
                      hintText: state.apiKeyConfigured
                          ? l10n.aiApiKeySavedHint
                          : l10n.aiApiKeyHint,
                      isDense: true,
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        tooltip: _showAiApiKey
                            ? l10n.aiHideKey
                            : l10n.aiShowKey,
                        onPressed: () =>
                            setState(() => _showAiApiKey = !_showAiApiKey),
                        icon: Icon(
                          _showAiApiKey
                              ? Icons.visibility_off
                              : Icons.visibility,
                          size: 17,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    l10n.aiKeyStorageNotice,
                    style: const TextStyle(
                      fontSize: 9.5,
                      color: Color(0xff6d7d8d),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed:
                          state.settingsLoaded &&
                              state.apiKeyConfigured &&
                              !state.busy
                          ? () async {
                              final bloc = context.read<AiBloc>();
                              final saved = await bloc.saveSettings(
                                endpoint: _aiEndpoint.text,
                                model: _aiModel.text,
                                clearApiKey: true,
                              );
                              if (saved && context.mounted) {
                                _aiApiKey.clear();
                                _aiConfigEdited = true;
                              }
                            }
                          : null,
                      icon: const Icon(Icons.key_off_outlined, size: 15),
                      label: Text(
                        l10n.aiClearApiKey,
                        style: const TextStyle(fontSize: 10),
                      ),
                    ),
                  ),
                  TextField(
                    key: const ValueKey('ai-prompt'),
                    controller: _aiInput,
                    minLines: 3,
                    maxLines: 6,
                    onChanged: context.read<AiBloc>().setInput,
                    style: const TextStyle(fontSize: 11),
                    decoration: InputDecoration(
                      hintText: l10n.aiPrompt,
                      hintStyle: const TextStyle(fontSize: 10.5),
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      FilledButton(
                        key: const ValueKey('ai-send'),
                        onPressed: !state.settingsLoaded || state.busy
                            ? null
                            : () async {
                                final bloc = context.read<AiBloc>();
                                final saved = await bloc.saveSettings(
                                  endpoint: _aiEndpoint.text,
                                  model: _aiModel.text,
                                  apiKey: _aiApiKey.text,
                                );
                                if (!saved || !context.mounted) return;
                                _aiApiKey.clear();
                                _aiConfigEdited = false;
                                await bloc.sendPrompt(
                                  _aiInput.text,
                                  context
                                      .read<DocumentBloc>()
                                      .state
                                      .active
                                      .document,
                                  language: l10n.localeName,
                                );
                              },
                        style: FilledButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                        ),
                        child: Text(
                          state.busy ? l10n.loading : l10n.aiSend,
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                      const SizedBox(width: 6),
                      OutlinedButton(
                        key: const ValueKey('ai-save-settings'),
                        onPressed: !state.settingsLoaded || state.busy
                            ? null
                            : () async {
                                final bloc = context.read<AiBloc>();
                                final saved = await bloc.saveSettings(
                                  endpoint: _aiEndpoint.text,
                                  model: _aiModel.text,
                                  apiKey: _aiApiKey.text,
                                );
                                if (!saved || !context.mounted) return;
                                _aiApiKey.clear();
                                _aiConfigEdited = false;
                                ScaffoldMessenger.maybeOf(
                                  context,
                                )?.showSnackBar(
                                  SnackBar(content: Text(l10n.aiSettingsSaved)),
                                );
                              },
                        style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                        ),
                        child: Text(
                          l10n.aiSaveSettings,
                          style: const TextStyle(fontSize: 10),
                        ),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        tooltip: l10n.copyPrompt,
                        onPressed: () async {
                          await Clipboard.setData(
                            ClipboardData(
                              text: context.read<AiBloc>().systemPrompt(
                                l10n.localeName,
                              ),
                            ),
                          );
                          if (context.mounted) {
                            ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                              SnackBar(content: Text(l10n.promptCopied)),
                            );
                          }
                        },
                        icon: const Icon(Icons.copy_all_outlined, size: 16),
                      ),
                    ],
                  ),
                  if (state.error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: Text(
                        l10n.aiInvaldProposal(state.error!),
                        style: const TextStyle(
                          fontSize: 10.5,
                          color: Color(0xffb4433c),
                        ),
                      ),
                    ),
                  if (preview != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: widget.cute
                            ? const Color(0xfff8eef3)
                            : const Color(0xffeef4f9),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.aiPreviewReady,
                            style: const TextStyle(fontSize: 10.5),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            l10n.previewObjects(preview.addedObjects),
                            style: const TextStyle(
                              fontSize: 10,
                              color: Color(0xff657687),
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            preview.summary,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 10,
                              color: Color(0xff5d6d7d),
                            ),
                          ),
                          const SizedBox(height: 5),
                          Row(
                            children: [
                              FilledButton(
                                onPressed: () {
                                  widget.onApplyAi(preview.document);
                                  context.read<AiBloc>().markApplied();
                                },
                                style: FilledButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                ),
                                child: Text(
                                  l10n.aiApply,
                                  style: const TextStyle(fontSize: 11),
                                ),
                              ),
                              const SizedBox(width: 4),
                              TextButton(
                                onPressed: () =>
                                    context.read<AiBloc>().discard(),
                                child: Text(
                                  l10n.aiDiscard,
                                  style: const TextStyle(fontSize: 11),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (state.applied)
                    Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: Text(
                        l10n.aiApplied,
                        style: const TextStyle(
                          fontSize: 10.5,
                          color: Color(0xff4f7b52),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  String _measureName(AppLocalizations l10n, MeasurementType type) =>
      switch (type) {
        MeasurementType.length => l10n.measureLength,
        MeasurementType.arcLength => l10n.measureArcLength,
        MeasurementType.angle => l10n.measureAngle,
        MeasurementType.area => l10n.measureArea,
        MeasurementType.slope => l10n.measureSlope,
        MeasurementType.functionValue => l10n.toolFunction,
      };

  IconData _kindIcon(GeometryKind kind) => switch (kind) {
    GeometryKind.point => Icons.circle,
    GeometryKind.segment => Icons.show_chart,
    GeometryKind.line => Icons.horizontal_rule,
    GeometryKind.ray => Icons.arrow_forward,
    GeometryKind.circle => Icons.circle_outlined,
    GeometryKind.arc => Icons.rotate_right,
    GeometryKind.triangle => Icons.change_history,
    GeometryKind.polygon => Icons.pentagon_outlined,
    GeometryKind.conic => Icons.filter_center_focus,
    GeometryKind.function => Icons.functions,
    GeometryKind.vector => Icons.arrow_outward,
    GeometryKind.coordinate => Icons.grid_4x4,
    GeometryKind.solid => Icons.view_in_ar,
  };
}

class _DockTitle extends StatelessWidget {
  const _DockTitle({
    required this.title,
    required this.cute,
    required this.onCollapse,
    required this.collapseTooltip,
  });

  final String title;
  final bool cute;
  final VoidCallback onCollapse;
  final String collapseTooltip;

  @override
  Widget build(BuildContext context) => Container(
    height: 32,
    padding: const EdgeInsets.only(left: 10),
    decoration: BoxDecoration(
      color: cute ? const Color(0xffe9d8e2) : const Color(0xffd2dde7),
      border: const Border(
        bottom: BorderSide(color: Color(0xff899aaa), width: 1.2),
      ),
    ),
    child: Row(
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Color(0xff172b3d),
          ),
        ),
        const Spacer(),
        IconButton(
          tooltip: collapseTooltip,
          onPressed: onCollapse,
          icon: const Icon(Icons.chevron_right, size: 17),
          visualDensity: VisualDensity.compact,
        ),
      ],
    ),
  );
}

class _DockSection extends StatelessWidget {
  const _DockSection({
    required this.title,
    required this.icon,
    required this.cute,
    required this.child,
    this.initiallyExpanded = false,
  });

  final String title;
  final IconData icon;
  final bool cute;
  final Widget child;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) => Theme(
    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
    child: ExpansionTile(
      initiallyExpanded: initiallyExpanded,
      tilePadding: const EdgeInsets.symmetric(horizontal: 10),
      childrenPadding: EdgeInsets.zero,
      dense: true,
      visualDensity: VisualDensity.compact,
      collapsedShape: const Border(),
      shape: Border(
        bottom: BorderSide(
          color: cute ? const Color(0xffe6dce3) : const Color(0xffdde1e6),
        ),
      ),
      leading: Icon(icon, size: 15, color: const Color(0xff6d7e8e)),
      title: Text(
        title,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: Color(0xff203548),
        ),
      ),
      children: [child],
    ),
  );
}

class _PropertyRow extends StatelessWidget {
  const _PropertyRow(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 1.5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 76,
          child: Text(
            label,
            style: const TextStyle(fontSize: 10.5, color: Color(0xff718191)),
          ),
        ),
        Expanded(
          child: Text(
            value,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10.5, color: Color(0xff34495d)),
          ),
        ),
      ],
    ),
  );
}
