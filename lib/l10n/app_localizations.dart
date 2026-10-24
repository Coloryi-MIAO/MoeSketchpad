import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In zh, this message translates to:
  /// **'萌板 / MoeSketchpad'**
  String get appTitle;

  /// No description provided for @menuFile.
  ///
  /// In zh, this message translates to:
  /// **'文件(F)'**
  String get menuFile;

  /// No description provided for @menuEdit.
  ///
  /// In zh, this message translates to:
  /// **'编辑(E)'**
  String get menuEdit;

  /// No description provided for @menuView.
  ///
  /// In zh, this message translates to:
  /// **'视图(V)'**
  String get menuView;

  /// No description provided for @menuLayout.
  ///
  /// In zh, this message translates to:
  /// **'布局(L)'**
  String get menuLayout;

  /// No description provided for @menuObject.
  ///
  /// In zh, this message translates to:
  /// **'对象(O)'**
  String get menuObject;

  /// No description provided for @menuEffects.
  ///
  /// In zh, this message translates to:
  /// **'效果(C)'**
  String get menuEffects;

  /// No description provided for @menuText.
  ///
  /// In zh, this message translates to:
  /// **'文本(T)'**
  String get menuText;

  /// No description provided for @menuTable.
  ///
  /// In zh, this message translates to:
  /// **'表格(A)'**
  String get menuTable;

  /// No description provided for @menuTools.
  ///
  /// In zh, this message translates to:
  /// **'工具(O)'**
  String get menuTools;

  /// No description provided for @menuWindow.
  ///
  /// In zh, this message translates to:
  /// **'窗口(W)'**
  String get menuWindow;

  /// No description provided for @menuHelp.
  ///
  /// In zh, this message translates to:
  /// **'帮助(H)'**
  String get menuHelp;

  /// No description provided for @newDocument.
  ///
  /// In zh, this message translates to:
  /// **'新建'**
  String get newDocument;

  /// No description provided for @open.
  ///
  /// In zh, this message translates to:
  /// **'打开'**
  String get open;

  /// No description provided for @save.
  ///
  /// In zh, this message translates to:
  /// **'保存'**
  String get save;

  /// No description provided for @saveAs.
  ///
  /// In zh, this message translates to:
  /// **'另存为'**
  String get saveAs;

  /// No description provided for @undo.
  ///
  /// In zh, this message translates to:
  /// **'撤销'**
  String get undo;

  /// No description provided for @redo.
  ///
  /// In zh, this message translates to:
  /// **'重做'**
  String get redo;

  /// No description provided for @grid.
  ///
  /// In zh, this message translates to:
  /// **'网格'**
  String get grid;

  /// No description provided for @snap.
  ///
  /// In zh, this message translates to:
  /// **'贴齐'**
  String get snap;

  /// No description provided for @snapGrid.
  ///
  /// In zh, this message translates to:
  /// **'贴齐网格'**
  String get snapGrid;

  /// No description provided for @snapObjects.
  ///
  /// In zh, this message translates to:
  /// **'贴齐对象'**
  String get snapObjects;

  /// No description provided for @zoom.
  ///
  /// In zh, this message translates to:
  /// **'缩放'**
  String get zoom;

  /// No description provided for @language.
  ///
  /// In zh, this message translates to:
  /// **'语言'**
  String get language;

  /// No description provided for @cuteTheme.
  ///
  /// In zh, this message translates to:
  /// **'萌化主题'**
  String get cuteTheme;

  /// No description provided for @professionalTheme.
  ///
  /// In zh, this message translates to:
  /// **'专业主题'**
  String get professionalTheme;

  /// No description provided for @about.
  ///
  /// In zh, this message translates to:
  /// **'关于萌板'**
  String get about;

  /// No description provided for @toolSelect.
  ///
  /// In zh, this message translates to:
  /// **'选择'**
  String get toolSelect;

  /// No description provided for @toolPoint.
  ///
  /// In zh, this message translates to:
  /// **'点'**
  String get toolPoint;

  /// No description provided for @toolSegment.
  ///
  /// In zh, this message translates to:
  /// **'线段'**
  String get toolSegment;

  /// No description provided for @toolLine.
  ///
  /// In zh, this message translates to:
  /// **'直线'**
  String get toolLine;

  /// No description provided for @toolCircle.
  ///
  /// In zh, this message translates to:
  /// **'圆'**
  String get toolCircle;

  /// No description provided for @toolTriangle.
  ///
  /// In zh, this message translates to:
  /// **'三角形'**
  String get toolTriangle;

  /// No description provided for @toolPolygon.
  ///
  /// In zh, this message translates to:
  /// **'多边形'**
  String get toolPolygon;

  /// No description provided for @toolFunction.
  ///
  /// In zh, this message translates to:
  /// **'函数'**
  String get toolFunction;

  /// No description provided for @toolPan.
  ///
  /// In zh, this message translates to:
  /// **'平移'**
  String get toolPan;

  /// No description provided for @toolZoom.
  ///
  /// In zh, this message translates to:
  /// **'缩放'**
  String get toolZoom;

  /// No description provided for @toolText.
  ///
  /// In zh, this message translates to:
  /// **'文本'**
  String get toolText;

  /// No description provided for @toolShape.
  ///
  /// In zh, this message translates to:
  /// **'形状'**
  String get toolShape;

  /// No description provided for @toolFreehand.
  ///
  /// In zh, this message translates to:
  /// **'手绘'**
  String get toolFreehand;

  /// No description provided for @toolRectangle.
  ///
  /// In zh, this message translates to:
  /// **'矩形'**
  String get toolRectangle;

  /// No description provided for @toolEllipse.
  ///
  /// In zh, this message translates to:
  /// **'椭圆'**
  String get toolEllipse;

  /// No description provided for @toolFill.
  ///
  /// In zh, this message translates to:
  /// **'填充'**
  String get toolFill;

  /// No description provided for @toolTransparency.
  ///
  /// In zh, this message translates to:
  /// **'透明度'**
  String get toolTransparency;

  /// No description provided for @toolEyedropper.
  ///
  /// In zh, this message translates to:
  /// **'吸管'**
  String get toolEyedropper;

  /// No description provided for @toolOutline.
  ///
  /// In zh, this message translates to:
  /// **'轮廓'**
  String get toolOutline;

  /// No description provided for @toolMoreInGroup.
  ///
  /// In zh, this message translates to:
  /// **'包含二级工具'**
  String get toolMoreInGroup;

  /// No description provided for @toolNotImplemented.
  ///
  /// In zh, this message translates to:
  /// **'{tool} 尚未接入几何构造；不会伪造可绘制状态。'**
  String toolNotImplemented(Object tool);

  /// No description provided for @contextCanvas.
  ///
  /// In zh, this message translates to:
  /// **'画布'**
  String get contextCanvas;

  /// No description provided for @contextSelection.
  ///
  /// In zh, this message translates to:
  /// **'选中对象'**
  String get contextSelection;

  /// No description provided for @contextPage.
  ///
  /// In zh, this message translates to:
  /// **'页面'**
  String get contextPage;

  /// No description provided for @pageSize.
  ///
  /// In zh, this message translates to:
  /// **'页面尺寸'**
  String get pageSize;

  /// No description provided for @pageLandscape.
  ///
  /// In zh, this message translates to:
  /// **'横向'**
  String get pageLandscape;

  /// No description provided for @unit.
  ///
  /// In zh, this message translates to:
  /// **'单位'**
  String get unit;

  /// No description provided for @properties.
  ///
  /// In zh, this message translates to:
  /// **'属性'**
  String get properties;

  /// No description provided for @objects.
  ///
  /// In zh, this message translates to:
  /// **'对象'**
  String get objects;

  /// No description provided for @layers.
  ///
  /// In zh, this message translates to:
  /// **'图层'**
  String get layers;

  /// No description provided for @measurements.
  ///
  /// In zh, this message translates to:
  /// **'测量'**
  String get measurements;

  /// No description provided for @animations.
  ///
  /// In zh, this message translates to:
  /// **'动画'**
  String get animations;

  /// No description provided for @aiAssistant.
  ///
  /// In zh, this message translates to:
  /// **'AI 助手'**
  String get aiAssistant;

  /// No description provided for @dockCollapse.
  ///
  /// In zh, this message translates to:
  /// **'收起泊坞窗'**
  String get dockCollapse;

  /// No description provided for @dockExpand.
  ///
  /// In zh, this message translates to:
  /// **'展开泊坞窗'**
  String get dockExpand;

  /// No description provided for @statusObjects.
  ///
  /// In zh, this message translates to:
  /// **'{count} 个对象'**
  String statusObjects(Object count);

  /// No description provided for @statusZoom.
  ///
  /// In zh, this message translates to:
  /// **'缩放 {zoom}%'**
  String statusZoom(Object zoom);

  /// No description provided for @statusOrigin.
  ///
  /// In zh, this message translates to:
  /// **'世界原点 ({x}, {y})'**
  String statusOrigin(Object x, Object y);

  /// No description provided for @statusToolHintSelect.
  ///
  /// In zh, this message translates to:
  /// **'拖拽对象或框选；滚轮缩放，空格拖动画布。'**
  String get statusToolHintSelect;

  /// No description provided for @statusToolHintPoint.
  ///
  /// In zh, this message translates to:
  /// **'点击画布创建点。'**
  String get statusToolHintPoint;

  /// No description provided for @statusToolHintSegment.
  ///
  /// In zh, this message translates to:
  /// **'依次点击两个端点。'**
  String get statusToolHintSegment;

  /// No description provided for @statusToolHintLine.
  ///
  /// In zh, this message translates to:
  /// **'依次点击直线上的两点。'**
  String get statusToolHintLine;

  /// No description provided for @statusToolHintCircle.
  ///
  /// In zh, this message translates to:
  /// **'先点圆心，再点圆周。'**
  String get statusToolHintCircle;

  /// No description provided for @statusToolHintTriangle.
  ///
  /// In zh, this message translates to:
  /// **'依次点击三角形的三个顶点。'**
  String get statusToolHintTriangle;

  /// No description provided for @statusToolHintPolygon.
  ///
  /// In zh, this message translates to:
  /// **'点击顶点，双击或回车完成多边形。'**
  String get statusToolHintPolygon;

  /// No description provided for @statusToolHintPan.
  ///
  /// In zh, this message translates to:
  /// **'拖动画布平移视口。'**
  String get statusToolHintPan;

  /// No description provided for @statusToolHintMeasurement.
  ///
  /// In zh, this message translates to:
  /// **'选择对象后可添加测量。'**
  String get statusToolHintMeasurement;

  /// No description provided for @untitled.
  ///
  /// In zh, this message translates to:
  /// **'未命名-{index}'**
  String untitled(Object index);

  /// No description provided for @noObjects.
  ///
  /// In zh, this message translates to:
  /// **'暂无对象'**
  String get noObjects;

  /// No description provided for @noMeasurements.
  ///
  /// In zh, this message translates to:
  /// **'暂无测量'**
  String get noMeasurements;

  /// No description provided for @noAnimations.
  ///
  /// In zh, this message translates to:
  /// **'暂无动画'**
  String get noAnimations;

  /// No description provided for @addMeasure.
  ///
  /// In zh, this message translates to:
  /// **'添加测量'**
  String get addMeasure;

  /// No description provided for @measureLength.
  ///
  /// In zh, this message translates to:
  /// **'长度'**
  String get measureLength;

  /// No description provided for @measureAngle.
  ///
  /// In zh, this message translates to:
  /// **'角度'**
  String get measureAngle;

  /// No description provided for @measureArea.
  ///
  /// In zh, this message translates to:
  /// **'面积'**
  String get measureArea;

  /// No description provided for @measureSlope.
  ///
  /// In zh, this message translates to:
  /// **'斜率'**
  String get measureSlope;

  /// No description provided for @measureArcLength.
  ///
  /// In zh, this message translates to:
  /// **'弧长'**
  String get measureArcLength;

  /// No description provided for @measureUnitless.
  ///
  /// In zh, this message translates to:
  /// **'无单位'**
  String get measureUnitless;

  /// No description provided for @playAnimation.
  ///
  /// In zh, this message translates to:
  /// **'播放'**
  String get playAnimation;

  /// No description provided for @pauseAnimation.
  ///
  /// In zh, this message translates to:
  /// **'暂停'**
  String get pauseAnimation;

  /// No description provided for @resetAnimation.
  ///
  /// In zh, this message translates to:
  /// **'重置'**
  String get resetAnimation;

  /// No description provided for @animationTrail.
  ///
  /// In zh, this message translates to:
  /// **'轨迹'**
  String get animationTrail;

  /// No description provided for @addAnimation.
  ///
  /// In zh, this message translates to:
  /// **'让选中点沿选中对象运动'**
  String get addAnimation;

  /// No description provided for @deleteSelection.
  ///
  /// In zh, this message translates to:
  /// **'删除选中'**
  String get deleteSelection;

  /// No description provided for @saveDialogTitle.
  ///
  /// In zh, this message translates to:
  /// **'保存更改'**
  String get saveDialogTitle;

  /// No description provided for @saveDialogMessage.
  ///
  /// In zh, this message translates to:
  /// **'是否将更改保存到 {name}？'**
  String saveDialogMessage(Object name);

  /// No description provided for @dontSave.
  ///
  /// In zh, this message translates to:
  /// **'不保存'**
  String get dontSave;

  /// No description provided for @cancel.
  ///
  /// In zh, this message translates to:
  /// **'取消'**
  String get cancel;

  /// No description provided for @passwordTitle.
  ///
  /// In zh, this message translates to:
  /// **'文档密码'**
  String get passwordTitle;

  /// No description provided for @passwordOpenLabel.
  ///
  /// In zh, this message translates to:
  /// **'输入 .moesp 文档密码'**
  String get passwordOpenLabel;

  /// No description provided for @passwordSaveLabel.
  ///
  /// In zh, this message translates to:
  /// **'为 .moesp 文档设置密码（不能为空）'**
  String get passwordSaveLabel;

  /// No description provided for @passwordTooShort.
  ///
  /// In zh, this message translates to:
  /// **'密码不能为空。'**
  String get passwordTooShort;

  /// No description provided for @openFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法打开文档：{error}'**
  String openFailed(Object error);

  /// No description provided for @saveFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法保存文档：{error}'**
  String saveFailed(Object error);

  /// No description provided for @invalidPassword.
  ///
  /// In zh, this message translates to:
  /// **'密码错误或文件已被篡改。'**
  String get invalidPassword;

  /// No description provided for @fileFilterMsp.
  ///
  /// In zh, this message translates to:
  /// **'MoeSketchpad 文档'**
  String get fileFilterMsp;

  /// No description provided for @aiPrompt.
  ///
  /// In zh, this message translates to:
  /// **'输入几何需求，或粘贴 AI 返回的 JSON 提案。'**
  String get aiPrompt;

  /// No description provided for @aiSend.
  ///
  /// In zh, this message translates to:
  /// **'生成预览'**
  String get aiSend;

  /// No description provided for @aiApply.
  ///
  /// In zh, this message translates to:
  /// **'应用到画布'**
  String get aiApply;

  /// No description provided for @aiDiscard.
  ///
  /// In zh, this message translates to:
  /// **'放弃'**
  String get aiDiscard;

  /// No description provided for @aiNoModel.
  ///
  /// In zh, this message translates to:
  /// **'当前未连接模型。MCP 工具已启用；也可粘贴结构化 JSON 提案进行预览。'**
  String get aiNoModel;

  /// No description provided for @aiPreviewReady.
  ///
  /// In zh, this message translates to:
  /// **'预览已就绪，确认后才会写入文档。'**
  String get aiPreviewReady;

  /// No description provided for @aiInvaldProposal.
  ///
  /// In zh, this message translates to:
  /// **'提案格式无效：{error}'**
  String aiInvaldProposal(Object error);

  /// No description provided for @aiApplied.
  ///
  /// In zh, this message translates to:
  /// **'AI 提案已应用。'**
  String get aiApplied;

  /// No description provided for @aiAssistantTitle.
  ///
  /// In zh, this message translates to:
  /// **'几何绘图助手'**
  String get aiAssistantTitle;

  /// No description provided for @measurementLabel.
  ///
  /// In zh, this message translates to:
  /// **'{type}: {value}'**
  String measurementLabel(Object type, Object value);

  /// No description provided for @newTab.
  ///
  /// In zh, this message translates to:
  /// **'新建文档'**
  String get newTab;

  /// No description provided for @closeTab.
  ///
  /// In zh, this message translates to:
  /// **'关闭标签页'**
  String get closeTab;

  /// No description provided for @pageA4.
  ///
  /// In zh, this message translates to:
  /// **'A4'**
  String get pageA4;

  /// No description provided for @rulerOriginReset.
  ///
  /// In zh, this message translates to:
  /// **'右键重置标尺原点'**
  String get rulerOriginReset;

  /// No description provided for @guideHint.
  ///
  /// In zh, this message translates to:
  /// **'从标尺拖出辅助线'**
  String get guideHint;

  /// No description provided for @loading.
  ///
  /// In zh, this message translates to:
  /// **'处理中…'**
  String get loading;

  /// No description provided for @unsupportedExport.
  ///
  /// In zh, this message translates to:
  /// **'该导出格式尚未接入经过验证的编码器。'**
  String get unsupportedExport;

  /// No description provided for @aboutVersion.
  ///
  /// In zh, this message translates to:
  /// **'版本 {version}（构建 {build}）'**
  String aboutVersion(Object build, Object version);

  /// No description provided for @aboutBuild.
  ///
  /// In zh, this message translates to:
  /// **'构建于 {date} · {commit}'**
  String aboutBuild(Object commit, Object date);

  /// No description provided for @aboutAuthor.
  ///
  /// In zh, this message translates to:
  /// **'作者：Coloryi-MIAO'**
  String get aboutAuthor;

  /// No description provided for @aboutLicense.
  ///
  /// In zh, this message translates to:
  /// **'GNU General Public License v3.0 (GPL-3.0-only)'**
  String get aboutLicense;

  /// No description provided for @aboutSource.
  ///
  /// In zh, this message translates to:
  /// **'源代码与问题反馈'**
  String get aboutSource;

  /// No description provided for @aboutNotice.
  ///
  /// In zh, this message translates to:
  /// **'第三方组件与许可证'**
  String get aboutNotice;

  /// No description provided for @aboutCopyright.
  ///
  /// In zh, this message translates to:
  /// **'Copyright (C) 2026 Coloryi-MIAO'**
  String get aboutCopyright;

  /// No description provided for @licenseFull.
  ///
  /// In zh, this message translates to:
  /// **'查看 GPL-3.0 协议全文'**
  String get licenseFull;

  /// No description provided for @close.
  ///
  /// In zh, this message translates to:
  /// **'关闭'**
  String get close;

  /// No description provided for @unsavedTitle.
  ///
  /// In zh, this message translates to:
  /// **'未保存的更改'**
  String get unsavedTitle;

  /// No description provided for @tabCloseTitle.
  ///
  /// In zh, this message translates to:
  /// **'关闭文档'**
  String get tabCloseTitle;

  /// No description provided for @fileAssociation.
  ///
  /// In zh, this message translates to:
  /// **'MIME: application/x-moesketchpad'**
  String get fileAssociation;

  /// No description provided for @experimental.
  ///
  /// In zh, this message translates to:
  /// **'实验性构建'**
  String get experimental;

  /// No description provided for @settings.
  ///
  /// In zh, this message translates to:
  /// **'设置'**
  String get settings;

  /// No description provided for @font.
  ///
  /// In zh, this message translates to:
  /// **'字体'**
  String get font;

  /// No description provided for @fontFallbackNotice.
  ///
  /// In zh, this message translates to:
  /// **'Web 无法枚举本地系统字体；将使用回退字体栈。'**
  String get fontFallbackNotice;

  /// No description provided for @fontCuratedNotice.
  ///
  /// In zh, this message translates to:
  /// **'当前使用内置字体候选；系统字体枚举需要可选原生插件。'**
  String get fontCuratedNotice;

  /// No description provided for @renderLayers.
  ///
  /// In zh, this message translates to:
  /// **'渲染层'**
  String get renderLayers;

  /// No description provided for @fitView.
  ///
  /// In zh, this message translates to:
  /// **'适合窗口'**
  String get fitView;

  /// No description provided for @exportPage.
  ///
  /// In zh, this message translates to:
  /// **'导出页面 SVG'**
  String get exportPage;

  /// No description provided for @visibility.
  ///
  /// In zh, this message translates to:
  /// **'可见性'**
  String get visibility;

  /// No description provided for @notImplemented.
  ///
  /// In zh, this message translates to:
  /// **'{feature} 尚未实现或未接入本构建。'**
  String notImplemented(Object feature);

  /// No description provided for @previewObjects.
  ///
  /// In zh, this message translates to:
  /// **'预览：将新增 {count} 个对象'**
  String previewObjects(int count);

  /// No description provided for @copyPrompt.
  ///
  /// In zh, this message translates to:
  /// **'复制系统提示词'**
  String get copyPrompt;

  /// No description provided for @promptCopied.
  ///
  /// In zh, this message translates to:
  /// **'系统提示词已复制。'**
  String get promptCopied;

  /// No description provided for @selectObjectFirst.
  ///
  /// In zh, this message translates to:
  /// **'请先选择一个对象。'**
  String get selectObjectFirst;

  /// No description provided for @addAnimationRequirement.
  ///
  /// In zh, this message translates to:
  /// **'请按住 Shift 选择两个对象：一个点和一个路径（线段、圆、弧、函数或多边形）。'**
  String get addAnimationRequirement;

  /// No description provided for @noAnimationsHint.
  ///
  /// In zh, this message translates to:
  /// **'可通过“沿路径运动”按钮创建动点动画。'**
  String get noAnimationsHint;

  /// No description provided for @labelEdit.
  ///
  /// In zh, this message translates to:
  /// **'编辑标注'**
  String get labelEdit;

  /// No description provided for @apply.
  ///
  /// In zh, this message translates to:
  /// **'应用'**
  String get apply;

  /// No description provided for @discard.
  ///
  /// In zh, this message translates to:
  /// **'放弃'**
  String get discard;

  /// No description provided for @layer.
  ///
  /// In zh, this message translates to:
  /// **'图层'**
  String get layer;

  /// No description provided for @openPassword.
  ///
  /// In zh, this message translates to:
  /// **'打开'**
  String get openPassword;

  /// No description provided for @savePassword.
  ///
  /// In zh, this message translates to:
  /// **'保存'**
  String get savePassword;

  /// No description provided for @objectIdLabel.
  ///
  /// In zh, this message translates to:
  /// **'对象 ID'**
  String get objectIdLabel;

  /// No description provided for @statusHintPageDimension.
  ///
  /// In zh, this message translates to:
  /// **'{w} × {h} mm'**
  String statusHintPageDimension(Object h, Object w);

  /// No description provided for @resetOrigin.
  ///
  /// In zh, this message translates to:
  /// **'重置原点'**
  String get resetOrigin;

  /// No description provided for @geometrySettings.
  ///
  /// In zh, this message translates to:
  /// **'几何设定'**
  String get geometrySettings;

  /// No description provided for @geometryUnit.
  ///
  /// In zh, this message translates to:
  /// **'长度单位'**
  String get geometryUnit;

  /// No description provided for @geometryGridSpacing.
  ///
  /// In zh, this message translates to:
  /// **'基础网格间距'**
  String get geometryGridSpacing;

  /// No description provided for @geometryGridSpacingHint.
  ///
  /// In zh, this message translates to:
  /// **'世界坐标单位；网格会随缩放自适应'**
  String get geometryGridSpacingHint;

  /// No description provided for @geometryTolerance.
  ///
  /// In zh, this message translates to:
  /// **'数值容差'**
  String get geometryTolerance;

  /// No description provided for @geometryToleranceHint.
  ///
  /// In zh, this message translates to:
  /// **'用于约束求解和退化构造判定'**
  String get geometryToleranceHint;

  /// No description provided for @geometrySnapTolerance.
  ///
  /// In zh, this message translates to:
  /// **'吸附范围'**
  String get geometrySnapTolerance;

  /// No description provided for @geometryDegenerate.
  ///
  /// In zh, this message translates to:
  /// **'两点过于接近，无法构造该几何对象。请调整容差或选择不同位置。'**
  String get geometryDegenerate;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
