# 萌板 / MoeSketchpad 架构与交付说明

版本：1.0.0+1 · 文档日期：2026-10-24 · 许可证：GPL-3.0-only
状态：**可运行的纵向切片**。标注“已实现”的内容有代码与测试；标注“未实现”
的内容不会被 UI 或文档伪装为可用。

## 1. 总体架构与目录

```text
Flutter App (Web / Windows / macOS)
  CDR 壳层：菜单 / 标准栏 / 上下文属性栏 / 工具箱 / 可折叠泊坞窗
  画布层：背景+页面 / 静态几何 / 覆盖层（三个 RepaintBoundary）
  9 个 BLoC：Theme Locale Tool Selection Canvas Document Measure Animation AI
        │  只调用 moesketchpad_core 类型与 API
        ▼
moesketchpad_core（纯 Dart，不依赖 Flutter/dart:ui/dart:io）
  ├─ 几何对象与文档 schema v2
  ├─ 稳健谓词/交点、R-tree + SpatialIndex
  ├─ 约束求解（阻尼最小二乘，有限差分 Jacobian）
  ├─ 测量、动画求值、函数 AST/采样
  └─ MSP v2 codec（Argon2id + AES-256-GCM + gzip）
        ▲
        ├─ moesp CLI（args；msp 仅兼容入口）─┬─ MCP stdio 白名单服务
        │                  └─ SVG/JSON 导出
        └─ Flutter UI（文件选择、窗口关闭、beforeunload、预览确认）
```

目录：

```text
lib/
  app.dart, main.dart, build_info.dart
  bloc/                       9 个 BLoC + 状态
  ui/canvas/                  CustomPainter 引擎与交互
  ui/widgets/                 工具箱、右侧泊坞窗
  ui/dialogs/                 密码、保存、关于
  ui/workspace_page.dart      CDR 壳层
  platform/                   文件、关闭拦截、窗口的 io/web 条件实现
  l10n/                       ARB 与生成代码
packages/moesketchpad_core/   纯 Dart 几何/MSP 内核
packages/moesketchpad_cli/    moesp 命令与 MCP server
packages/*/test/              内核与 CLI 测试
packaging/windows/            Inno Setup / 开发注册脚本
docs/architecture.md          本文
COPYING / NOTICE / SOURCE-AVAILABILITY.txt
```

`lib/` 与 `moesp` 共用 core，不存在两份几何算法。UI 不直接实现求交、测量或
序列化。

## 2. .moesp v2 格式规范（草案，已实现）

多层防护：**头部是 AES-GCM AAD；所有几何明文都在密文内**。多字节整数大端。

| 偏移 | 大小 | 字段 |
|---:|---:|---|
| 0 | 12 | Magic ASCII `MOESKETCHPAD` |
| 12 | 2 | 版本号 `2` |
| 14 | 2 | flags：bit0 encrypted=1（必须）、bit1 gzip、bit2 加密缩略图 |
| 16 | 1 | KDF：`1` = Argon2id |
| 17 | 4 | Argon2id memory KiB = 19456 |
| 21 | 4 | iterations = 2 |
| 25 | 1 | parallelism = 1 |
| 26 | 1 | salt 长度 = 16 |
| 27 | 16 | 随机 salt |
| 43 | 1 | nonce 长度 = 12 |
| 44 | 12 | AES-GCM nonce |
| 56 | 8 | 明文（压缩前）长度 |
| 64 | 8 | 密文长度 |
| 72 | N | AES-256-GCM 密文（gzip 后 JSON/CBOR 负载） |
| 72+N | 16 | GCM 认证标签 |

- 负载：`format=moesketchpad-document`, `schemaVersion=2`，包含 objects、
  constraints、measurements、animations、layers、view、title、metadata。
  缩略图只放在加密 metadata 内，不在明文头泄露。
- 语言、单位不放进明文 flag，避免泄露文档属性；原需求中的“明文语言/单位”
  有意不采纳。缩略图同理。
- 压缩：gzip，通过 `archive` 的 `maxOutputSize` 限制解压上限（默认 32 MiB），
  且先认证后解压。文件上限默认 64 MiB。
- `MspCodec` API：`encode` / `decode` / `validate` / `migrate` /
  `exportJson` / `importJson`。`validate` 只校验结构与头部，不声称认证；
  `decode` 成功才表示 GCM 认证通过。
