// SPDX-License-Identifier: GPL-3.0-only
#include "flutter_window.h"

#include <optional>

#include "flutter/generated_plugin_registrant.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT FlutterWindow::HandleGetMinMaxInfo(HWND hwnd, LPARAM lparam) const {
  // Windows sizes a maximized window to the whole monitor, so the window would
  // cover the taskbar. The app hides its title bar through Flutter
  // (TitleBarStyle.hidden) but keeps the WS_OVERLAPPEDWINDOW resize frame, so a
  // maximized window also overhangs the screen by the frame on every side.
  //
  // ptMaxSize is measured in frame-inclusive window coordinates while the work
  // area is in screen coordinates, so the frame must be subtracted from the
  // requested client size to land the window exactly on the work area.
  auto* info = reinterpret_cast<MINMAXINFO*>(lparam);
  HMONITOR monitor = MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);
  MONITORINFO monitor_info{};
  monitor_info.cbSize = sizeof(monitor_info);
  if (!GetMonitorInfo(monitor, &monitor_info)) {
    return 0;
  }

  const RECT& work = monitor_info.rcWork;
  const RECT& full = monitor_info.rcMonitor;

  // ptMaxSize describes the maximized *client* area; Windows then adds this
  // window's non-client frame around it. Requesting the bare work-area size is
  // therefore what lands the frame-inclusive window rect exactly on the work
  // area, leaving the taskbar uncovered.
  info->ptMaxPosition.x = work.left - full.left;
  info->ptMaxPosition.y = work.top - full.top;
  info->ptMaxSize.x = work.right - work.left;
  info->ptMaxSize.y = work.bottom - work.top;
  return 0;
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      // The engine and its plugins (notably window_manager, which sets minimum
      // and maximum track sizes) consumed the message. WM_GETMINMAXINFO still
      // needs the maximized rectangle pinned to the work area afterwards.
      if (message != WM_GETMINMAXINFO) {
        return *result;
      }
    }
  }

  if (message == WM_GETMINMAXINFO) {
    return HandleGetMinMaxInfo(hwnd, lparam);
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
