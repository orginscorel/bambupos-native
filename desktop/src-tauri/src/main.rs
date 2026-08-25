// BamBumPOS masaüstü kabuğu — Tauri v2 giriş noktası.
//
// İSKELET UYARISI: bu dosya bu ortamda `cargo check` ile DOĞRULANMADI
// (ortamda cargo/rustc yok — bkz. desktop/SYNC.md "Derleme talimatı").
// Tauri v2 API'leri (özellikle `app.path()`, plugin kayıt imzaları,
// `WebviewWindowBuilder`) minor sürümler arasında değişebiliyor; ilk
// `cargo check` bu dosyada küçük imza uyuşmazlıkları çıkarabilir - normal
// kabul edin ve derleyici mesajına göre düzeltin.
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod commands;
mod db;
mod state;
mod sync;

use std::time::Duration;

use tauri::Manager;

use state::AppState;
use sync::client::ApiClient;

/// TODO: kurulum sihirbazı (YAZILMADI) bunu `meta.app_url`'e yazana kadar
/// derleme-zamanı ortam değişkeni + sabit geri dönüş kullanılıyor. Üretimde
/// bambumpos.com kiracıları için doğru host FARKLI olacaktır (bkz. bellek:
/// "bambumpos migration" - tek app + host-routing) - bu yüzden BURADA
/// SABİTLEMEK yerine ilk-çalıştırma ekranında kullanıcıya/kuruluma
/// SORULMALI. Şimdilik derleme zamanında `BAMBUMPOS_APP_URL` ile ezilebilir.
const DEFAULT_APP_URL: &str = "https://qrmenu.bogahostdeveloper.com.tr";

fn main() {
    tracing_subscriber::fmt()
        .with_env_filter(tracing_subscriber::EnvFilter::from_default_env())
        .init();

    tauri::Builder::default()
        .plugin(tauri_plugin_shell::init())
        .plugin(tauri_plugin_http::init())
        .plugin(tauri_plugin_store::Builder::default().build())
        .setup(|app| {
            let handle = app.handle().clone();

            // TODO doğrula: Tauri v2'de `app.path()` -> `PathResolver`,
            // `.app_data_dir()` -> `Result<PathBuf, tauri::Error>`.
            let data_dir = handle
                .path()
                .app_data_dir()
                .expect("app_data_dir çözülemedi - platform path resolver sorunu");

            let conn = db::open(data_dir).expect("yerel SQLite acilamadi/sema uygulanamadi");

            let base_url = std::env::var("BAMBUMPOS_APP_URL").unwrap_or_else(|_| DEFAULT_APP_URL.to_string());
            // TODO (kritik açık risk - bkz. sync/client.rs başlığı): auth_token
            // bugün DAİMA None. Sunucu tarafında terminal-token tabanlı bir
            // guard eklenene kadar arka plan senkronu pratikte 401/302 alır.
            let auth_token: Option<String> = std::env::var("BAMBUMPOS_AUTH_TOKEN").ok();

            let api = ApiClient::new(base_url, auth_token).expect("HTTP istemcisi kurulamadi");

            app.manage(AppState::new(conn, api));

            // Arka plan senkron döngüsü: periyodik bağlantı kontrolü + varsa
            // kuyruk oynatma/pull. TODO: aralık (30sn) sabit kodlandı - ileride
            // kullanıcı ayarına ya da "hemen dene, sonra üstel geri çekilme"
            // (exponential backoff) desenine bağlanmalı; bugün basit sabit
            // aralık, pil/bant genişliği açısından optimize EDİLMEDİ.
            let bg_handle = app.handle().clone();
            tauri::async_runtime::spawn(async move {
                let mut interval = tokio::time::interval(Duration::from_secs(30));
                loop {
                    interval.tick().await;
                    run_background_cycle(&bg_handle).await;
                }
            });

            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            commands::get_status,
            commands::force_sync,
            commands::enqueue_add_item,
            commands::open_local_order,
            commands::list_failed_ops,
            commands::ack_failed_op,
            commands::open_online_panel,
        ])
        .run(tauri::generate_context!())
        .expect("BamBumPOS masaustu kabugu baslatilamadi");
}

/// Arka plan döngüsünün tek turu: `AppState`'i çözer, `sync::run_cycle`'ı
/// çalıştırır, sonucu `state.online`'a yazar ve frontend'e bir olay yayınlar
/// (dist/index.html bunu dinleyip online panel yükleme/offline kabuk
/// gösterme kararını verebilir - bkz. dist/index.html TODO).
async fn run_background_cycle(app: &tauri::AppHandle) {
    let state = app.state::<AppState>();

    let result = {
        // NOT: commands::force_sync'teki AYNI Send/await kısıtı burada da
        // geçerli - bkz. o dosyadaki TODO. `block_on` kullanımı bilinçli
        // geçici çözüm, cargo check sonrası gözden geçirilmeli.
        let conn = state.db.lock().expect("db kilidi alinamadi (poisoned mutex)");
        tauri::async_runtime::block_on(sync::run_cycle(&conn, &state.api))
    };

    match result {
        Ok(summary) => {
            state.set_online(summary.pull.is_ok());
            tracing::info!(
                succeeded = summary.replay.succeeded,
                retried = summary.replay.retried,
                failed = summary.replay.failed_permanent,
                pull_ok = summary.pull.is_ok(),
                "arka plan senkron turu tamamlandi"
            );
        }
        Err(e) => {
            state.set_online(false);
            tracing::warn!(error = %e, "arka plan senkron turu basarisiz");
        }
    }

    // TODO: frontend'e emit (`app.emit("sync-status", ...)`) burada
    // eklenmeli ki dist/index.html canli guncellensin - iskelette
    // `get_status` komutu polling ile cagirilarak da ayni sonuc alinabilir
    // (basitlik icin bugun polling varsayildi, bkz. dist/index.html).
}
