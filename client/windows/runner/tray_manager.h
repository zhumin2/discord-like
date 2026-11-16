#ifndef RUNNER_TRAY_MANAGER_H_
#define RUNNER_TRAY_MANAGER_H_

#include <windows.h>

// 系统托盘管理（聊天客户端）：关闭窗口 = 隐藏到托盘，程序与 WebSocket 连接继续运行。
// 左键单击图标恢复窗口；右键菜单提供「打开 Chord / 退出」。
class TrayManager {
 public:
  // 安装托盘图标。返回是否成功。
  bool Install(HWND hwnd);

  // 移除托盘图标（退出前调用）。
  void Remove(HWND hwnd);

  // 处理托盘图标通知消息（WM_APP+1）。返回 true 表示消息已处理。
  bool HandleNotification(HWND hwnd, WPARAM wparam, LPARAM lparam);

  // 隐藏窗口到托盘（首次显示气泡提示）。
  void HideWindowToTray(HWND hwnd);

  // 从托盘恢复窗口。
  void RestoreWindow(HWND hwnd);

 private:
  void ShowContextMenu(HWND hwnd);

  NOTIFYICONDATAW nid_ = {};
  bool installed_ = false;
  bool balloon_shown_ = false;
};

#endif  // RUNNER_TRAY_MANAGER_H_
