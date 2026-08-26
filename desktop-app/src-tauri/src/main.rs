// BamBumPOS masaüstü kabuğu: pencereyi açar, içerik web panelinden gelir.
// Böylece masaüstü uygulaması ayrı bir sürüm gerektirmez — panel güncellenince
// uygulama da güncellenmiş olur.
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

fn main() {
    tauri::Builder::default()
        .run(tauri::generate_context!())
        .expect("BamBumPOS penceresi açılamadı");
}
