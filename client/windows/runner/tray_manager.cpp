#include "tray_manager.h"

#include <shellapi.h>

#include "resource.h"

namespace {
// 托盘回调消息（WM_APP 区段，避免与系统消息冲突）
constexpr UINT kTrayIconMessage = WM_APP + 1;
// 菜单项 ID
constexpr int kMenuRestore = 2001;
constexpr int kMenuQuit = 2003;

HICON LoadAppIcon() {
  // 按小图标尺寸加载，保证托盘清晰
  const int size = GetSystemMetrics(SM_CXSMICON);
  return static_cast<HICON>(LoadImage(GetModuleHandle(nullptr),
                                      MAKEINTRESOURCEW(IDI_APP_ICON),
                                      IMAGE_ICON, size, size, LR_DEFAULTCOLOR));
}
}  // namespace

bool TrayManager::Install(HWND hwnd) {
  if (installed_) {
    return true;
  }
  nid_.cbSize = sizeof(NOTIFYICONDATAW);
  nid_.hWnd = hwnd;
  nid_.uID = 1;
  nid_.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP;
  nid_.uCallbackMessage = kTrayIconMessage;
  nid_.hIcon = LoadAppIcon();
  wcscpy_s(nid_.szTip, L"Chord - 点击图标恢复窗口");
  installed_ = Shell_NotifyIconW(NIM_ADD, &nid_) == TRUE;
  return installed_;
}

void TrayManager::Remove(HWND hwnd) {
  if (!installed_) {
    return;
  }
  nid_.uFlags = 0;
  Shell_NotifyIconW(NIM_DELETE, &nid_);
  if (nid_.hIcon) {
    DestroyIcon(nid_.hIcon);
    nid_.hIcon = nullptr;
  }
  installed_ = false;
}

bool TrayManager::HandleNotification(HWND hwnd, WPARAM wparam, LPARAM lparam) {
  if (wparam != 1) {
    return false;  // 不是我们的托盘图标
  }
  switch (LOWORD(lparam)) {
    case WM_LBUTTONUP:
    case WM_LBUTTONDBLCLK:
      RestoreWindow(hwnd);
      return true;
    case WM_RBUTTONUP:
      ShowContextMenu(hwnd);
      return true;
    default:
      return false;
  }
}

void TrayManager::HideWindowToTray(HWND hwnd) {
  if (!installed_) {
    Install(hwnd);
  }
  ShowWindow(hwnd, SW_HIDE);
  if (!balloon_shown_) {
    balloon_shown_ = true;
    NOTIFYICONDATAW nid = nid_;
    nid.uFlags = NIF_INFO;
    nid.uTimeout = 3000;
    wcscpy_s(nid.szInfoTitle, L"Chord");
    wcscpy_s(nid.szInfo, L"已最小化到系统托盘，点击图标恢复窗口。消息仍会实时接收。");
    Shell_NotifyIconW(NIM_MODIFY, &nid);
  }
}

void TrayManager::RestoreWindow(HWND hwnd) {
  ShowWindow(hwnd, SW_SHOW);
  if (IsIconic(hwnd)) {
    ShowWindow(hwnd, SW_RESTORE);
  }
  SetForegroundWindow(hwnd);
}

void TrayManager::ShowContextMenu(HWND hwnd) {
  HMENU menu = CreatePopupMenu();
  AppendMenuW(menu, MF_STRING, kMenuRestore, L"打开 Chord");
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(menu, MF_STRING, kMenuQuit, L"退出");

  POINT pt;
  GetCursorPos(&pt);
  // TrackPopupMenu 前必须 SetForegroundWindow，否则菜单不会随点击消失
  SetForegroundWindow(hwnd);
  const int cmd = TrackPopupMenu(menu, TPM_RETURNCMD | TPM_NONOTIFY | TPM_RIGHTBUTTON,
                                 pt.x, pt.y, 0, hwnd, nullptr);
  PostMessageW(hwnd, WM_NULL, 0, 0);
  DestroyMenu(menu);

  switch (cmd) {
    case kMenuRestore:
      RestoreWindow(hwnd);
      break;
    case kMenuQuit:
      // 真正退出：移除托盘图标并销毁窗口
      Remove(hwnd);
      DestroyWindow(hwnd);
      break;
    default:
      break;
  }
}
