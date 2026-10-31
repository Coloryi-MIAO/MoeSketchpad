// SPDX-License-Identifier: GPL-3.0-only
/// Localized copy for the Windows installer.
///
/// The installer ships exactly two languages and has no code-generation step, so
/// every user-visible string lives in this one table instead of generated ARB
/// output. Adding a language means adding a branch here and listing its code in
/// [InstallerStrings.supported].
library;

class InstallerStrings {
  const InstallerStrings(this.languageCode);

  /// Installer version reported in the custom caption bar.
  static const kInstallerVersion = '1.0.0';

  /// Language codes the installer understands, in menu order.
  static const List<String> supported = ['zh', 'en'];

  final String languageCode;

  /// True when the active language is Chinese.
  bool get isChinese => languageCode == 'zh';

  /// Label for this language inside its own picker.
  String get languageName => isChinese ? '简体中文' : 'English';

  // ---------------------------------------------------------------- branding

  String get windowTitle => isChinese ? '萌板安装程序' : 'MoeSketchpad Setup';
  String get brandName => isChinese ? '萌板' : 'MoeSketchpad';
  String get brandLatin => 'MOESKETCHPAD';
  String get brandTagline => isChinese
      ? '为灵感与几何留出的安静空间。'
      : 'A calm, precise space for ideas and geometry.';

  // ----------------------------------------------------------------- welcome

  String get welcomeHeading => isChinese ? '安装萌板' : 'Install MoeSketchpad';
  String get welcomeSubtitle => isChinese
      ? '为当前 Windows 账户安装几何画板与 moesp 命令行工具。'
      : 'Install the geometry workspace and its command-line tools for your '
            'Windows account.';

  String get folderLabel => isChinese ? '安装位置' : 'Installation folder';
  String get folderHint => isChinese ? '选择一个文件夹' : 'Choose a folder';
  String get folderBrowse => isChinese ? '浏览…' : 'Browse…';
  String get folderInvalid => isChinese
      ? '请选择以 MoeSketchpad 结尾的文件夹。'
      : 'Choose a folder whose final name is MoeSketchpad.';
  String get folderPickError =>
      isChinese ? '无法打开文件夹选择对话框。' : 'Could not open the folder picker.';

  String get languageLabel => isChinese ? '界面语言' : 'Interface language';

  String get moespLabel =>
      isChinese ? 'moesp 命令注册方式' : 'moesp command registration';
  String get moespAuto =>
      isChinese ? '自动加入 PATH（推荐）' : 'Add to PATH automatically (recommended)';
  String get moespSkip => isChinese ? '暂不注册 PATH' : 'Do not register PATH';

  String get optionDesktop =>
      isChinese ? '创建桌面快捷方式' : 'Create a desktop shortcut';
  String get optionStartMenu => isChinese ? '添加到开始菜单' : 'Add to Start menu';
  String get optionLaunch =>
      isChinese ? '安装完成后启动萌板' : 'Launch MoeSketchpad when finished';

  String get install => isChinese ? '开始安装' : 'Install';
  String get cancel => isChinese ? '取消' : 'Cancel';
  String get finish => isChinese ? '完成' : 'Finish';
  String get retry => isChinese ? '重试' : 'Try again';
  String get uninstall => isChinese ? '卸载' : 'Uninstall';
  String get cancelUninstall => isChinese ? '取消卸载' : 'Cancel uninstall';

  // --------------------------------------------------------------- uninstalling

