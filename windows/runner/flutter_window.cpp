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

LRESULT FlutterWindow::HandleGetMinMaxInfo(HWND hwnd, WPARAM wparam,
                                           LPARAM lparam) const {
  // Let any engine-imposed minimum-size constraints stand, then override the
  // maximized rectangle.
  auto* info = reinterpret_cast<MINMAXINFO*>(lparam);
  HMONITOR monitor = MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);
  MONITORINFO monitor_info{};
  monitor_info.cbSize = sizeof(monitor_info);
  if (GetMonitorInfo(monitor, &monitor_info)) {
    const RECT& work = monitor_info.rcWork;
    const RECT& full = monitor_info.rcMonitor;
    info->ptMaxPosition.x = work.left - full.left;
    info->ptMaxPosition.y = work.top - full.top;
    info->ptMaxSize.x = work.right - work.left;
    info->ptMaxSize.y = work.bottom - work.top;
  }
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
      // WM_GETMINMAXINFO lets the engine set a minimum size; we still need to
      // override the maximized rectangle afterwards (see below).
      if (message != WM_GETMINMAXINFO) {
        return *result;
      }
    }
  }

  // Pin the maximized window to the monitor work area so it does not cover the
  // taskbar. Windows computes the maximized size from the full monitor plus the
  // window frame; with the title bar hidden by Flutter but the resize frame
  // retained, that would make the window overhang the screen edges and overlap
  // the taskbar. Handle it after the engine so plugin-set minimum sizes survive.
  if (message == WM_GETMINMAXINFO) {
    return HandleGetMinMaxInfo(hwnd, wparam, lparam);
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
