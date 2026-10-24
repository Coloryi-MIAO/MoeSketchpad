# 萌板 / MoeSketchpad

跨平台动态几何画板，CDR 风格壳层 + 无边界世界坐标 + 自研加密 `.msp` v2。
目标平台：Flutter Web / Windows / macOS。许可证：**GPL-3.0-only**。

当前是**可运行的纵向切片**，不是全部需求均已完成的商业发布版。已实现与未实现
能力以 [架构与交付说明](docs/architecture.md) 为准，不伪造平台功能。

## 已实现

- CDR 风格菜单/标准栏/上下文属性栏/工具箱飞出菜单/右侧可折叠泊坞窗/文档标签/
  状态栏；纯无限画布、四边标尺、辅助线、可移动显示原点。
- 点、线段、直线、圆、三角形、多边形、函数（显式/参数/极坐标/隐式）绘制；
  选择、拖拽、框选、删除、撤销/重做、网格与对象吸附、滚轮缩放。
- 右侧可见“几何设定”：长度单位、基础网格间距、自适应网格、吸附半径与数值
  容差；设置随文档保存并在标签页间隔离，容差接入约束求解与退化构造校验。
- 多标签文档、脏状态、保存/不保存/取消；Windows/macOS 原生关闭拦截，
  Web `beforeunload` 降级提示。
- 纯 Dart 内核：文档 schema v2、R-tree、稳健求交、阻尼最小二乘约束求解、
  测量、函数 AST、动画求值。
- `.msp` v2：Argon2id + AES-256-GCM + gzip，头部作为 AAD；无明文几何。
- `msp` CLI：create/constraint/label/measure/animate/calc/view/validate/
  inspect/convert/export/mcp-serve，统一退出码与 JSON 输出。
- 三角简写与规范形式等价：`--triangle-90-3*4*5-5/180`。
- MCP stdio 白名单工具与 workspace 路径限制；AI JSON 提案预览/应用；
  AI 面板不内置网络模型。
- 中英文 ARB、萌化/专业主题、密码打开保存、关于界面、COPYING/NOTICE/CI
  与 Windows/macOS/Web 平台配置。

## 明确未实现 / 限制

- 设备钥匙串/设备密钥（仅密码）；自动保存与崩溃恢复；系统字体枚举。
- GIF/APNG/MP4 导出；持久化“最近文件”。
- 相切约束、交点吸附、部分 CDR 工具（矩形/椭圆/手绘/文本/填充等按钮存在但
  会明确提示未接入）；系统字体枚举在 Web 不可用。
- 10 万对象 60fps 尚无基准；macOS 打包需在 macOS + Xcode 验证。
- 内置 AI 无模型连接；通过 MCP/JSON 提案协作。

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
export MSP_PASSWORD='your password'
dart run packages/moesketchpad_cli/bin/msp.dart create point --x=1 --y=2 --file doc.msp
dart run packages/moesketchpad_cli/bin/msp.dart inspect doc.msp --json
```

构建独立 CLI：

```bash
(cd packages/moesketchpad_cli && dart compile exe bin/msp.dart -o msp)
```

## 打包与文件关联

- Windows 图标已替换；安装器与 `.msp` 关联：
  `packaging/windows/moesketchpad.iss`（Inno Setup 6+），开发注册：
  `packaging/windows/register_msp.ps1`。
- macOS UTI/Document Type：`macos/Runner/Info.plist`；图标资产已替换。
  macOS 构建只能在 macOS runner 上验证。
- Web PWA：`web/manifest.json`；MIME 响应头：`web/_headers`
  （`application/x-moesketchpad`）。浏览器无任意文件系统/进程/设备密钥。
- CI：`.github/workflows/build.yml`。

## 安全

密码不得提交/写入日志。`.msp` 加密不替代对恶意文件的大小/结构校验；解析器
有魔数、版本、KDF、长度、解压上限与 GCM 认证检查。AI/MCP 仅白名单工具，路径
限制在 workspace 内，无 shell 拼接。完整说明见
[架构与交付说明](docs/architecture.md) 与 [Copilot 内核任务](copanddsh.txt)。

## 许可证与合规

- `COPYING`：GPL-3.0 全文；源码 SPDX 头为 `GPL-3.0-only`。
- `NOTICE`：第三方组件清单；发布前按 pubspec.lock 重新生成并复核。
- `SOURCE-AVAILABILITY.txt`：二进制源码获取说明。
- 关于界面包含版本、构建信息、作者、GPL 入口、源码/问题链接。
- Copyright (C) 2026 Coloryi-MIAO。
