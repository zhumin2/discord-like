#include "flutter_window.h"

#include <commdlg.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <optional>
#include <string>

#include "flutter/generated_plugin_registrant.h"

// v1.1: native file picker channel "chord/file" (no Flutter plugin needed,
// see AGENTS.md pitfall 8). Returns {path, name} or null on cancel.
static void RegisterFileChannel(flutter::FlutterEngine* engine) {
  // Heap-allocated and intentionally never freed: the channel must outlive
  // every method call for the lifetime of the process.
  auto* channel = new flutter::MethodChannel<>(
      engine->messenger(), "chord/file", &flutter::StandardMethodCodec::GetInstance());
  channel->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
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
