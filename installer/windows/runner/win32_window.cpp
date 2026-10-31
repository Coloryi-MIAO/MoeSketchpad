#include "win32_window.h"

#include <dwmapi.h>
#include <flutter_windows.h>
#include <windowsx.h>

#include "resource.h"

namespace {

/// Window attribute that enables dark mode window decorations.
///
/// Redefined in case the developer's machine has a Windows SDK older than
/// version 10.0.22000.0.
/// See: https://docs.microsoft.com/windows/win32/api/dwmapi/ne-dwmapi-dwmwindowattribute
#ifndef DWMWA_USE_IMMERSIVE_DARK_MODE
#define DWMWA_USE_IMMERSIVE_DARK_MODE 20
#endif

constexpr const wchar_t kWindowClassName[] = L"FLUTTER_RUNNER_WIN32_WINDOW";

/// Registry key for app theme preference.
///
/// A value of 0 indicates apps should use dark mode. A non-zero or missing
/// value indicates apps should use light mode.
constexpr const wchar_t kGetPreferredBrightnessRegKey[] =
  L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize";
constexpr const wchar_t kGetPreferredBrightnessRegValue[] = L"AppsUseLightTheme";

// The number of Win32Window objects that currently exist.
static int g_active_window_count = 0;

using EnableNonClientDpiScaling = BOOL __stdcall(HWND hwnd);

// Scale helper to convert logical scaler values to physical using passed in
// scale factor
int Scale(int source, double scale_factor) {
  return static_cast<int>(source * scale_factor);
}

// Dynamically loads the |EnableNonClientDpiScaling| from the User32 module.
// This API is only needed for PerMonitor V1 awareness mode.
void EnableFullDpiSupportIfAvailable(HWND hwnd) {
  HMODULE user32_module = LoadLibraryA("User32.dll");
  if (!user32_module) {
    return;
  }
  auto enable_non_client_dpi_scaling =
      reinterpret_cast<EnableNonClientDpiScaling*>(
          GetProcAddress(user32_module, "EnableNonClientDpiScaling"));
  if (enable_non_client_dpi_scaling != nullptr) {
    enable_non_client_dpi_scaling(hwnd);
  }
  FreeLibrary(user32_module);
}

}  // namespace

// Manages the Win32Window's window class registration.
class WindowClassRegistrar {
 public:
  ~WindowClassRegistrar() = default;

  // Returns the singleton registrar instance.
  static WindowClassRegistrar* GetInstance() {
    if (!instance_) {
      instance_ = new WindowClassRegistrar();
    }
    return instance_;
  }

  // Returns the name of the window class, registering the class if it hasn't
  // previously been registered.
  const wchar_t* GetWindowClass();

  // Unregisters the window class. Should only be called if there are no
  // instances of the window.
  void UnregisterWindowClass();

 private:
  WindowClassRegistrar() = default;

  static WindowClassRegistrar* instance_;

  bool class_registered_ = false;
};

WindowClassRegistrar* WindowClassRegistrar::instance_ = nullptr;

const wchar_t* WindowClassRegistrar::GetWindowClass() {
  if (!class_registered_) {
    WNDCLASS window_class{};
    window_class.hCursor = LoadCursor(nullptr, IDC_ARROW);
    window_class.lpszClassName = kWindowClassName;
    window_class.style = CS_HREDRAW | CS_VREDRAW;
    window_class.cbClsExtra = 0;
    window_class.cbWndExtra = 0;
    window_class.hInstance = GetModuleHandle(nullptr);
    window_class.hIcon =
        LoadIcon(window_class.hInstance, MAKEINTRESOURCE(IDI_APP_ICON));
    window_class.hbrBackground = 0;
    window_class.lpszMenuName = nullptr;
    window_class.lpfnWndProc = Win32Window::WndProc;
    RegisterClass(&window_class);
    class_registered_ = true;
  }
  return kWindowClassName;
}

void WindowClassRegistrar::UnregisterWindowClass() {
  UnregisterClass(kWindowClassName, nullptr);
  class_registered_ = false;
}

Win32Window::Win32Window() {
  ++g_active_window_count;
}

Win32Window::~Win32Window() {
  --g_active_window_count;
  Destroy();
}

bool Win32Window::Create(const std::wstring& title,
                         const Point& origin,
                         const Size& size,
                         bool frameless) {
  Destroy();

  const wchar_t* window_class =
      WindowClassRegistrar::GetInstance()->GetWindowClass();

  const POINT target_point = {static_cast<LONG>(origin.x),
                              static_cast<LONG>(origin.y)};
  HMONITOR monitor = MonitorFromPoint(target_point, MONITOR_DEFAULTTONEAREST);
  UINT dpi = FlutterDesktopGetDpiForMonitor(monitor);
  double scale_factor = dpi / 96.0;

  // A frameless window drops the caption and thick frame so the Flutter UI can
  // draw its own chrome. WS_THICKFRAME is retained because the desktop window
  // manager uses it for the drop shadow and for snap layouts once the custom
  // hit testing below reports the resize borders.
  const DWORD style = frameless
                          ? (WS_POPUP | WS_THICKFRAME | WS_MINIMIZEBOX |
                             WS_MAXIMIZEBOX | WS_SYSMENU)
                          : WS_OVERLAPPEDWINDOW;

  HWND window = CreateWindow(
      window_class, title.c_str(), style, Scale(origin.x, scale_factor),
      Scale(origin.y, scale_factor), Scale(size.width, scale_factor),
      Scale(size.height, scale_factor), nullptr, nullptr,
      GetModuleHandle(nullptr), this);

  if (!window) {
    return false;
  }

  frameless_ = frameless;
  if (frameless_) {
    ApplyFramelessChrome();
  }

  UpdateTheme(window);

  return OnCreate();
}