- 密钥：用户密码或随机设备密钥 → Argon2id(32B) → AES-256-GCM。桌面和 Web
  用 `flutter_secure_storage` 存储设备密钥；不在文件中嵌入密钥，也不硬编码默认
  密码。设备密钥模式不提供跨设备解密能力。
- 错误处理：错误密码与 GCM 失败使用同一通用信息；不输出密钥或明文片段。
  魔数、版本、KDF、长度在 KDF/分配前校验。写入 CLI 使用临时文件+备份替换。
- MIME：`application/x-moesketchpad`；扩展名 `.moesp`；macOS UTI
  `com.coloryi.moesketchpad.moesp`。

限制：当前 schema 迁移只接受 v1 载荷到 v2 解析；二进制 v1（旧 `MSP1`）未保留
兼容解码器。发布前需要正式规范冻结与 fuzz 测试。

## 3. CLI 规范与安全策略

入口：`moesp`（Dart 包 `packages/moesketchpad_cli`；`msp` 是兼容别名）。

```text
moesp help [command] [--lang zh|en] [--json]
moesp create <primitive> [options] [--file doc.moesp]
moesp constraint <type> <target...> [--value=n] [--file doc.moesp]
moesp label <target> --text=A [--auto] [--offset=x,y] [...]
moesp measure <target> --type=length|arcLength|angle|area|slope [--unit=...]
moesp animate <point> --path=<obj> --t=0..1 --speed=1 --loop|--pingpong --trail=n
moesp calc <expression> [--var=x=1]...
moesp view [--zoom=] [--pan-x=] [--page=] [--landscape] [...]
moesp validate <file.moesp> [--deep]
moesp inspect <file.moesp> [--header] [--full]
moesp convert <input> --to=json|msp --output=<path> [--force]
moesp export <file.moesp> --format=svg|json --output=<path>
moesp mcp-serve [--workspace=<dir>] [--audit-log=<file>]
```

所有命令接受全局 `--lang zh|en`、`--json`、`--file`、`--password-env`（默认
`MSP_PASSWORD`）、`--workspace`、`--audit-log`。密码**只能**通过环境变量提供，
不允许命令行密码，避免进程列表/历史泄露。

创建 primitive：`point, segment, line, ray, circle, arc, triangle, polygon,
conic, function, vector, coordinate, solid`。函数支持 explicit、parametric、
polar、implicit，表达式由纯 Dart AST 解析（无 eval）。

### 三角形简写解析

兼容形式：

```text
--triangle-<angleType>-<a>*<b>*<c>-<hypotenuse>/<rotation>
moesp create --triangle-90-3*4*5-5/180
```

- 正则只接受有限正数，`angleType` 当前只支持 `90`（right）；其他角度类型会
  返回退出码 2，建议使用显式参数。
- `<hypotenuse>` 必须是最大边；排序后满足 `a²+b²=c²`，相对容差 1e-9。
- 简写在进入 args 解析前转换为内部 AST，与规范形式
  `moesp create triangle --type=right --sides=3,4,5 --hypotenuse=5 --rotation=180`
  完全等价（CLI 测试验证 JSON 对象一致）。
- 语义：A=(0,0)，B 在 rotation 方向上，长度=hypotenuse；C 由两腿圆交点求得，
  取定向法线正侧。rotation=180° 时 B 在负 x 轴。无解返回 5，不猜坐标。
- MCP 的 create 工具也使用同一 `PrimitiveFactory`，不做参数拼接。

退出码：`0` 成功、`1` 通用/I/O、`2` 参数、`3` 文件格式、`4` 解密/密码、
`5` 约束无解、`6` 权限/安全拒绝。`--json` 只把机器 JSON 写到 stdout，诊断到
stderr。约束命令在求解未收敛时返回 5，且不写文件。

安全：MCP 文件工具路径 canonicalize（含符号链接）后必须位于 `--workspace`；
只读、只接受 `.moesp`、大小限制；审计日志仅记录时间/工具/成功，不含文档或密码。
AI 面向的 CLI 不执行任意 shell，工具参数按白名单结构化校验。

已实现线-圆切线和圆-圆外切/内切约束。Flutter 桌面/Web 支持
基本几何对象的 GIF/APNG 动画导出；CLI 动图、MP4 未实现。导出当前视口的
SVG 已支持。CLI `constraint` 支持 `tangent-line-circle` 与
`tangent-circle-circle`，后者可加 `--internal`。右侧命令面板只接受受限的安全
子集：help、calc、point/segment/circle 创建、label、measure 及相切约束；
不会启动 shell，也不会执行任意系统命令。所有参数按命令类型白名单检查。

