# 萌板 / MoeSketchpad

跨平台动态几何画板的 Flutter 起步实现。当前包含可运行的画板 UI（点、
线段、平移、缩放、网格、A4 页面）、共享 Dart 几何模型、安全表达式解析器、
Argon2id + AES-256-GCM `.msp` 编解码，以及 `msp calc/create triangle/validate`
CLI 子集。

## 运行

```powershell
flutter pub get
flutter run -d windows
flutter test
dart run bin/msp.dart help
dart run bin/msp.dart calc "sqrt(3^2 + 4^2)" --json
dart run bin/msp.dart create triangle --type=right --sides=3,4,5 --hypotenuse=5 --rotation=180 --json
dart run bin/msp.dart create --triangle-90-3*4*5-5/180
```

CLI 目前从 Dart 入口运行；构建独立 `msp.exe`/可执行文件及其他子命令属于后续工作。
Windows 可本地构建。macOS 发布必须在 macOS/Xcode runner 上完成。Web 上本地字体枚举、
任意文件系统访问、进程调用和设备密钥存储不可用，须经浏览器文件选择器和密码降级。

架构、`.msp` v1 二进制草案、安全限制、CLI 规则、AI system prompt、平台降级和里程碑见
[架构与交付计划](docs/architecture.md)。

## 状态说明

这是可验证的基础版本，不是已完成全部产品需求的发布版本。压缩位暂不支持；CLI、
国际化、R-tree、约束求解、MCP/AI、原生文件关联、窗口关闭拦截、文件保存 UI、
动图导出和完整 GPL 发布材料尚未完成。请勿将其描述成已支持功能。

许可证目标为 `GPL-3.0-only`。在公开发布前，必须补齐官方完整 `COPYING`、SPDX 头、
第三方 NOTICE、图标来源与二进制源码获取说明。