bool Win32Window::Show() {
  return ShowWindow(window_handle_, SW_SHOWNORMAL);
}

// static
LRESULT CALLBACK Win32Window::WndProc(HWND const window,
                                      UINT const message,
                                      WPARAM const wparam,
                                      LPARAM const lparam) noexcept {
  if (message == WM_NCCREATE) {
    auto window_struct = reinterpret_cast<CREATESTRUCT*>(lparam);
    SetWindowLongPtr(window, GWLP_USERDATA,
                     reinterpret_cast<LONG_PTR>(window_struct->lpCreateParams));

    auto that = static_cast<Win32Window*>(window_struct->lpCreateParams);
    EnableFullDpiSupportIfAvailable(window);
    that->window_handle_ = window;
  } else if (Win32Window* that = GetThisFromHandle(window)) {
    return that->MessageHandler(window, message, wparam, lparam);
  }

  return DefWindowProc(window, message, wparam, lparam);
}

LRESULT
Win32Window::MessageHandler(HWND hwnd,
                            UINT const message,
                            WPARAM const wparam,
                            LPARAM const lparam) noexcept {
  switch (message) {
    case WM_DESTROY:
      window_handle_ = nullptr;
      Destroy();
      if (quit_on_close_) {
        PostQuitMessage(0);
      }
      return 0;

    case WM_ERASEBKGND:
      // Suppress default gray background; Flutter paints the entire client area.
      return 1;

    case WM_NCHITTEST: {
      if (!frameless_) {
        return DefWindowProc(window_handle_, message, wparam, lparam);
      }
      // Custom hit testing gives the chromeless window real resize borders and
      // a draggable caption strip without a native title bar. Only the reserved
      // strip at the top drags, so Flutter widgets below it keep receiving
      // clicks normally.
      POINT cursor_point;
      cursor_point.x = GET_X_LPARAM(lparam);
      cursor_point.y = GET_Y_LPARAM(lparam);

      RECT rect;
      GetWindowRect(hwnd, &rect);
      const int border = Scale(kResizeBorder, 1.0);

      const bool on_left = cursor_point.x < rect.left + border;
      const bool on_right = cursor_point.x >= rect.right - border;
      const bool on_top = cursor_point.y < rect.top + border;
      const bool on_bottom = cursor_point.y >= rect.bottom - border;

      if (on_top && on_left) return HTTOPLEFT;
      if (on_top && on_right) return HTTOPRIGHT;
      if (on_bottom && on_left) return HTBOTTOMLEFT;
      if (on_bottom && on_right) return HTBOTTOMRIGHT;
      if (on_left) return HTLEFT;
      if (on_right) return HTRIGHT;
      if (on_top) return HTTOP;
      if (on_bottom) return HTBOTTOM;

      // Maximized windows must not be draggable by the caption, otherwise the
      // user can tear the window off its maximized state accidentally.
      if (!IsWindowMaximized()) {
        POINT client_point = cursor_point;
        ScreenToClient(hwnd, &client_point);
        const int caption_height = Scale(kCaptionHeight, 1.0);
        if (client_point.y >= 0 && client_point.y < caption_height &&
            client_point.x >= 0) {
          return HTCAPTION;
        }
      }
      return HTCLIENT;
    }

    case WM_GETMINMAXINFO: {
      if (frameless_) {
        auto* info = reinterpret_cast<MINMAXINFO*>(lparam);
        HMONITOR monitor = MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);
        // FlutterDesktopGetDpiForMonitor is already used for window creation and
        // does not depend on a Windows 10-only SDK macro, unlike GetDpiForWindow.
        const UINT dpi = FlutterDesktopGetDpiForMonitor(monitor);
        const double scale = (dpi == 0 ? 96 : dpi) / 96.0;
        info->ptMinTrackSize.x = Scale(kMinimumWidth, scale);
        info->ptMinTrackSize.y = Scale(kMinimumHeight, scale);

        // A WS_POPUP window is maximized to the whole monitor by default, which
        // would bury the taskbar. Constrain the maximized rect to the monitor's
        // work area so the installer behaves like an ordinary app window.
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
      break;
    }

    case WM_NCCALCSIZE: {
      // Removing the non-client area entirely is what makes the window truly
      // chromeless while keeping the native resize/snap behaviour.
      if (frameless_ && wparam == TRUE) {
        return 0;
      }
      break;
    }

    case WM_DPICHANGED: {
      auto newRectSize = reinterpret_cast<RECT*>(lparam);
      LONG newWidth = newRectSize->right - newRectSize->left;
      LONG newHeight = newRectSize->bottom - newRectSize->top;

      SetWindowPos(hwnd, nullptr, newRectSize->left, newRectSize->top, newWidth,
                   newHeight, SWP_NOZORDER | SWP_NOACTIVATE);

      return 0;
    }
    case WM_SIZE: {
      RECT rect = GetClientArea();
      if (child_content_ != nullptr) {
        // Size and position the child window.
        MoveWindow(child_content_, rect.left, rect.top, rect.right - rect.left,
                   rect.bottom - rect.top, TRUE);
      }
      return 0;
    }

    case WM_ACTIVATE:
      if (child_content_ != nullptr) {
        SetFocus(child_content_);
      }
      return 0;

    case WM_DWMCOLORIZATIONCOLORCHANGED:
      UpdateTheme(hwnd);
      return 0;
  }

  return DefWindowProc(window_handle_, message, wparam, lparam);
}

