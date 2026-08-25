//! Uygulama genelinde paylaşılan durum (Tauri `State` olarak enjekte edilir).
//!
//! İSKELET: alanlar bilinçli olarak azdır; gerçek uygulamada muhtemelen
//! ayrı bir `ConnectivityMonitor` task'ı ve `SyncEngine` (bkz. `sync::engine`
//! TODO) burada tutulacak handle'lar üretecek.

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Mutex;

use rusqlite::Connection;

use crate::sync::client::ApiClient;

/// Süreç boyunca tek bir SQLite bağlantısı tutulur (rusqlite `Connection`
/// `Send` değildir ama `Mutex` içinde `Send + Sync` olur). Yüksek eşzamanlılık
/// beklenmiyor (tek masaüstü terminali, tek kullanıcı) — bu yüzden basit bir
/// `Mutex<Connection>` bilinçli tercih; performans sorun olursa `r2d2_sqlite`
/// havuzuna geçilebilir (TODO, bkz. SYNC.md "Sonraki adımlar").
pub struct AppState {
    pub db: Mutex<Connection>,
    pub api: ApiClient,
    /// En son bağlantı denemesinin sonucu (health-check / son başarılı istek).
    /// UI bunu `get_status` komutuyla okur; arka plan döngüsü günceller.
    pub online: AtomicBool,
}

impl AppState {
    pub fn new(db: Connection, api: ApiClient) -> Self {
        Self {
            db: Mutex::new(db),
            api,
            online: AtomicBool::new(false),
        }
    }

    pub fn is_online(&self) -> bool {
        self.online.load(Ordering::Relaxed)
    }

    pub fn set_online(&self, value: bool) {
        self.online.store(value, Ordering::Relaxed);
    }
}