## 4. 几何内核与函数解析

- 对象：point/segment/line/ray/circle/arc/triangle/polygon/conic/function/
  vector/coordinate/solid。世界坐标为有限 double；无边界线、函数、坐标轴在
  空间索引中作为 unbounded 项总是候选。
- 稳健性：`GeometryTolerance`（相对 1e-9、绝对 1e-12，可配）；交点返回
  none/one/two/degenerate，平行、共线、相切、零长度显式处理；圆-线、圆-圆、
  线段/射线域检查。三分点外接圆、点在多边形内。
- 几何设定泊坞窗：长度单位 mm/cm/px、基础网格间距、像素吸附半径、
  数值容差预设；网格间距随缩放自适应，吸附半径按当前 zoom 换算到世界坐标。
  默认基础网格 24 世界单位、吸附半径 9 px、容差相对/绝对值均为 1e-9；
  容差可选 1e-6/1e-9/1e-12。容差被保存于文档 view，约束求解器与线段/
  直线/圆的退化构造检查共用。单位用于新测量的默认输出单位。
- 约束：阻尼最小二乘 + 有限差分 Jacobian + 高斯消元；支持 coincident,
  distance, horizontal, vertical, pointOnLine, pointOnCircle, parallel,
  perpendicular, equalLength, angle, tangentLineCircle, tangentCircleCircle
  （外切或通过 `internalTangency` 选择内切）。报告 converged/iterations/
  residual；不收敛时调用方不得提交。
- 测量：length/arcLength/angle/area/slope/functionValue；单位 unitless、
  cm、mm、px、custom；cm/mm 使用文档 `ViewState.unitScaleMm`（默认 96dpi）。
- 函数：不可变 AST（number/variable/unary/binary/call），长度 4096、节点 2048、
  深度 64 的上限，白名单函数，无 `eval`；显式/参数/极坐标/隐式采样，隐式
  使用 marching squares。采样有上限，避免恶意表达式耗尽内存。
- 动画：t 的纯函数求值；loop/pingpong/once；segment/circle/arc/polygon/
  function 路径；trail 有界。动画不修改源几何，渲染层应用派生位置。

## 5. 无边界画布与空间索引

- 屏幕 = 视口中心 + pan + (world - displayOrigin) × zoom；origin 只改显示参考，
  世界坐标不因移动原点改变。画布无纸张边界、无固定尺寸；旧版文档中的 `page`
  字段仅为兼容存储保留，不参与渲染或限制对象范围。
- 缩放范围 0.002–1e6；自适应网格 1-2-5/倍增序列目标 16–80 px；低 zoom 隐藏
  标签/减少函数采样。
- `RTree<T>`：动态插入、二次分裂、查询、删除；`SpatialIndex` 包装对象，包含
  unbounded 集合，支持视口查询、线/圆/多边形距离命中与框选。当前 UI 在文档
  身份变化时重建索引；10 万级增量索引与 LOD 缓存仍待压力测试。
- 吸附：对象端点/中点/线段/直线/圆投影、线段-线段/线段-圆交点、
  标尺辅助线、网格；容差与吸附半径随画布几何设定生效。
- 无限工作区使用浅灰背景；网格、对象和辅助线覆盖当前视口，不绘制纸张边界。
  标尺四边显示，缩放/平移实时重绘；从标尺拖拽生成辅助线，右键角落重置原点。
- 静态背景、几何、选择/动画覆盖层拆为独立 RepaintBoundary。没有宣称在 10 万
  对象下达到 60fps；需要基准测试后才可声明。

## 6. CDR 风格 UI、无限画布与 BLoC

```text
MaterialApp(locale, theme)
  Scaffold
    Column
      MenuBar: 文件/编辑/视图/布局/对象/效果/文本/工具/窗口/帮助
      StandardBar: 新建/打开/保存/撤销/重做/缩放/单位/网格/贴齐
      ContextBar: 画布原点 或 选中对象属性
      Row
        ToolBox: 选择/形状(矩形椭圆多边形飞出)/缩放(平移)/手绘/文本/填充/
                 透明度/吸管/轮廓 + 点/线段/直线/圆/三角/多边形/函数
        SketchpadCanvas
          四边标尺 + 角落原点手柄
          RepaintBoundary 背景(无限工作区+网格)
          RepaintBoundary 几何与标注/测量
          RepaintBoundary 选择框/辅助线/动画/吸附提示
        RightDock: 对象/属性/测量/动画/AI（可折叠）
      DocumentTabs：多标签、脏标记、关闭拦截
      StatusBar：对象数/世界坐标/原点/缩放/路径
```

