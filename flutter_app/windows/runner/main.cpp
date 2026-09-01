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
  // Created small, centered on the primary monitor, and frameless with
  // rounded corners (see Win32Window::Create's SetFrameless(true, ...)
  // call) — sized and rounded to exactly match the launch splash's own
  // card (see widgets/splash_screen.dart's _cardWidth/_cardHeight/
  // BorderRadius.circular(10)), so the window's own visible bounds *are*
  // the card, with the real desktop showing through everywhere else —
  // rather than the eventual maximized size, like Meridian's own launch
  // screen. FlutterWindow's "darkmoon/window" channel restores the normal
  // rectangular frame and maximizes it once main.dart's splash timer
  // finishes.
  const int splash_window_width = 720;
  const int splash_window_height = 420;
  const int splash_corner_radius = 10;
  const int screen_width = GetSystemMetrics(SM_CXSCREEN);
  const int screen_height = GetSystemMetrics(SM_CYSCREEN);
  Win32Window::Point origin(
      static_cast<unsigned int>(
          std::max(0, (screen_width - splash_window_width) / 2)),
      static_cast<unsigned int>(
          std::max(0, (screen_height - splash_window_height) / 2)));
  Win32Window::Size size(splash_window_width, splash_window_height);
  if (!window.Create(L"darkmoon", origin, size, splash_corner_radius)) {
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
