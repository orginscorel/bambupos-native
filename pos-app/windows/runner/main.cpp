#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "baslangic_log.h"
#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // pos-win7: Flutter motoru başlamadan ÖNCE günlük + çökme yakalayıcı.
  // %LOCALAPPDATA%\BamBumPOS\logs\baslangic.log
  BaslangicLogKur();
  CokusYakalayiciKur();
  BaslangicLog(L"wWinMain başladı");
  // flutter_windows.dll ve eklentiler gecikmeli yüklenir (CMakeLists
  // /DELAYLOAD): eksik DLL / Windows 8+ işlevi burada adıyla yakalanır.
  if (!BaglantilariDenetle()) {
    return EXIT_FAILURE;
  }

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
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1366, 820);
  BaslangicLog(L"Pencere ve Flutter motoru oluşturuluyor");
  if (!window.Create(L"BamBumPOS", origin, size)) {
    HataKutusu(L"BamBumPOS penceresi / Flutter motoru oluşturulamadı.\n"
               L"Ekran kartı sürücüsü ve Windows 7 Platform Update (KB2670838) "
               L"kurulu olmalı.");
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);
  BaslangicLog(L"Pencere hazır; mesaj döngüsü başlıyor");

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  BaslangicLog(L"Uygulama kapandı (normal çıkış)");
  return EXIT_SUCCESS;
}
