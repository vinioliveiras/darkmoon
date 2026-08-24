#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  // Created small and centered on the primary monitor — just roomy enough
  // for the launch splash's centered card (see widgets/splash_screen.dart's
  // _cardWidth/_cardHeight, 720x420) with margin for the title bar/borders
  // Win32Window::Create's width/height includes — rather than the eventual
  // maximized size, so the real desktop is visible around the splash card
  // like Lightroom's own launch screen. FlutterWindow's "darkmoon/window"
  // channel maximizes it once main.dart's splash timer finishes.
  const int splash_window_width = 800;
  const int splash_window_height = 520;
  const int screen_width = GetSystemMetrics(SM_CXSCREEN);
  const int screen_height = GetSystemMetrics(SM_CYSCREEN);
  Win32Window::Point origin(
      static_cast<unsigned int>(
          std::max(0, (screen_width - splash_window_width) / 2)),
      static_cast<unsigned int>(
          std::max(0, (screen_height - splash_window_height) / 2)));
  Win32Window::Size size(splash_window_width, splash_window_height);
  if (!window.Create(L"darkmoon", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