- 画布绘制与覆盖层都按画布视口裁剪，不会溢出覆盖工具栏、工具箱或右侧泊坞窗。
- 矩形/椭圆使用按下并拖动到对角点的 CDR 式手势；按住 Shift 约束为正方形/圆。
  三角形、矩形、多边形和椭圆默认无填充；选中对象后可直接设置描边颜色。
- Web 工具条在窄宽度切换为紧凑图标并自动换行。Web 保存先由应用取得安全文件名，
  再触发浏览器下载；浏览器本身不提供原路径覆盖或任意目录写入。
- 表格菜单及其插入网格操作已移除。
- 画布没有页面尺寸、纸张背景或页面边界。旧版文档中的 page 元数据保留用于兼容，
  不影响工作区显示与几何范围。
- “几何设定”泊坞窗默认展开且位于右侧属性窗顶部；调整设定会更新文档 view 并
  标记未保存，`.moesp` 重开时恢复。切换标签页会保存当前 view 并加载目标文档 view。
- CDT 工具箱：未实现的 CDR 工具仍可选择，但点击画布会显示“未接入、不会伪造
  成功”的提示；长按/右键工具组打开飞出菜单。
- BLoC 所有权：DocumentBloc 是文档与 `isDirty` 唯一来源；CanvasBloc 管视口；
  SelectionBloc 只管 ID；MeasureBloc 是派生结果；AnimationBloc 驱动时间；
  AiBloc 只产生预览；Theme/Locale 不影响几何与序列化。撤销栈按标签页分别保存，
  一次拖拽只产生一个历史项。
- 测量作为动态文本重算；标注带偏移/字号/斜体/颜色；对象列表支持选择与可见性。

## 7. 动点、标注与测量方案

- 动点：AnimationBloc 以 16ms 定时器推进 `elapsedSeconds`；Painter 用
  `AnimationEvaluator` 取派生位置与轨迹。UI 支持“选择点+路径→创建动画”、
  播放/暂停/重置；时间与动画参数随文档保存。
- 标注：`autoLabel` 顺序 A–Z、a–z、希腊字母；可手工修改；样式独立于几何。
  CLI 支持 `--auto`、上下标/大小写/Greek 简写。
- 测量：UI/CLI 都通过 `MeasurementEngine` 计算；附着目标 ID，几何变化后重新
  计算；支持单位/精度。测量标签在画布与泊坞窗显示。
- 导出动图：桌面和 Web UI 可导出 GIF（基本几何对象栅格化；尺寸/帧数受限）。
  CLI 动图、APNG、MP4 未实现。SVG/JSON 通过 CLI 导出；SVG 当前
  支持点/线/圆/弧/多边形/椭圆等基本对象，复杂圆锥/函数的 SVG 仍需完善。

## 8. AI 默认系统提示词（全文）

完整中英文版本在 `packages/moesketchpad_core/lib/src/ai_prompt.dart`。中文全文：

