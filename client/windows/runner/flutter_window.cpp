#include "flutter_window.h"

#include <commdlg.h>
#include <commctrl.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <shellapi.h>

#include <optional>
#include <string>
#include <vector>

#include "clipboard_image.h"
#include "flutter/generated_plugin_registrant.h"

// v1.1: native file picker channel "chord/file" (no Flutter plugin needed,
// see AGENTS.md pitfall 8). Returns {path, name} or null on cancel.
// 供 WM_KEYDOWN 主动回调 Dart 用的通道指针（进程生命周期内有效）
static flutter::MethodChannel<>* g_file_channel = nullptr;

static std::string ToUtf8(const std::wstring& wide) {
  if (wide.empty()) return std::string();
  int size = WideCharToMultiByte(CP_UTF8, 0, wide.c_str(),
                                 static_cast<int>(wide.size()), nullptr, 0,
                                 nullptr, nullptr);
  std::string utf8(size, 0);
  WideCharToMultiByte(CP_UTF8, 0, wide.c_str(), static_cast<int>(wide.size()),
                      utf8.data(), size, nullptr, nullptr);
  return utf8;
}

// 路径列表 → [{path, name}]，供 Dart 侧读取字节后走附件上传管线。
static flutter::EncodableList PathsToFileList(
    const std::vector<std::wstring>& paths) {
  flutter::EncodableList list;
  for (const auto& path : paths) {
    const size_t pos = path.find_last_of(L"\\/");
    const std::wstring name =
        (pos == std::wstring::npos) ? path : path.substr(pos + 1);
    flutter::EncodableMap item;
    item[flutter::EncodableValue("path")] = flutter::EncodableValue(ToUtf8(path));
    item[flutter::EncodableValue("name")] = flutter::EncodableValue(ToUtf8(name));
    list.push_back(flutter::EncodableValue(item));
  }
  return list;
}

// 从 HDROP 取出所有文件路径（拖放 / CF_HDROP 共用）。
static std::vector<std::wstring> PathsFromHDrop(HDROP drop) {
  std::vector<std::wstring> paths;
  const UINT count = DragQueryFileW(drop, 0xFFFFFFFF, nullptr, 0);
  for (UINT i = 0; i < count; ++i) {
    const UINT len = DragQueryFileW(drop, i, nullptr, 0);
    if (len == 0) continue;
    std::wstring path(len, L'\0');
    const UINT got = DragQueryFileW(drop, i, path.data(), len + 1);
    if (got > 0) {
      path.resize(got);
      paths.push_back(path);
    }
  }
  return paths;
}

// Flutter 的视图是独立的子 HWND（键盘/拖放消息都发给它），顶层
// FlutterWindow::MessageHandler 收不到。用 SetWindowSubclass 钩住子窗口，
// 只处理 WM_DROPFILES（文件拖进窗口 → 上传），其余转回 Flutter 默认处理。
static LRESULT CALLBACK FlutterViewDropProc(HWND hwnd, UINT message,
                                            WPARAM wparam, LPARAM lparam,
                                            UINT_PTR, DWORD_PTR) {
  if (message == WM_DROPFILES) {
    auto drop = reinterpret_cast<HDROP>(wparam);
    const auto paths = PathsFromHDrop(drop);
    DragFinish(drop);
    if (g_file_channel != nullptr && !paths.empty()) {
      g_file_channel->InvokeMethod(
          "onDroppedFiles",
          std::make_unique<flutter::EncodableValue>(PathsToFileList(paths)));
    }
    return 0;
  }
  return DefSubclassProc(hwnd, message, wparam, lparam);
}

