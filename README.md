# 萌板 / MoeSketchpad

跨平台动态几何画板，CDR 风格壳层 + 无边界世界坐标 + 自研加密 `.moesp` v2。
目标平台：Flutter Web / Windows / macOS。许可证：**GPL-3.0-only**。

当前是**可运行的纵向切片**，不是全部需求均已完成的商业发布版。已实现与未实现
能力以 [架构与交付说明](docs/architecture.md) 为准，不伪造平台功能。

## 已实现

- CDR 风格菜单/标准栏/上下文属性栏/工具箱飞出菜单/右侧可折叠泊坞窗/文档标签/
  状态栏；紧凑工具栏也显示图标名称、当前工具高亮和操作说明；纯无限画布、
  四边标尺、辅助线、可移动显示原点。
- 点、线段、直线、圆、三角形、多边形、函数（显式/参数/极坐标/隐式）绘制；
  矩形/椭圆按住拖拽绘制，按住 Shift 绘制正方形/圆；封闭图形默认仅描边，
  选中对象后可选择线条颜色；选择、拖拽、框选、删除、撤销/重做、吸附与缩放。
- 画布绘制层按视口裁剪，几何对象不会覆盖顶部栏、工具箱或属性面板；不提供表格菜单。
- 右侧可见“几何设定”：长度单位、基础网格间距、自适应网格、吸附半径与数值
  容差；设置随文档保存并在标签页间隔离，容差接入约束求解与退化构造校验。
- 多标签文档、脏状态、保存/不保存/取消；Windows/macOS 原生关闭拦截，
  Web `beforeunload` 降级提示；Web 打开使用文件选择器，保存先输入 `.moesp`
  文件名再由浏览器下载（保存路径/覆盖行为由浏览器管理）。
- 纯 Dart 内核：文档 schema v2、R-tree、稳健求交、阻尼最小二乘约束求解、
  测量、函数 AST、动画求值。
- `.moesp` v2：Argon2id + AES-256-GCM + gzip，头部作为 AAD；无明文几何。
- `moesp` CLI（兼容 `msp` 可执行别名）：create/constraint/label/measure/animate/calc/view/validate/
  inspect/convert/export/mcp-serve，统一退出码与 JSON 输出。
- 三角简写与规范形式等价：`--triangle-90-3*4*5-5/180`。
- 右侧“命令行”泊坞窗提供结构化安全子集，不执行任意 shell：`moesp help`、
  `moesp calc sqrt(3^2+4^2)`、`moesp create point --x=1 --y=2 --label=A`、
  `moesp create segment --x1=0 --y1=0 --x2=3 --y2=4`、
  `moesp create circle --x=0 --y=0 --radius=5`、`moesp label <id> --text=A`、
  `moesp measure <id>` 和两种相切约束。
- MCP stdio 白名单工具与 workspace 路径限制；AI 支持可配置 OpenAI 兼容
  Chat Completions 地址、模型和 API Key，返回内容经 JSON/几何对象校验后预览，
  必须由用户确认应用；遇到缺少对象必填字段时最多自动请求模型修正一次。
- 中英文 ARB、萌化/专业主题、密码打开保存、关于界面、COPYING/NOTICE/CI
  与 Windows/macOS/Web 平台配置。

## 实现状态与限制

- 桌面端与 Web 最近文件列表及加密自动保存/崩溃恢复已接入；自动保存仅针对本会话已打开或保存且当前会话已提供密码的文档，恢复草稿时需要再次输入密码。
- 桌面/Web GIF 与 APNG 动画导出已实现基本几何对象渲染；MP4 和 CLI 动图导出未实现。
- 线-圆、圆-圆外切/内切约束、线段-线段/线段-圆交点吸附、当前视口 SVG 导出已实现。
- 单独的设备密钥包装格式、系统字体枚举未实现；免密码模式用设备安全存储中的随机密钥参与现有加密，不把固定默认密码写入文件。Web 不支持本地字体枚举。
- 属性面板命令行使用受限安全命令子集，并非在应用内启动完整 CLI 或 shell。
- 可选择使用设备生成的随机密钥免输密码；密钥保存在系统安全存储中，文件通常只能在同一设备打开。Web 端安全性受浏览器存储机制约束。
- 10 万对象 60fps 尚无基准；macOS 打包需在 macOS + Xcode 验证。
- AI 连接支持 OpenAI 兼容的 Chat Completions API；浏览器端点需允许 CORS。
  桌面端 API Key 使用系统安全存储，Web 端使用浏览器加密存储；不要在共享/不可信设备保存密钥。

## 运行

要求 Flutter 3.47.6（本地验证版本）/ Dart 3.13.5；`pubspec.yaml` 给出兼容范围。