  String get uninstallingHeading =>
      isChinese ? '正在卸载萌板' : 'Uninstalling MoeSketchpad';
  String get uninstallHeading => isChinese ? '卸载萌板' : 'Uninstall MoeSketchpad';
  String get uninstallCancel => isChinese ? '取消卸载' : 'Cancel';
  String get uninstallConfirmBody => isChinese
      ? '即将从此电脑移除萌板、moesp 命令、桌面快捷方式、开始菜单快捷方式以及 .moesp 文件关联。\n\n此操作不可撤销。'
      : 'This will remove MoeSketchpad, the moesp command, desktop and Start '
            'menu shortcuts, and the .moesp file association from this PC.\n\n'
            'This action cannot be undone.';
  String get uninstallStatusRemoving =>
      isChinese ? '正在删除安装文件…' : 'Removing installation files…';
  String get uninstallStatusShortcuts =>
      isChinese ? '正在删除快捷方式…' : 'Removing shortcuts…';
  String get uninstallStatusAssociation =>
      isChinese ? '正在删除 .moesp 文件关联…' : 'Removing the .moesp file association…';
  String get uninstallStatusPath =>
      isChinese ? '正在从 PATH 中移除 moesp…' : 'Removing moesp from PATH…';
  String get uninstallStatusRegistry =>
      isChinese ? '正在删除注册表条目…' : 'Removing registry entries…';
  String get uninstallComplete =>
      isChinese ? '卸载完成' : 'Uninstallation complete';
  String get uninstallWindowTitle =>
      isChinese ? '卸载萌板' : 'MoeSketchpad Uninstall';
  String get uninstallCompleteHeading =>
      isChinese ? '已卸载萌板' : 'MoeSketchpad has been uninstalled';
  String get uninstallCompleteBody => isChinese
      ? '萌板已从此电脑上移除。感谢您的使用。'
      : 'MoeSketchpad and its file associations have been removed from this PC. Thank you for using it.';

  // --------------------------------------------------------------- progress

  String get installingHeading =>
      isChinese ? '正在安装' : 'Setting up your workspace';
  String get statusPreparing =>
      isChinese ? '正在准备安装…' : 'Preparing installation…';
  String get statusWaiting =>
      isChinese ? '正在等待萌板关闭…' : 'Waiting for MoeSketchpad to close…';
  String get statusVerifying =>
      isChinese ? '正在校验安装包…' : 'Verifying installation package…';
  String statusInstalling(int done, int total) =>
      isChinese ? '正在写入文件（$done/$total）…' : 'Installing files ($done/$total)…';
  String get statusIntegration =>
      isChinese ? '正在创建快捷方式与文件关联…' : 'Creating shortcuts and file association…';
  String get statusComplete => isChinese ? '安装完成' : 'Installation complete';
  String get statusFailed => isChinese ? '安装失败' : 'Installation failed';
  String get statusReady => isChinese ? '准备就绪' : 'Ready to install';

  /// Percentage label beside the progress ring.
  String percent(int value) => '$value%';

  // -------------------------------------------------------------- completion

  String get completeHeading => isChinese ? '安装完成，可以开始使用' : 'You are all set';
  String get completeBody => isChinese
      ? '萌板与 moesp 命令已就绪。双击任意 .moesp 文档即可打开。'
      : 'MoeSketchpad and the moesp command are ready. Double-click a .moesp '
            'document to open it.';

  String get failedHeading => isChinese ? '安装未能完成' : 'Could not finish setup';

  // ------------------------------------------------------------ error detail

  String get errorRunning => isChinese
      ? '无法确认萌板是否正在运行。'
      : 'Could not check whether MoeSketchpad is running.';
  String get errorCloseFirst => isChinese
      ? '请先关闭萌板，再安装或升级。'
      : 'Close MoeSketchpad before installing or updating.';
  String get errorWaitClose => isChinese
      ? '无法等待正在运行的萌板关闭。'
      : 'Could not wait for the running application to close.';
  String get errorTimeout => isChinese
      ? '萌板在三分钟内没有关闭。'
      : 'MoeSketchpad did not close within three minutes.';
  String get errorPathRead =>
      isChinese ? '无法读取当前用户的 PATH。' : 'Could not read the current user PATH.';
  String get errorShortcutFolders => isChinese
      ? '无法定位当前用户的快捷方式目录。'
      : 'Could not locate the current user shortcut folders.';
  String errorCommandFailed(int exitCode) => isChinese
      ? '命令执行失败（退出码 $exitCode）。'
      : 'A command failed with exit code $exitCode.';

  // ------------------------------------------------------------------ footer

  String get licenseLabel => 'GPL-3.0-only';
  String get authorLabel => 'Coloryi-MIAO';
  String get versionLabel => isChinese ? '版本' : 'Version';
}
