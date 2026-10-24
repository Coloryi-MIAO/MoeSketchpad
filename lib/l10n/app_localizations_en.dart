// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'MoeSketchpad';

  @override
  String get menuFile => 'File (F)';

  @override
  String get menuEdit => 'Edit (E)';

  @override
  String get menuView => 'View (V)';

  @override
  String get menuLayout => 'Layout (L)';

  @override
  String get menuObject => 'Object (O)';

  @override
  String get menuEffects => 'Effects (C)';

  @override
  String get menuText => 'Text (T)';

  @override
  String get menuTools => 'Tools (O)';

  @override
  String get menuWindow => 'Window (W)';

  @override
  String get menuHelp => 'Help (H)';

  @override
  String get newDocument => 'New';

  @override
  String get open => 'Open';

  @override
  String get save => 'Save';

  @override
  String get saveAs => 'Save As';

  @override
  String get saveFileNameTitle => 'Save document';

  @override
  String get saveFileNameLabel => 'File name';

  @override
  String get invalidSaveFileName =>
      'Enter a valid file name without paths or reserved characters.';

  @override
  String get continueLabel => 'Continue';

  @override
  String get undo => 'Undo';

  @override
  String get redo => 'Redo';

  @override
  String get grid => 'Grid';

  @override
  String get snap => 'Snap';

  @override
  String get snapGrid => 'Snap to grid';

  @override
  String get snapObjects => 'Snap to objects';

  @override
  String get zoom => 'Zoom';

  @override
  String get language => 'Language';

  @override
  String get cuteTheme => 'Cute theme';

  @override
  String get professionalTheme => 'Professional theme';

  @override
  String get about => 'About MoeSketchpad';

  @override
  String get toolSelect => 'Select';

  @override
  String get toolPoint => 'Point';

  @override
  String get toolSegment => 'Segment';

  @override
  String get toolLine => 'Line';

  @override
  String get toolCircle => 'Circle';

  @override
  String get toolTriangle => 'Triangle';

  @override
  String get toolPolygon => 'Polygon';

  @override
  String get toolFunction => 'Function';

  @override
  String get toolPan => 'Pan';

  @override
  String get toolZoom => 'Zoom';

  @override
  String get toolText => 'Text';

  @override
  String get toolShape => 'Shape';

  @override
  String get toolFreehand => 'Freehand';

  @override
  String get toolRectangle => 'Rectangle';

  @override
  String get toolEllipse => 'Ellipse';

  @override
  String get toolFill => 'Fill';

  @override
  String get toolTransparency => 'Transparency';

  @override
  String get toolEyedropper => 'Eyedropper';

  @override
  String get toolOutline => 'Outline';

  @override
  String get toolMoreInGroup => 'Has a flyout group';

  @override
  String toolNotImplemented(Object tool) {
    return '$tool is not wired to geometry construction yet; availability is not faked.';
  }

  @override
  String get contextCanvas => 'Canvas';

  @override
  String get contextSelection => 'Selection';

  @override
  String get contextPage => 'Page';

  @override
  String get pageSize => 'Page size';

  @override
  String get pageLandscape => 'Landscape';

  @override
  String get unit => 'Units';

  @override
  String get properties => 'Properties';

  @override
  String get objects => 'Objects';

  @override
  String get layers => 'Layers';

  @override
  String get measurements => 'Measurements';

  @override
  String get animations => 'Animations';

  @override
  String get aiAssistant => 'AI Assistant';

  @override
  String get dockCollapse => 'Collapse dock';

  @override
  String get dockExpand => 'Expand dock';

  @override
  String statusObjects(Object count) {
    return '$count objects';
  }

  @override
  String statusZoom(Object zoom) {
    return 'Zoom $zoom%';
  }

  @override
  String statusOrigin(Object x, Object y) {
    return 'World origin ($x, $y)';
  }

  @override
  String get statusToolHintSelect =>
      'Drag objects or rubber-band select; wheel zooms, Space+drag pans.';

  @override
  String get statusToolHintPoint => 'Click the canvas to create a point.';

  @override
  String get statusToolHintSegment => 'Click the two endpoints.';

  @override
  String get statusToolHintLine => 'Click two points on the line.';

  @override
  String get statusToolHintCircle =>
      'Click the center, then a point on the circle.';

  @override
  String get statusToolHintTriangle => 'Click the three vertices.';

  @override
  String get statusToolHintPolygon =>
      'Click vertices, then double-click or press Enter.';

  @override
  String get statusToolHintPan => 'Drag the canvas to pan.';

  @override
  String get statusToolHintZoom =>
      'Click the canvas to zoom in; use the wheel for continuous zoom.';

  @override
  String get statusToolHintRectangle =>
      'Drag to draw a rectangle; hold Shift to draw a square.';

  @override
  String get statusToolHintEllipse =>
      'Drag to draw an ellipse; hold Shift to draw a circle.';

  @override
  String get statusToolHintFunction =>
      'Click the canvas to enter a function and its domain.';

  @override
  String get statusToolHintText => 'Click the canvas to enter and place text.';

  @override
  String get statusToolHintFreehand =>
      'Press and drag to draw a freehand curve.';

  @override
  String get statusToolHintFill =>
      'Click a closed shape to set its fill color.';

  @override
  String get statusToolHintTransparency =>
      'Click an object to adjust its opacity.';

  @override
  String get statusToolHintEyedropper =>
      'Click an object to sample its stroke color.';

  @override
  String get statusToolHintOutline =>
      'Click an object to adjust its stroke width and color.';

  @override
  String get statusToolHintMeasurement =>
      'Select an object to add a measurement.';

  @override
  String untitled(Object index) {
    return 'Untitled-$index';
  }

  @override
  String get noObjects => 'No objects yet';

  @override
  String get noMeasurements => 'No measurements yet';

  @override
  String get noAnimations => 'No animations yet';

  @override
  String get addMeasure => 'Add measurement';

  @override
  String get measureLength => 'Length';

  @override
  String get measureAngle => 'Angle';

  @override
  String get measureArea => 'Area';

  @override
  String get measureSlope => 'Slope';

  @override
  String get measureArcLength => 'Arc length';

  @override
  String get measureUnitless => 'Unitless';

  @override
  String get playAnimation => 'Play';

  @override
  String get pauseAnimation => 'Pause';

  @override
  String get resetAnimation => 'Reset';

  @override
  String get animationTrail => 'Trail';

  @override
  String get addAnimation => 'Move selected point along selected object';

  @override
  String get deleteSelection => 'Delete selection';

  @override
  String get saveDialogTitle => 'Save changes';

  @override
  String saveDialogMessage(Object name) {
    return 'Do you want to save changes to $name?';
  }

  @override
  String get dontSave => 'Don\'t Save';

  @override
  String get cancel => 'Cancel';

  @override
  String get passwordTitle => 'Document password';

  @override
  String get passwordOpenLabel => 'Enter the .moesp document password';

  @override
  String get passwordSaveLabel =>
      'Set a non-empty password for the .moesp document';

  @override
  String get passwordTooShort => 'Password must not be empty.';

  @override
  String openFailed(Object error) {
    return 'Could not open document: $error';
  }

  @override
  String saveFailed(Object error) {
    return 'Could not save document: $error';
  }

  @override
  String get invalidPassword =>
      'Incorrect password or the file has been tampered with.';

  @override
  String get fileFilterMsp => 'MoeSketchpad documents';

  @override
  String get aiPrompt =>
      'Describe geometry or paste a JSON proposal from the AI.';

  @override
  String get aiConnectionHelp =>
      'OpenAI-compatible Chat Completions API. Only your prompt and the app\'s system instructions are sent; no canvas document is sent. Web endpoints must allow CORS.';

  @override
  String get aiEndpoint => 'API endpoint';

  @override
  String get aiModel => 'Model name';

  @override
  String get aiApiKey => 'API key';

  @override
  String get aiApiKeyHint => 'Paste the API key from your provider';

  @override
  String get aiApiKeySavedHint =>
      'Saved; leave blank to keep using the stored key';

  @override
  String get aiKeyStorageNotice =>
      'Desktop uses platform secure storage; Web encrypts it in this browser. Keys never enter documents or logs. Use trusted endpoints/devices only.';

  @override
  String get aiClearApiKey => 'Clear saved key';

  @override
  String get aiSaveSettings => 'Save settings';

  @override
  String get aiSettingsSaved => 'AI settings saved securely.';

  @override
  String get aiShowKey => 'Show API key';

  @override
  String get aiHideKey => 'Hide API key';

  @override
  String get aiSend => 'Preview';

  @override
  String get aiApply => 'Apply to canvas';

  @override
  String get aiDiscard => 'Discard';

  @override
  String get aiNoModel =>
      'No model connected. MCP tools are enabled; you can also paste a structured JSON proposal for preview.';

  @override
  String get aiPreviewReady =>
      'Preview ready. Nothing is written until you confirm.';

  @override
  String aiInvaldProposal(Object error) {
    return 'AI request failed or proposal is invalid: $error';
  }

  @override
  String get aiApplied => 'AI proposal applied.';

  @override
  String get aiAssistantTitle => 'Geometry drawing assistant';

  @override
  String measurementLabel(Object type, Object value) {
    return '$type: $value';
  }

  @override
  String get newTab => 'New document';

  @override
  String get closeTab => 'Close tab';

  @override
  String get pageA4 => 'A4';

  @override
  String get rulerOriginReset => 'Right-click to reset the ruler origin';

  @override
  String get guideHint => 'Drag from a ruler to create a guide';

  @override
  String get loading => 'Working…';

  @override
  String get unsupportedExport =>
      'This export format has no verified encoder in this build.';

  @override
  String aboutVersion(Object build, Object version) {
    return 'Version $version (build $build)';
  }

  @override
  String aboutBuild(Object commit, Object date) {
    return 'Built $date · $commit';
  }

  @override
  String get aboutAuthor => 'Author: Coloryi-MIAO';

  @override
  String get aboutLicense => 'GNU General Public License v3.0 (GPL-3.0-only)';

  @override
  String get aboutSource => 'Source repository and issue tracker';

  @override
  String get aboutNotice => 'Third-party components and licenses';

  @override
  String get aboutCopyright => 'Copyright (C) 2026 Coloryi-MIAO';

  @override
  String get licenseFull => 'Read the full GPL-3.0 license';

  @override
  String get close => 'Close';

  @override
  String get unsavedTitle => 'Unsaved changes';

  @override
  String get tabCloseTitle => 'Close document';

  @override
  String get fileAssociation => 'MIME: application/x-moesketchpad';

  @override
  String get experimental => 'Experimental build';

  @override
  String get settings => 'Settings';

  @override
  String get font => 'Font';

  @override
  String get fontFallbackNotice =>
      'Web cannot enumerate local fonts; a fallback stack will be used.';

  @override
  String get fontCuratedNotice =>
      'A curated font list is used; native system-font enumeration requires an optional plugin.';

  @override
  String get renderLayers => 'Render layers';

  @override
  String get fitView => 'Fit to window';

  @override
  String get exportPage => 'Export page SVG';

  @override
  String get visibility => 'Visibility';

  @override
  String notImplemented(Object feature) {
    return '$feature is not implemented or wired in this build.';
  }

  @override
  String previewObjects(int count) {
    return 'Preview: $count object(s) will be added';
  }

  @override
  String get copyPrompt => 'Copy system prompt';

  @override
  String get promptCopied => 'System prompt copied.';

  @override
  String get selectObjectFirst => 'Select an object first.';

  @override
  String get addAnimationRequirement =>
      'Shift-select exactly two objects: a point and a path (segment, circle, arc, function or polygon).';

  @override
  String get noAnimationsHint =>
      'Create an animation with the “move along path” button.';

  @override
  String get labelEdit => 'Edit label';

  @override
  String get strokeColor => 'Stroke color';

  @override
  String get apply => 'Apply';

  @override
  String get discard => 'Discard';

  @override
  String get layer => 'Layer';

  @override
  String get openPassword => 'Open';

  @override
  String get savePassword => 'Save';

  @override
  String get objectIdLabel => 'Object ID';

  @override
  String statusHintPageDimension(Object h, Object w) {
    return '$w × $h mm';
  }

  @override
  String get resetOrigin => 'Reset origin';

  @override
  String get geometrySettings => 'Geometry settings';

  @override
  String get geometryUnit => 'Length unit';

  @override
  String get geometryGridSpacing => 'Base grid spacing';

  @override
  String get geometryGridSpacingHint => 'World units; grid adapts as you zoom';

  @override
  String get geometryTolerance => 'Numerical tolerance';

  @override
  String get geometryToleranceHint =>
      'Used by constraint solving and degenerate construction checks';

  @override
  String get geometrySnapTolerance => 'Snap radius';

  @override
  String get geometryDegenerate =>
      'The points are too close to construct this object. Adjust tolerance or choose different positions.';
}
