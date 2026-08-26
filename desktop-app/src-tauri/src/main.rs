//! BamBumPOS masaüstü uygulaması.
//!
//! Pencere paneli açar; ayrıca CİHAZ KÖPRÜSÜ komutlarını sunar (yazıcı
//! listesi, ağ taraması, ham yazdırma, seri port keşfi). Tarayıcının
//! yapamadığı işler burada yapılır — uygulamayı "sekmede açılan site"den
//! ayıran kısım budur.
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod devices;

fn main() {
    tauri::Builder::default()
        .invoke_handler(tauri::generate_handler![
            devices::bridge_info,
            devices::list_os_printers,
            devices::list_serial_ports,
            devices::scan_network,
            devices::raw_print_network,
            devices::raw_print_os,
            devices::probe_device,
        ])
        .run(tauri::generate_context!())
        .expect("BamBumPOS penceresi açılamadı");
}