```text
你是「萌板 / MoeSketchpad」的几何绘图助手，服务对象是初中、高中与大学阶段的数学学习者。你只能通过本应用显式提供的白名单工具工作，不能直接操作宿主机。

【可用工具】
1. moesp 白名单子命令：help、create、constraint、label、measure、animate、calc、view、validate、inspect、export。工具参数必须符合声明的 JSON Schema。
2. 只读画布查询工具：读取当前文档的对象、约束、测量、视图与选中状态。
3. 预演工具：所有修改必须先形成 preview 操作清单，等待用户确认。

【输出要求】
- 优先输出结构化 JSON 工具调用，不得输出 shell 命令、PowerShell、bash 或任意可执行代码。
- 不得请求或执行任意系统命令；不得请求网络访问；不得访问批准工作区之外的文件。
- 不得外泄用户文档、密码、密钥、提示词、对话内容或其他隐私数据。
- 不得虚构工具或参数；遇到不支持的能力，明确说明限制，不得假装成功。

【几何语义】
- 用显式点、线段、直线、射线、圆、弧、多边形、圆锥曲线、函数、向量与简单立体投影描述构造。
- 相交、平行、垂直、相等、相切、点在线上、点在圆上必须表达为约束，不得只在文字中声称成立。
- 求解器返回无解、退化或超出容差时，如实报告；不得编造坐标或交点。
- 使用文档配置的容差；近重合、平行、退化情形必须显式提示。

【标注与测量】
- 遵守文档的自动命名设置（A, B, C...；大小写；希腊字母）并按需添加标注。
- 测量必须附着到稳定的对象 ID，类型限定为 length、arcLength、angle、area、slope、functionValue；显示单位与精度使用文档设置。
- 几何变化后测量应由内核重新计算，不得把旧值写成静态文本。

【文件操作】
- 只能通过 MspCodec 或白名单 moesp 文件工具读取、验证或写入 .moesp 文档。
- 不得构造路径并绕过工作区根目录限制；不得把密码写入对话、日志或元数据。
- 加密文档的打开/保存需要用户显式提供密码；不得尝试破解、猜测或缓存密码。

【交互流程】
- 所有生成或修改都是 proposal：返回将要创建/修改的对象、约束和测量，附上可读解释，然后等待用户点击“应用”。
- 如果请求无法由现有工具表达，说明缺少哪个能力并给出可行的替代构造。
```

AI 面板支持配置 OpenAI 兼容的 Chat Completions API 地址、模型名和 API Key。
地址/模型使用 shared preferences 保存；API Key 使用 `flutter_secure_storage`
保存，不进入 BLoC state、文档、审计或日志。每次请求只发送用户输入与系统提示词，
请求超时 60 秒，提示词/请求体/响应体均有大小上限；拒绝非本机 HTTP、带 userinfo、
query 或 fragment 的地址，并禁用 HTTP 重定向，避免凭据跟随跳转泄露。
响应只接受 JSON 几何提案，先经几何模型验证并显示预览，用户确认后才写入文档。
当前 API 是 OpenAI-compatible Chat Completions；MCP stdio 仍由 CLI 单独提供，
没有把远程模型伪装成 MCP tool client。

桌面 API Key 由系统凭据存储保护；Web 端由 `flutter_secure_storage` 的 Web 实现加密
存于当前浏览器，仅应在可信设备/来源使用。Web 服务端点必须支持 CORS（含 Authorization
和 JSON 请求头）；不支持 CORS 的供应商需通过自建可信 HTTPS 代理接入。浏览器中的
密钥无法达到服务器端保管等级，勿在共享设备保存。

## 9. 关闭拦截、多语言、字体与主题

- 脏状态：DocumentBloc 在新建/修改后置脏，保存成功清除；关闭标签页弹窗
  “保存/不保存/取消”，保存失败不关闭。窗口关闭在 Windows/macOS 通过
  window_manager `preventClose` + WindowListener 拦截，逐个脏标签询问；
  Web 使用 `beforeunload` 原生提示（浏览器控制文案，可能被抑制）。
- 自动保存/崩溃恢复：已实现已加密文档的临时草稿；仅对本会话已打开或保存且
  当前会话已提供密码的标签生效。桌面写系统临时目录，Web 使用受限
  localStorage；仅保存当前会话内存中的密码派生所需信息，不持久化密码，恢复时要求
  用户重新输入。最近文件使用 SharedPreferences/localStorage 保存。
- i18n：Flutter gen-l10n，`app_zh.arb` / `app_en.arb`，所有主要 UI、错误、
  提示词与 CLI 支持 zh/en。MCP/CLI `--lang`。
- 字体：默认 Microsoft YaHei，平台回退到 Microsoft YaHei UI / PingFang SC /
  Noto Sans CJK SC / sans-serif。设置中提供策展字体列表；**桌面系统字体枚举
  尚未实现**，Web 无法枚举本地字体。不会伪称已枚举。
- 萌化主题：仅影响颜色、圆角、阴影/过渡；不影响几何、精度、文件格式。
  专业模式为 CDR 风格中性紧凑配色。

## 10. 关于界面与 GPL-3.0 合规

关于界面显示：软件名称、版本/构建号、日期/提交（dart-define 可覆盖）、作者
Coloryi-MIAO、GPL-3.0-only + SPDX、源码/问题地址、第三方组件、版权声明、
COPYING/NOTICE 全文入口。