static void RegisterFileChannel(flutter::FlutterEngine* engine) {
  // Heap-allocated and intentionally never freed: the channel must outlive
  // every method call for the lifetime of the process.
  auto* channel = new flutter::MethodChannel<>(
      engine->messenger(), "chord/file", &flutter::StandardMethodCodec::GetInstance());
  g_file_channel = channel;
  channel->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        // Dart → 原生：把 RGBA 写入剪贴板（图片复制）
        if (call.method_name() == "copyImage") {
          const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
          if (args == nullptr) {
            result->Error("bad_args", "copyImage expects map");
            return;
          }
          auto it_data = args->find(flutter::EncodableValue("data"));
          auto it_w = args->find(flutter::EncodableValue("width"));
          auto it_h = args->find(flutter::EncodableValue("height"));
          const auto* bytes = (it_data != args->end())
                                  ? std::get_if<std::vector<uint8_t>>(&it_data->second)
                                  : nullptr;
          const auto* w = (it_w != args->end())
                              ? std::get_if<int32_t>(&it_w->second)
                              : nullptr;
          const auto* h = (it_h != args->end())
                              ? std::get_if<int32_t>(&it_h->second)
                              : nullptr;
          if (bytes == nullptr || w == nullptr || h == nullptr) {
            result->Error("bad_args", "copyImage expects data/width/height");
            return;
          }
          const bool ok = clipboard_image::CopyRgbaToClipboard(*bytes, *w, *h);
          result->Success(flutter::EncodableValue(ok));
          return;
        }
        // Dart → 原生：主动读取剪贴板图片（Ctrl+V 时由 Dart 侧触发，作为
        // WM_KEYDOWN 的兜底——键盘焦点在 Flutter 子窗口时顶层窗口收不到按键）
        if (call.method_name() == "readClipboardImage") {
          std::vector<uint8_t> rgba;
          int w = 0, h = 0;
          if (!clipboard_image::ReadClipboardRgba(&rgba, &w, &h) || w <= 0 || h <= 0) {
            result->Success(nullptr);  // 剪贴板里没有图片
            return;
          }
          flutter::EncodableMap payload;
          payload[flutter::EncodableValue("data")] = flutter::EncodableValue(rgba);
          payload[flutter::EncodableValue("width")] = flutter::EncodableValue(w);
          payload[flutter::EncodableValue("height")] = flutter::EncodableValue(h);
          result->Success(flutter::EncodableValue(payload));
          return;
        }
        if (call.method_name() == "readClipboardFiles") {
          std::vector<std::wstring> paths;
          if (!clipboard_image::ReadClipboardPaths(&paths)) {
            result->Success(nullptr);  // 剪贴板里没有文件
            return;
          }
          result->Success(flutter::EncodableValue(PathsToFileList(paths)));
          return;
        }
        if (call.method_name() != "pickFile") {
          result->NotImplemented();
          return;
        }
        bool images_only = false;
        if (const auto* args =
                std::get_if<flutter::EncodableMap>(call.arguments())) {
          auto it = args->find(flutter::EncodableValue("imagesOnly"));
          if (it != args->end()) {
            if (const auto* b = std::get_if<bool>(&it->second)) {
              images_only = *b;
            }
          }
        }

        wchar_t file[MAX_PATH] = L"";
        OPENFILENAMEW ofn{};
        ofn.lStructSize = sizeof(ofn);
        ofn.hwndOwner = GetActiveWindow();
        ofn.lpstrFile = file;
        ofn.nMaxFile = MAX_PATH;
        ofn.lpstrFilter = images_only
            ? L"Images\0*.jpg;*.jpeg;*.png;*.gif;*.webp;*.svg\0All files\0*.*\0"
            : L"All files\0*.*\0";
        ofn.Flags = OFN_FILEMUSTEXIST | OFN_PATHMUSTEXIST | OFN_NOCHANGEDIR;

        if (!GetOpenFileNameW(&ofn)) {
          result->Success(nullptr);  // user cancelled
          return;
        }

        auto to_utf8 = [](const std::wstring& wide) -> std::string {
          if (wide.empty()) return std::string();
          int size = WideCharToMultiByte(CP_UTF8, 0, wide.c_str(),
                                         static_cast<int>(wide.size()),
                                         nullptr, 0, nullptr, nullptr);
          std::string utf8(size, 0);
          WideCharToMultiByte(CP_UTF8, 0, wide.c_str(),
                              static_cast<int>(wide.size()), utf8.data(),
                              size, nullptr, nullptr);
          return utf8;
        };

        const std::wstring wpath(file);
        size_t pos = wpath.find_last_of(L"\\/");
        const std::wstring wname =
            (pos == std::wstring::npos) ? wpath : wpath.substr(pos + 1);

        flutter::EncodableMap resp;
        resp[flutter::EncodableValue("path")] =
            flutter::EncodableValue(to_utf8(wpath));
        resp[flutter::EncodableValue("name")] =
            flutter::EncodableValue(to_utf8(wname));
        result->Success(flutter::EncodableValue(resp));
      });
}

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  // 安装系统托盘图标（点 X = 隐藏到托盘，消息继续实时接收）
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
  RegisterFileChannel(flutter_controller_->engine());

  // Dart → 原生：未读数上报（托盘角标 + 提示文字）
  app_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "chord/app",
      &flutter::StandardMethodCodec::GetInstance());
  app_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name() != "setBadge") {
          result->NotImplemented();
          return;
        }
        const auto* n = std::get_if<int32_t>(call.arguments());
        if (n == nullptr) {
          result->Error("bad_args", "setBadge expects int");
          return;
        }
        tray_.SetBadge(*n);
        result->Success();
      });

  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  // 文件拖放：拖进窗口时 Windows 把 WM_DROPFILES 发给鼠标下的窗口，
  // 即 Flutter 的视图子窗口（不是顶层窗口）——子类化它并接受文件拖放。
  {
    HWND view = flutter_controller_->view()->GetNativeWindow();
    DragAcceptFiles(view, TRUE);
    SetWindowSubclass(view, FlutterViewDropProc, 1, 0);
  }

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
  if (flutter_controller_ && flutter_controller_->view()) {
    HWND view = flutter_controller_->view()->GetNativeWindow();
    RemoveWindowSubclass(view, FlutterViewDropProc, 1);
    DragAcceptFiles(view, FALSE);
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
  // Ctrl+V 且剪贴板为图片/文件 → 主动回调 Dart（onClipboardImage/onClipboardFiles）。
  // 必须在 HandleTopLevelWindowProc 之前：Flutter 会处理（并返回）键盘消息，
  // 放到 switch 里永远收不到（v1.3.5 的 bug）。这里只旁路读取，不吞按键。
  if (message == WM_KEYDOWN && wparam == 'V' &&
      (GetKeyState(VK_CONTROL) & 0x8000) != 0 && g_file_channel != nullptr) {
    std::vector<uint8_t> rgba;
    int w = 0, h = 0;
    if (clipboard_image::ReadClipboardRgba(&rgba, &w, &h) && w > 0 && h > 0) {
      flutter::EncodableMap payload;
      payload[flutter::EncodableValue("data")] = flutter::EncodableValue(rgba);
      payload[flutter::EncodableValue("width")] = flutter::EncodableValue(w);
      payload[flutter::EncodableValue("height")] = flutter::EncodableValue(h);
      g_file_channel->InvokeMethod(
          "onClipboardImage",
          std::make_unique<flutter::EncodableValue>(payload));
    } else {
      // 资源管理器里 Ctrl+C 的是文件（CF_HDROP）
      std::vector<std::wstring> paths;
      if (clipboard_image::ReadClipboardPaths(&paths)) {
        g_file_channel->InvokeMethod(
            "onClipboardFiles",
            std::make_unique<flutter::EncodableValue>(PathsToFileList(paths)));
      }
    }
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
    case WM_CLOSE:
      // 点 X：隐藏到系统托盘而不是退出（托盘菜单「退出」才真正关闭）
      tray_.HideWindowToTray(hwnd);
      return 0;
    case WM_APP + 1:  // 托盘图标回调
      if (tray_.HandleNotification(hwnd, wparam, lparam)) {
        return 0;
      }
      break;
    case WM_APP + 2:  // 另一个实例启动时请求唤起本窗口
      tray_.RestoreWindow(hwnd);
      return 0;
    case WM_DESTROY:
      tray_.Remove(hwnd);
      break;
    case WM_GETMINMAXINFO: {
      // 最小窗口尺寸（逻辑像素，按 DPI 缩放）
      auto info = reinterpret_cast<MINMAXINFO*>(lparam);
      UINT dpi = GetDpiForWindow(hwnd);
      info->ptMinTrackSize.x = MulDiv(900, dpi, 96);
      info->ptMinTrackSize.y = MulDiv(600, dpi, 96);
      return 0;
    }
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
