#ifndef RUNNER_WIN32_WINDOW_H_
#define RUNNER_WIN32_WINDOW_H_

#include <windows.h>

#include <functional>
#include <memory>
#include <string>

// A class abstraction for a high DPI-aware Win32 Window. Intended to be
// inherited from by classes that wish to specialize with custom
// rendering and input handling
class Win32Window {
 public:
  struct Point {
    unsigned int x;
    unsigned int y;
    Point(unsigned int x, unsigned int y) : x(x), y(y) {}
  };

  struct Size {
    unsigned int width;
    unsigned int height;
    Size(unsigned int width, unsigned int height)
        : width(width), height(height) {}
  };

  Win32Window();
  virtual ~Win32Window();

  // Creates a win32 window with |title| that is positioned and sized using
  // |origin| and |size|. New windows are created on the default monitor. Window
  // sizes are specified to the OS in physical pixels, hence to ensure a
  // consistent size this function will scale the inputted width and height as
  // as appropriate for the default monitor. The window is invisible until
  // |Show| is called. Returns true if the window was created successfully.
  //
  // The window starts frameless (see SetFrameless) with |corner_radius|
  // (logical pixels, scaled the same way |size| is) rounding its actual
  // window shape — 0 (the default) leaves it a plain rectangle.
  bool Create(const std::wstring& title, const Point& origin, const Size& size,
              int corner_radius = 0);

  // Show the current window. Returns true if the window was successfully shown.
  bool Show();

  // Release OS resources associated with window.
  void Destroy();

  // Inserts |content| into the window tree.
  void SetChildContent(HWND content);

  // Returns the backing Window handle to enable clients to set icon and other
  // window properties. Returns nullptr if the window has been destroyed.
  HWND GetHandle();

  // If true, closing this window will quit the application.
  void SetQuitOnClose(bool quit_on_close);

  // Return a RECT representing the bounds of the current client area.
  RECT GetClientArea();

  // Adds or removes the title bar, system menu, resize border and min/
  // max/close buttons, *and* (via WM_NCCALCSIZE in MessageHandler) the
  // thin sizing-border DWM still reserves around a top-level window even
  // once WS_CAPTION/WS_THICKFRAME are gone — without also handling
  // WM_NCCALCSIZE, that border survives and shows up as a stray 1px edge
  // around the splash. Used to show the launch splash (see
  // widgets/splash_screen.dart, which draws its own card/shadow) without a
  // mismatched native frame wrapped around it, then restored once the
  // splash is dismissed — see flutter_window.cpp's "darkmoon/window"
  // channel.
  //
  // While going frameless, |corner_radius| (physical pixels, 0 for a
  // plain rectangle) also clips the actual window shape via SetWindowRgn
  // — the window's own visible bounds become the rounded card
  // widgets/splash_screen.dart draws, rather than a plain rectangle the
  // card floats inside of. Going framed again always clears the region
  // back to a plain rectangle, regardless of |corner_radius|.
  void SetFrameless(bool frameless, int corner_radius = 0);

 protected:
  // Processes and route salient window messages for mouse handling,
  // size change and DPI. Delegates handling of these to member overloads that
  // inheriting classes can handle.
  virtual LRESULT MessageHandler(HWND window,
                                 UINT const message,
                                 WPARAM const wparam,
                                 LPARAM const lparam) noexcept;

  // Called when CreateAndShow is called, allowing subclass window-related
  // setup. Subclasses should return false if setup fails.
  virtual bool OnCreate();

  // Called when Destroy is called.
  virtual void OnDestroy();

 private:
  friend class WindowClassRegistrar;

  // OS callback called by message pump. Handles the WM_NCCREATE message which
  // is passed when the non-client area is being created and enables automatic
  // non-client DPI scaling so that the non-client area automatically
  // responds to changes in DPI. All other messages are handled by
  // MessageHandler.
  static LRESULT CALLBACK WndProc(HWND const window,
                                  UINT const message,
                                  WPARAM const wparam,
                                  LPARAM const lparam) noexcept;

  // Retrieves a class instance pointer for |window|
  static Win32Window* GetThisFromHandle(HWND const window) noexcept;

  // Update the window frame's theme to match the system theme.
  static void UpdateTheme(HWND const window);

  bool quit_on_close_ = false;

  // True between a SetFrameless(true) and the matching SetFrameless(false)
  // — read by MessageHandler's WM_NCCALCSIZE case, which needs to know
  // whether to claim the whole window as client area (frameless) or fall
  // back to DefWindowProc's normal caption/border sizing (framed).
  bool frameless_ = false;

  // window handle for top level window.
  HWND window_handle_ = nullptr;

  // window handle for hosted content.
  HWND child_content_ = nullptr;
};

#endif  // RUNNER_WIN32_WINDOW_H_