合规清单与当前状态：

- [x] `COPYING` 完整 GPL-3.0 文本
- [x] 所有手写 Dart 源文件带 SPDX（生成文件除外）
- [x] `NOTICE` 第三方组件清单（需发布前按 pubspec.lock 重新生成完整版本）
- [x] 构建产物附 `SOURCE-AVAILABILITY.txt` 与 COPYING/NOTICE（CI 完成）
- [x] 关于界面与许可证入口
- [ ] 图标/字体资产的逐项来源审计（当前图标为项目自绘）
- [ ] 发布前法律/仓库 URL/问题渠道最终确认

## 11. 打包与文件关联

- Web：`flutter build web --release` 通过；`web/manifest.json` PWA；
  `web/_headers` 声明 `application/x-moesketchpad`；favicon/PWA 图标已替换。
  浏览器没有任意文件系统、本地字体枚举、进程或可靠设备密钥；文件保存使用
  浏览器下载（应用先询问 `.moesp` 文件名），打开使用浏览器文件选择器；
  下载目录与覆盖行为由浏览器管理。
- Windows：`flutter build windows --release`；`windows/runner/resources/app_icon.ico`
  已替换；Inno Setup 脚本 `packaging/windows/moesketchpad.iss` 注册
  `.moesp`、MIME、DefaultIcon、打开命令；`register_moesp.ps1` 供开发用。
  EXE 版本资源为语言中性 Unicode，并填充产品名、文件描述、公司、版本、版权和原始文件名。
- Windows/macOS 初始窗口根据主显示器可用尺寸适配；桌面最小窗口约束已降低，
  窄窗口时自动折叠右侧属性泊坞窗。
- macOS：`macos/Runner/Info.plist` 已声明 UTI 与 Document Type；AppIcon 资产
  已替换。Windows 上无法构建/验证 macOS，需 macOS runner + Xcode。
-   CI：`.github/workflows/build.yml` 使用 Flutter 3.47.6 构建 Web/Windows/
  macOS，Windows job 另编译 CLI 并生成 Inno Setup 安装器；macOS 仅在 macOS
  runner 验证。
- 文件关联的启动参数已传入 App；初始密码对话流程已接入桌面文件读取路径。

## 12. 里程碑、测试计划与限制

已完成纵向切片：纯 Dart 内核、MSP v2、moesp CLI、MCP 白名单服务、CDR
壳层、无边界画布与页面/标尺/辅助线、基础点/线/圆/三角形/多边形/函数绘制、
选择与拖拽、撤销、动点播放、标注/测量、AI JSON 预览、脏状态标签关闭/窗口
关闭、密码保存加载、中英/主题、平台配置与合规材料。

测试与验证记录：

- `flutter analyze`：通过。
- `flutter test`：8/8 通过。
- core `dart test`：本轮验证 18 项通过。
- CLI `dart test`：真实子进程（含简写等价与退出码）；本轮曾发现旧的 help
  断言，已改为 `Usage: moesp`，需在最终验证中复跑。
- `flutter build web --release`：通过。
- `flutter build windows --release`：通过（411.9 s）；macOS 未在本机验证。

后续里程碑（Copilot 任务见 `copanddsh.txt`）：

1. 内核加固：更多 fuzz/性质测试、约束完整性与性能基准。
2. Canvas：10 万对象、增量索引、笔迹/文本工具与性能剖析。
3. 文档：系统字体枚举（原生）、设备钥匙串、多窗口。
4. 导出：完整 SVG、PNG/PDF、CLI GIF/APNG、MP4。
5. AI/MCP：更多供应商协议适配、工具 schema 版本化、审计轮转、MCP 客户端传输。
6. 发布：签名/公证、安装器 CI、完整 NOTICE 生成、macOS UTI 实机验证。

平台限制（明确）：Web 无本地字体枚举、任意路径文件系统、进程调用；桌面系统
字体枚举未实现；MP4 与 CLI 动图导出未实现。免密码保存会使用每安装随机
生成并交由 `flutter_secure_storage` 保存的设备密钥，不使用共享固定默认密码；
文件依赖原设备密钥，不保证跨设备打开，Web 端保护能力取决于浏览器本地安全存储。
设备文件关联的 macOS 侧
当前 AI 直接请求依赖端点兼容 Chat Completions；Web 受 CORS/浏览器安全存储限制；
不声称 60fps/全部原始需求功能均已实现。