void Win32Window::Destroy() {
  OnDestroy();

  if (window_handle_) {
    DestroyWindow(window_handle_);
    window_handle_ = nullptr;
  }
  if (g_active_window_count == 0) {
    WindowClassRegistrar::GetInstance()->UnregisterWindowClass();
  }
}

Win32Window* Win32Window::GetThisFromHandle(HWND const window) noexcept {
  return reinterpret_cast<Win32Window*>(
      GetWindowLongPtr(window, GWLP_USERDATA));
}

void Win32Window::SetChildContent(HWND content) {
  child_content_ = content;
  SetParent(content, window_handle_);
  RECT frame = GetClientArea();

  MoveWindow(content, frame.left, frame.top, frame.right - frame.left,
             frame.bottom - frame.top, true);

  SetFocus(child_content_);
}

RECT Win32Window::GetClientArea() {
  RECT frame;
  GetClientRect(window_handle_, &frame);
  return frame;
}

HWND Win32Window::GetHandle() {
  return window_handle_;
}

void Win32Window::SetQuitOnClose(bool quit_on_close) {
  quit_on_close_ = quit_on_close;
}

void Win32Window::ApplyFramelessChrome() {
  if (!window_handle_) {
    return;
  }
  // Extend the DWM frame into the client area so a chromeless window still gets
  // a native drop shadow and rounded corners on Windows 11, and so system snap
  // layouts keep working.
  const MARGINS margins = {1, 1, 1, 1};
  DwmExtendFrameIntoClientArea(window_handle_, &margins);

#ifndef DWMWA_WINDOW_CORNER_PREFERENCE
#define DWMWA_WINDOW_CORNER_PREFERENCE 33
#endif
#ifndef DWMWCP_ROUND
#define DWMWCP_ROUND 2
#endif
  const DWORD corner_preference = DWMWCP_ROUND;
  DwmSetWindowAttribute(window_handle_, DWMWA_WINDOW_CORNER_PREFERENCE,
                        &corner_preference, sizeof(corner_preference));

  // Re-evaluate the frame now that the styles and margins changed.
  SetWindowPos(window_handle_, nullptr, 0, 0, 0, 0,
               SWP_FRAMECHANGED | SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER |
                   SWP_NOACTIVATE);
}

void Win32Window::Minimize() {
  if (window_handle_) {
    ShowWindow(window_handle_, SW_MINIMIZE);
  }
}

void Win32Window::ToggleMaximize() {
  if (!window_handle_) {
    return;
  }
  ShowWindow(window_handle_, IsWindowMaximized() ? SW_RESTORE : SW_MAXIMIZE);
}

bool Win32Window::IsWindowMaximized() const {
  if (!window_handle_) {
    return false;
  }
  WINDOWPLACEMENT placement{};
  placement.length = sizeof(placement);
  if (!GetWindowPlacement(window_handle_, &placement)) {
    return false;
  }
  return placement.showCmd == SW_SHOWMAXIMIZED;
}

void Win32Window::CloseWindow() {
  if (window_handle_) {
    PostMessage(window_handle_, WM_CLOSE, 0, 0);
  }
}

bool Win32Window::OnCreate() {
  // No-op; provided for subclasses.
  return true;
}

void Win32Window::OnDestroy() {
  // No-op; provided for subclasses.
}

void Win32Window::UpdateTheme(HWND const window) {
  DWORD light_mode;
  DWORD light_mode_size = sizeof(light_mode);
  LSTATUS result = RegGetValue(HKEY_CURRENT_USER, kGetPreferredBrightnessRegKey,
                               kGetPreferredBrightnessRegValue,
                               RRF_RT_REG_DWORD, nullptr, &light_mode,
                               &light_mode_size);

  if (result == ERROR_SUCCESS) {
    BOOL enable_dark_mode = light_mode == 0;
    DwmSetWindowAttribute(window, DWMWA_USE_IMMERSIVE_DARK_MODE,
                          &enable_dark_mode, sizeof(enable_dark_mode));
  }
}