```bash
flutter pub get
flutter gen-l10n
flutter analyze
flutter test

# Flutter 桌面/网页
flutter run -d windows
flutter run -d chrome
flutter build web --release
flutter build windows --release

# 内核 / CLI
(cd packages/moesketchpad_core && dart test)
(cd packages/moesketchpad_cli && dart test)
dart run packages/moesketchpad_cli/bin/msp.dart help
dart run packages/moesketchpad_cli/bin/msp.dart calc "sqrt(3^2+4^2)" --json

# 密码只从环境变量读取；不要写在命令行
$env:MSP_PASSWORD='your password' # PowerShell; use an environment variable on other shells
dart run packages/moesketchpad_cli/bin/msp.dart create point --x=1 --y=2 --file doc.moesp
dart run packages/moesketchpad_cli/bin/msp.dart inspect doc.moesp --json
```

构建独立 CLI：

```bash
Push-Location packages/moesketchpad_cli
dart compile exe bin/msp.dart -o moesp.exe
Pop-Location
```

## 打包与文件关联

- Windows 图标已替换；安装器与 `.moesp` 关联：
  `packaging/windows/moesketchpad.iss`（Inno Setup 6+，现代向导样式），安装时注册
  `moesp.exe` 的系统 PATH 和文件关联，卸载时清除 PATH 项；开发注册：
  `packaging/windows/register_moesp.ps1`。EXE 版本资源包含产品/公司/版权/文件名/
  版本说明，使用语言中性 Unicode 字符串表。
- macOS UTI/Document Type：`macos/Runner/Info.plist`；图标资产已替换。
  macOS 构建只能在 macOS runner 上验证。
- Web PWA：`web/manifest.json`；MIME 响应头：`web/_headers`
  （`application/x-moesketchpad`）。文件保存由浏览器下载管理器处理，不提供任意路径写入；
  浏览器也无任意文件系统/进程/设备密钥。
- Web 在窄视口使用紧凑图标和自动换行工具栏，避免右侧按钮只显示一部分。
- CI：`.github/workflows/build.yml`。

## 打开、保存与 AI 配置

### Web 文档

1. 从工具栏选择“打开”，选取本机 `.moesp` 文件，并输入该文档的密码。
2. 保存时先输入文件名（可省略 `.moesp` 扩展名），再输入密码。
3. 浏览器会通过下载管理器保存文件；Web 无法静默覆盖任意路径，下载位置及同名文件处理由浏览器决定。
4. 可选“使用设备生成密钥”免输入密码；该文件依赖当前安装环境中的密钥，不能替代跨设备密码共享。需要跨设备时使用用户密码。

### 动画导出

从“文件 → 导出动画 GIF / 导出动画 APNG”选择格式。导出使用当前画布可见视口，
需要文档中已有动点动画；默认导出 36 帧、每帧 80 ms，当前可渲染基础点、线段、
圆、椭圆、圆弧、多边形和函数曲线。PNG 动画由标准 APNG 块组成，文件扩展名仍为
`.png`，MIME 为 `image/apng`；部分较旧的图片查看器可能只显示首帧。

### AI 服务

在右侧“AI 助手”面板填写并保存：

- **API 地址**：OpenAI 兼容的 Chat Completions API 根地址，例如 `https://api.openai.com/v1`；应用会请求其 `/chat/completions` 路径。
- **模型**：服务提供商要求的确切模型 ID。
- **API Key**：由服务提供商签发。桌面端保存到系统安全存储；Web 端使用浏览器存储，不要在公用设备保存。

Web 服务必须允许当前站点的 CORS 请求；非本机远程 API 必须使用 HTTPS，本机开发服务可用 HTTP。每次只发送用户输入和系统提示词，不发送当前画布文档。AI 结果先以新增对象提案预览，点击“应用到画布”后才写入；若返回对象缺少 `id`、`kind` 或 `points`，应用会请求一次格式修正，仍无效时显示校验错误，不会应用不完整提案。

> API Key 会交给你配置的 API 服务处理。请确认服务商可信，并遵守其隐私与数据保留政策。

## 安全

密码不得提交/写入日志。`.moesp` 加密不替代对恶意文件的大小/结构校验；解析器
有魔数、版本、KDF、长度、解压上限与 GCM 认证检查。AI/MCP 仅白名单工具，路径
限制在 workspace 内，无 shell 拼接。完整说明见
[架构与交付说明](docs/architecture.md) 与 [Copilot 内核任务](copanddsh.txt)。

## 许可证与合规

- `COPYING`：GPL-3.0 全文；源码 SPDX 头为 `GPL-3.0-only`。
- `NOTICE`：第三方组件清单；发布前按 pubspec.lock 重新生成并复核。
- `SOURCE-AVAILABILITY.txt`：二进制源码获取说明。
- 关于界面包含版本、构建信息、作者、GPL 入口、源码/问题链接。
- Copyright (C) 2026 Coloryi-MIAO。

## 验证

```bash
flutter analyze
flutter test
(cd packages/moesketchpad_core && dart test)
(cd packages/moesketchpad_cli && dart test)
flutter build web --release
```

Web 文件选择、下载目录和 API CORS 受运行浏览器及服务端策略影响；发布前应在目标浏览器中分别验证打开/保存与所配置的 AI 服务。
