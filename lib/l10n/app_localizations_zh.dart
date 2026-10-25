// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => '萌板 / MoeSketchpad';

  @override
  String get menuFile => '文件(F)';

  @override
  String get menuEdit => '编辑(E)';

  @override
  String get menuView => '视图(V)';

  @override
  String get menuLayout => '布局(L)';

  @override
  String get menuObject => '对象(O)';

  @override
  String get menuEffects => '效果(C)';

  @override
  String get menuText => '文本(T)';

  @override
  String get menuTools => '工具(O)';

  @override
  String get menuWindow => '窗口(W)';

  @override
  String get menuHelp => '帮助(H)';

  @override
  String get newDocument => '新建';

  @override
  String get open => '打开';

  @override
  String get save => '保存';

  @override
  String get saveAs => '另存为';

  @override
  String get saveFileNameTitle => '保存文档';

  @override
  String get saveFileNameLabel => '文件名';

  @override
  String get invalidSaveFileName => '请输入有效文件名，不能包含路径或系统保留字符。';

  @override
  String get continueLabel => '继续';

  @override
  String get undo => '撤销';

  @override
  String get redo => '重做';

  @override
  String get grid => '网格';

  @override
  String get snap => '贴齐';

  @override
  String get snapGrid => '贴齐网格';

  @override
  String get snapObjects => '贴齐对象';

  @override
  String get zoom => '缩放';

  @override
  String get language => '语言';

  @override
  String get cuteTheme => '萌化主题';

  @override
  String get professionalTheme => '专业主题';

  @override
  String get about => '关于萌板';

  @override
  String get toolSelect => '选择';

  @override
  String get toolPoint => '点';

  @override
  String get toolSegment => '线段';

  @override
  String get toolLine => '直线';

  @override
  String get toolCircle => '圆';

  @override
  String get toolTriangle => '三角形';

  @override
  String get toolPolygon => '多边形';

  @override
  String get toolFunction => '函数';

  @override
  String get toolPan => '平移';

  @override
  String get toolZoom => '缩放';

  @override
  String get toolText => '文本';

  @override
  String get toolShape => '形状';

  @override
  String get toolFreehand => '手绘';

  @override
  String get toolRectangle => '矩形';

  @override
  String get toolEllipse => '椭圆';

  @override
  String get toolFill => '填充';

  @override
  String get toolTransparency => '透明度';

  @override
  String get toolEyedropper => '吸管';

  @override
  String get toolOutline => '轮廓';

  @override
  String get toolMoreInGroup => '包含二级工具';

  @override
  String toolNotImplemented(Object tool) {
    return '$tool 尚未接入几何构造；不会伪造可绘制状态。';
  }

  @override
  String get contextCanvas => '画布';

  @override
  String get contextSelection => '选中对象';

  @override
  String get contextPage => '页面';

  @override
  String get pageSize => '页面尺寸';

  @override
  String get pageLandscape => '横向';

  @override
  String get unit => '单位';

  @override
  String get properties => '属性';

  @override
  String get objects => '对象';

  @override
  String get layers => '图层';

  @override
  String get measurements => '测量';

  @override
  String get animations => '动画';

  @override
  String get aiAssistant => 'AI 助手';

  @override
  String get dockCollapse => '收起泊坞窗';

  @override
  String get dockExpand => '展开泊坞窗';

  @override
  String statusObjects(Object count) {
    return '$count 个对象';
  }

  @override
  String statusZoom(Object zoom) {
    return '缩放 $zoom%';
  }

  @override
  String statusOrigin(Object x, Object y) {
    return '世界原点 ($x, $y)';
  }

  @override
  String get statusToolHintSelect => '拖拽对象或框选；滚轮缩放，空格拖动画布。';

  @override
  String get statusToolHintPoint => '点击画布创建点。';

  @override
  String get statusToolHintSegment => '依次点击两个端点。';

  @override
  String get statusToolHintLine => '依次点击直线上的两点。';

  @override
  String get statusToolHintCircle => '先点圆心，再点圆周。';

  @override
  String get statusToolHintTriangle => '依次点击三角形的三个顶点。';

  @override
  String get statusToolHintPolygon => '点击顶点，双击或回车完成多边形。';

  @override
  String get statusToolHintPan => '拖动画布平移视口。';

  @override
  String get statusToolHintZoom => '点击画布放大；滚轮可连续缩放。';

  @override
  String get statusToolHintRectangle => '按住拖动画出矩形；按住 Shift 绘制正方形。';

  @override
  String get statusToolHintEllipse => '按住拖动画出椭圆；按住 Shift 绘制圆。';

  @override
  String get statusToolHintFunction => '点击画布输入函数表达式并设置定义域。';

  @override
  String get statusToolHintText => '点击画布输入并放置文本。';

  @override
  String get statusToolHintFreehand => '按住并拖动画出自由曲线。';

  @override
  String get statusToolHintFill => '点击封闭图形设置填充颜色。';

  @override
  String get statusToolHintTransparency => '点击对象调整透明度。';

  @override
  String get statusToolHintEyedropper => '点击对象吸取其线条颜色。';

  @override
  String get statusToolHintOutline => '点击对象调整轮廓线宽与颜色。';

  @override
  String get statusToolHintMeasurement => '选择对象后可添加测量。';

  @override
  String untitled(Object index) {
    return '未命名-$index';
  }

  @override
  String get noObjects => '暂无对象';

  @override
  String get noMeasurements => '暂无测量';

  @override
  String get noAnimations => '暂无动画';

  @override
  String get addMeasure => '添加测量';

  @override
  String get measureLength => '长度';

  @override
  String get measureAngle => '角度';

  @override
  String get measureArea => '面积';

  @override
  String get measureSlope => '斜率';

  @override
  String get measureArcLength => '弧长';

  @override
  String get measureUnitless => '无单位';

  @override
  String get playAnimation => '播放';

  @override
  String get pauseAnimation => '暂停';

  @override
  String get resetAnimation => '重置';

  @override
  String get animationTrail => '轨迹';

  @override
  String get addAnimation => '让选中点沿选中对象运动';

  @override
  String get deleteSelection => '删除选中';

  @override
  String get saveDialogTitle => '保存更改';

  @override
  String saveDialogMessage(Object name) {
    return '是否将更改保存到 $name？';
  }

  @override
  String get dontSave => '不保存';

  @override
  String get cancel => '取消';

  @override
  String get passwordTitle => '文档密码';

  @override
  String get passwordOpenLabel => '输入 .moesp 文档密码';

  @override
  String get passwordSaveLabel => '为 .moesp 文档设置密码（不能为空）';

  @override
  String get passwordTooShort => '密码不能为空。';

  @override
  String openFailed(Object error) {
    return '无法打开文档：$error';
  }

  @override
  String saveFailed(Object error) {
    return '无法保存文档：$error';
  }

  @override
  String get invalidPassword => '密码错误或文件已被篡改。';

  @override
  String get fileFilterMsp => 'MoeSketchpad 文档';

  @override
  String get aiPrompt => '输入几何需求，或粘贴 AI 返回的 JSON 提案。';

  @override
  String get aiConnectionHelp =>
      'OpenAI 兼容 Chat Completions 接口。仅发送你输入的提示词与应用系统提示词，不发送画布文档；Web 端点需允许 CORS。';

  @override
  String get aiEndpoint => 'API 地址';

  @override
  String get aiModel => '模型名称';

  @override
  String get aiApiKey => 'API Key';

  @override
  String get aiApiKeyHint => '粘贴服务商提供的 API Key';

  @override
  String get aiApiKeySavedHint => '已保存；留空则继续使用已保存的 Key';

  @override
  String get aiKeyStorageNotice =>
      '桌面端使用系统安全存储；Web 端加密保存在当前浏览器。Key 不写入文档或日志，请仅使用可信端点/设备。';

  @override
  String get aiClearApiKey => '清除已保存的 Key';

  @override
  String get aiSaveSettings => '保存配置';

  @override
  String get aiSettingsSaved => 'AI 配置已安全保存。';

  @override
  String get aiShowKey => '显示 API Key';

  @override
  String get aiHideKey => '隐藏 API Key';

  @override
  String get aiSend => '生成预览';

  @override
  String get aiApply => '应用到画布';

  @override
  String get aiDiscard => '放弃';

  @override
  String get aiNoModel => '当前未连接模型。MCP 工具已启用；也可粘贴结构化 JSON 提案进行预览。';

  @override
  String get aiPreviewReady => '预览已就绪，确认后才会写入文档。';

  @override
  String aiInvaldProposal(Object error) {
    return 'AI 请求失败或提案无效：$error';
  }

  @override
  String get aiApplied => 'AI 提案已应用。';

  @override
  String get aiAssistantTitle => '几何绘图助手';

  @override
  String measurementLabel(Object type, Object value) {
    return '$type: $value';
  }

  @override
  String get newTab => '新建文档';

  @override
  String get closeTab => '关闭标签页';

  @override
  String get pageA4 => 'A4';

  @override
  String get rulerOriginReset => '右键重置标尺原点';

  @override
  String get guideHint => '从标尺拖出辅助线';

  @override
  String get loading => '处理中…';

  @override
  String get unsupportedExport => '该导出格式尚未接入经过验证的编码器。';

  @override
  String aboutVersion(Object build, Object version) {
    return '版本 $version（构建 $build）';
  }

  @override
  String aboutBuild(Object commit, Object date) {
    return '构建于 $date · $commit';
  }

  @override
  String get aboutAuthor => '作者：Coloryi-MIAO';

  @override
  String get aboutLicense => 'GNU General Public License v3.0 (GPL-3.0-only)';

  @override
  String get aboutSource => '源代码与问题反馈';

  @override
  String get aboutNotice => '第三方组件与许可证';

  @override
  String get aboutCopyright => 'Copyright (C) 2026 Coloryi-MIAO';

  @override
  String get licenseFull => '查看 GPL-3.0 协议全文';

  @override
  String get close => '关闭';

  @override
  String get unsavedTitle => '未保存的更改';

  @override
  String get tabCloseTitle => '关闭文档';

  @override
  String get fileAssociation => 'MIME: application/x-moesketchpad';

  @override
  String get experimental => '实验性构建';

  @override
  String get settings => '设置';

  @override
  String get font => '字体';

  @override
  String get fontFallbackNotice => 'Web 无法枚举本地系统字体；将使用回退字体栈。';

  @override
  String get fontCuratedNotice => '当前使用内置字体候选；系统字体枚举需要可选原生插件。';

  @override
  String get renderLayers => '渲染层';

  @override
  String get fitView => '适合窗口';

  @override
  String get exportPage => '导出当前视口 SVG';

  @override
  String get visibility => '可见性';

  @override
  String notImplemented(Object feature) {
    return '$feature 尚未实现或未接入本构建。';
  }

  @override
  String previewObjects(int count) {
    return '预览：将新增 $count 个对象';
  }

  @override
  String get copyPrompt => '复制系统提示词';

  @override
  String get promptCopied => '系统提示词已复制。';

  @override
  String get selectObjectFirst => '请先选择一个对象。';

  @override
  String get addAnimationRequirement =>
      '请按住 Shift 选择两个对象：一个点和一个路径（线段、圆、弧、函数或多边形）。';

  @override
  String get noAnimationsHint => '可通过“沿路径运动”按钮创建动点动画。';

  @override
  String get labelEdit => '编辑标注';

  @override
  String get strokeColor => '线条颜色';

  @override
  String get apply => '应用';

  @override
  String get discard => '放弃';

  @override
  String get layer => '图层';

  @override
  String get openPassword => '打开';

  @override
  String get savePassword => '保存';

  @override
  String get objectIdLabel => '对象 ID';

  @override
  String statusHintPageDimension(Object h, Object w) {
    return '$w × $h mm';
  }

  @override
  String get resetOrigin => '重置原点';

  @override
  String get geometrySettings => '几何设定';

  @override
  String get geometryUnit => '长度单位';

  @override
  String get geometryGridSpacing => '基础网格间距';

  @override
  String get geometryGridSpacingHint => '世界坐标单位；网格会随缩放自适应';

  @override
  String get geometryTolerance => '数值容差';

  @override
  String get geometryToleranceHint => '用于约束求解和退化构造判定';

  @override
  String get geometrySnapTolerance => '吸附范围';

  @override
  String get geometryDegenerate => '两点过于接近，无法构造该几何对象。请调整容差或选择不同位置。';
}
