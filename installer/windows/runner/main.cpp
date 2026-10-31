#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <algorithm>
#include <string>
#include <vector>

#include "flutter_window.h"
#include "utils.h"

namespace {

// Named mutex that keeps a single installer process alive at a time. Only the
// installer claims it; the moesp CLI intentionally stays multi-instance.
constexpr const wchar_t kInstallerMutex[] =
    L"Local\\MoeSketchpad.Installer.SingleInstance";

// A private message carrying the "activate yourself" request to the instance
// that already owns the mutex.
constexpr UINT kActivateMessage = WM_APP + 1;

// Hidden helper window class the running installer listens on, so a second
// launch can raise it without spawning any extra visible window.
constexpr const wchar_t kActivateWindowClass[] =
    L"MoeSketchpadInstallerActivate";
constexpr const wchar_t kActivateWindowTitle[] =
    L"MoeSketchpad Installer Activate";

// Frameless window geometry. The Dart chrome draws the title bar, so the window
// starts a little smaller than the app window.
constexpr int kInitialWidth = 720;
constexpr int kInitialHeight = 760;

// The message-only window that receives activation requests.
HWND g_activate_window = nullptr;

// The visible installer window, raised when a redundant launch occurs.
HWND g_flutter_window = nullptr;

LRESULT CALLBACK ActivateWndProc(HWND window, UINT message, WPARAM wparam,
                                 LPARAM lparam) noexcept {
  if (message == kActivateMessage) {
    if (g_flutter_window != nullptr) {
      if (IsIconic(g_flutter_window)) {
        ShowWindow(g_flutter_window, SW_RESTORE);
      }
      SetForegroundWindow(g_flutter_window);
    }
    return 0;
  }
  return DefWindowProc(window, message, wparam, lparam);
}

// Registers the activation window class once per process.
void RegisterActivateClass() {
  static bool registered = false;
  if (registered) {
    return;
  }
  WNDCLASS window_class{};
  window_class.lpfnWndProc = ActivateWndProc;
  window_class.hInstance = GetModuleHandle(nullptr);
  window_class.lpszClassName = kActivateWindowClass;
  RegisterClass(&window_class);
  registered = true;
}

// Creates the hidden window used to receive activation requests.
void CreateActivateWindow() {
  RegisterActivateClass();
  g_activate_window =
      CreateWindowEx(0, kActivateWindowClass, kActivateWindowTitle, 0, 0, 0, 0,
                     0, HWND_MESSAGE, nullptr, GetModuleHandle(nullptr),
                     nullptr);
}

// Asks the already-running installer to come to the foreground.
void RequestActivation() {
  HWND existing =
      FindWindowW(kActivateWindowClass, kActivateWindowTitle);
  if (existing != nullptr) {
    PostMessage(existing, kActivateMessage, 0, 0);
  }
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // The installer is intentionally multi-instance: a second launch (e.g. after
  // a first install completed) must always spawn a fresh, independent window
  // rather than raising an old one and exiting. Only the moesketchpad core app
  // enforces single-instance behavior. An explicit --uninstall must also always
  // run on its own so the ARP entry can be removed even while an installer
  // window is open.
  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();
  const bool is_uninstall = std::find_if(
      command_line_arguments.begin(), command_line_arguments.end(),
      [](const std::string& a) { return a == "--uninstall"; }) !=
      command_line_arguments.end();

  // No single-instance mutex for the installer itself; launches are always
  // independent (a second installer window must be allowed after a first
  // install completes, and an --uninstall from ARP must always run).
  HANDLE instance_mutex = nullptr;

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  const wchar_t* window_title = is_uninstall
      ? L"MoeSketchpad Uninstall"
      : L"MoeSketchpad Setup";

  FlutterWindow window(project);
  Win32Window::Point origin(0, 0);
  Win32Window::Size size(kInitialWidth, kInitialHeight);
  // The installer runs chromeless: the Dart chrome supplies the title bar.
  if (!window.Create(window_title, origin, size, /*frameless=*/true)) {
    if (instance_mutex != nullptr) {
      ::CloseHandle(instance_mutex);
    }
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  // Raise the (possibly minimized) installer when a redundant launch occurs.
  g_flutter_window = window.GetHandle();
  CreateActivateWindow();

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  if (g_activate_window != nullptr) {
    DestroyWindow(g_activate_window);
    g_activate_window = nullptr;
  }
  if (instance_mutex != nullptr) {
    ::ReleaseMutex(instance_mutex);
    ::CloseHandle(instance_mutex);
  }
  return EXIT_SUCCESS;
}
