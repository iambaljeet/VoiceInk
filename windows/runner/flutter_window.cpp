#include "flutter_window.h"

#include <optional>
#include <windowsx.h>

#include <flutter/standard_method_codec.h>
#include "flutter/generated_plugin_registrant.h"

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
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  // Set up the hover method channel for capsule hit-testing.
  hover_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "com.voiceink/hover",
          &flutter::StandardMethodCodec::GetInstance());

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
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;

    case WM_MOUSEMOVE: {
      // Register for WM_MOUSELEAVE if not already tracking.
      if (!tracking_mouse_) {
        TRACKMOUSEEVENT tme = {};
        tme.cbSize = sizeof(tme);
        tme.dwFlags = TME_LEAVE;
        tme.hwndTrack = hwnd;
        TrackMouseEvent(&tme);
        tracking_mouse_ = true;
      }

      if (hover_channel_) {
        double x = static_cast<double>(GET_X_LPARAM(lparam));
        double y = static_cast<double>(GET_Y_LPARAM(lparam));
        flutter::EncodableMap args;
        args[flutter::EncodableValue("x")] = flutter::EncodableValue(x);
        args[flutter::EncodableValue("y")] = flutter::EncodableValue(y);
        hover_channel_->InvokeMethod(
            "mouseMove",
            std::make_unique<flutter::EncodableValue>(args));
      }
      break;
    }

    case WM_MOUSELEAVE: {
      tracking_mouse_ = false;
      if (hover_channel_) {
        hover_channel_->InvokeMethod(
            "mouseExit",
            std::make_unique<flutter::EncodableValue>(
                flutter::EncodableValue()));
      }
      break;
    }
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
