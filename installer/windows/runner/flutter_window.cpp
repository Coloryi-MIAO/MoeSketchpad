#include "flutter_window.h"

#include <optional>

#include "flutter/generated_plugin_registrant.h"

namespace {

// Method channel the installer's custom window chrome talks to.
constexpr char kWindowChannelName[] = "moesketchpad/installer_window";

// Reports the current maximized state so the Dart chrome can swap its button.
flutter::EncodableValue BuildWindowState(Win32Window* window) {
  flutter::EncodableMap state;
  state[flutter::EncodableValue("maximized")] =
      flutter::EncodableValue(window != nullptr && window->IsWindowMaximized());
  state[flutter::EncodableValue("frameless")] = flutter::EncodableValue(true);
  return flutter::EncodableValue(state);
}

}  // namespace

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

  // Expose the custom window manager to Flutter. Every command is validated
  // here rather than trusting the Dart side, and unknown methods are reported
  // as NotImplemented instead of being silently ignored.
  window_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), kWindowChannelName,
          &flutter::StandardMethodCodec::GetInstance());
  window_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        const std::string& method = call.method_name();
        if (method == "minimize") {
          Minimize();
          result->Success(BuildWindowState(this));
        } else if (method == "toggleMaximize") {
          ToggleMaximize();
          result->Success(BuildWindowState(this));
        } else if (method == "close") {
          result->Success();
          CloseWindow();
        } else if (method == "state") {
          result->Success(BuildWindowState(this));
        } else if (method == "startDrag") {
          // The caption strip already reports HTCAPTION, so the OS performs the
          // drag itself. ReleaseCapture + WM_NCLBUTTONDOWN is the documented
          // fallback for areas Flutter swallows.
          ReleaseCapture();
          SendMessage(GetHandle(), WM_NCLBUTTONDOWN, HTCAPTION, 0);
          result->Success();
        } else {
          result->NotImplemented();
        }
      });

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
  if (window_channel_) {
    window_channel_->SetMethodCallHandler(nullptr);
    window_channel_ = nullptr;
  }
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
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
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;

    case WM_SIZE:
      // Keep the Dart chrome in sync when the user snaps or maximizes the
      // window through the system rather than the in-app buttons.
      if (window_channel_) {
        window_channel_->InvokeMethod(
            "windowStateChanged",
            std::make_unique<flutter::EncodableValue>(BuildWindowState(this)));
      }
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
