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

  // 安装系统托盘图标（关闭窗口 = 最小化到托盘）
  hwnd_for_tray_ = GetHandle();
  tray_.Install(hwnd_for_tray_);

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
  tray_.Remove(hwnd_for_tray_);
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // 托盘消息与关闭拦截优先于其他处理
  switch (message) {
    case WM_GETMINMAXINFO: {
      // 最小窗口尺寸（逻辑像素，按 DPI 缩放），防止布局挤压变形
      auto info = reinterpret_cast<MINMAXINFO*>(lparam);
      UINT dpi = GetDpiForWindow(hwnd);
      info->ptMinTrackSize.x = MulDiv(520, dpi, 96);
      info->ptMinTrackSize.y = MulDiv(540, dpi, 96);
      return 0;
    }
    case WM_CLOSE:
      // 点击 X：隐藏到系统托盘而不是退出（托盘菜单「退出」才会真正关闭）
      tray_.HideWindowToTray(hwnd);
      return 0;
    case WM_APP + 1:  // 托盘图标回调（见 tray_manager.h）
      if (tray_.HandleNotification(hwnd, wparam, lparam)) {
        return 0;
      }
      break;
    case WM_DESTROY:
      // 正常退出路径（托盘菜单「退出」）：移除托盘
      tray_.Remove(hwnd);
      break;
  }

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
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
