#include "tray_manager.h"

#include <shellapi.h>

#include <vector>

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

// GDI 绘制的 32bpp 位图 alpha 全为 0（渲染出来是全透明），这里统一置为不透明。
void ForceOpaque(HBITMAP bmp, int size) {
  BITMAPINFO bi{};
  bi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  bi.bmiHeader.biWidth = size;
  bi.bmiHeader.biHeight = -size;  // top-down
  bi.bmiHeader.biPlanes = 1;
  bi.bmiHeader.biBitCount = 32;
  bi.bmiHeader.biCompression = BI_RGB;
  std::vector<uint8_t> px(static_cast<size_t>(size) * size * 4);
  HDC screen = GetDC(nullptr);
  GetDIBits(screen, bmp, 0, size, px.data(), &bi, DIB_RGB_COLORS);
  for (int i = 0; i < size * size; ++i) {
    px[static_cast<size_t>(i) * 4 + 3] = 255;
  }
  SetDIBits(screen, bmp, 0, size, px.data(), &bi, DIB_RGB_COLORS);
  ReleaseDC(nullptr, screen);
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

void TrayManager::SetBadge(int count) {
  if (count < 0) count = 0;
  if (count == badge_) return;
  badge_ = count;
  if (!installed_) return;  // 尚未安装托盘图标，Install() 时会用最新 badge_
  UpdateIcon();
}

void TrayManager::UpdateIcon() {
  HICON fresh = badge_ > 0 ? MakeBadgedIcon(badge_) : LoadAppIcon();
  if (!fresh) return;

  HICON old = nid_.hIcon;
  nid_.hIcon = fresh;
  nid_.uFlags = NIF_ICON | NIF_TIP;
  if (badge_ > 0) {
    swprintf_s(nid_.szTip, L"Chord - %d 条未读，点击恢复窗口", badge_);
  } else {
    wcscpy_s(nid_.szTip, L"Chord - 点击图标恢复窗口");
  }
  Shell_NotifyIconW(NIM_MODIFY, &nid_);
  if (old) DestroyIcon(old);
}

// 在应用图标右上角叠加红色未读数字（>9 显示 9+）。
HICON TrayManager::MakeBadgedIcon(int count) const {
  const int size = GetSystemMetrics(SM_CXSMICON);
  HICON base = LoadAppIcon();
  if (!base) return nullptr;

  HDC screen = GetDC(nullptr);
  HDC dc = CreateCompatibleDC(screen);
  HBITMAP bmp = CreateCompatibleBitmap(screen, size, size);
  HBITMAP old_bmp = static_cast<HBITMAP>(SelectObject(dc, bmp));

  RECT full{0, 0, size, size};
  HBRUSH bg = CreateSolidBrush(RGB(30, 31, 34));  // 与托盘底色接近
  FillRect(dc, &full, bg);
  DeleteObject(bg);
  DrawIconEx(dc, 0, 0, base, size, size, 0, nullptr, DI_NORMAL);

  // 红点
  const int d = size * 5 / 8;
  const int x = size - d, y = 0;
  HBRUSH red = CreateSolidBrush(RGB(237, 66, 69));
  HPEN pen = CreatePen(PS_SOLID, 1, RGB(30, 31, 34));
  HGDIOBJ old_brush = SelectObject(dc, red);
  HGDIOBJ old_pen = SelectObject(dc, pen);
  Ellipse(dc, x, y, x + d, y + d);
  SelectObject(dc, old_brush);
  SelectObject(dc, old_pen);
  DeleteObject(red);
  DeleteObject(pen);

  // 数字
  wchar_t txt[8];
  if (count > 9) {
    wcscpy_s(txt, L"9+");
  } else {
    swprintf_s(txt, L"%d", count);
  }
  HFONT font = CreateFontW(-d * 3 / 5, 0, 0, 0, FW_BOLD, FALSE, FALSE, FALSE,
                           DEFAULT_CHARSET, OUT_DEFAULT_PRECIS,
                           CLIP_DEFAULT_PRECIS, ANTIALIASED_QUALITY,
                           DEFAULT_PITCH, L"Segoe UI");
  HGDIOBJ old_font = SelectObject(dc, font);
  SetBkMode(dc, TRANSPARENT);
  SetTextColor(dc, RGB(255, 255, 255));
  RECT tr{x, y, x + d, y + d};
  DrawTextW(dc, txt, -1, &tr, DT_CENTER | DT_VCENTER | DT_SINGLELINE);
  SelectObject(dc, old_font);
  DeleteObject(font);

  SelectObject(dc, old_bmp);
  DeleteDC(dc);
  ReleaseDC(nullptr, screen);
  DestroyIcon(base);

  ForceOpaque(bmp, size);

  // 掩码全 0（配合强制不透明 alpha）
  std::vector<uint8_t> mask_bits(static_cast<size_t>(size) * size / 8, 0);
  HBITMAP mask = CreateBitmap(size, size, 1, 1, mask_bits.data());
  ICONINFO ii{};
  ii.fIcon = TRUE;
  ii.hbmColor = bmp;
  ii.hbmMask = mask;
  HICON out = CreateIconIndirect(&ii);
  DeleteObject(bmp);
  DeleteObject(mask);
  return out;
}
