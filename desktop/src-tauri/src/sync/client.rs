//! Sunucu HTTP istemcisi — arka planda (webview DIŞINDA) çalışan Rust
//! senkron motorunun ağ katmanı.
//!
//! ÖNEMLİ AYRIM: bu istemci, pencerede yüklü online panelin kendi `fetch()`
//! çağrılarından TAMAMEN AYRIDIR. Webview online panel (APP_URL) yüklüyken
//! zaten kendi oturum çerezleriyle normal şekilde çalışır — ona hiç
//! dokunmuyoruz. Bu `ApiClient` yalnız *arka planda*, kullanıcı başka bir
//! ekranda olsa bile (veya pencere offline kabuğu gösteriyorken) `pending_ops`
//! kuyruğunu oynatmak ve baseline/delta PULL yapmak için kullanılır.
//!
//! AÇIK RİSK / TODO (bkz. desktop/SYNC.md "Kimlik doğrulama - açık risk"):
//! Laravel tarafındaki panel API'si `auth:web` (oturum çerezi tabanlı) guard
//! kullanıyor — token tabanlı (Sanctum) DEĞİL (bkz. routes/orders.php,
//! routes/venue.php: `Route::middleware(['web','auth:web','tenant'])`).
//! Bu, bağımsız bir Rust HTTP istemcisinin webview'ın oturumundan BAĞIMSIZ
//! olarak kimlik doğrulaması için BUGÜN sunucuda uygun bir mekanizma
//! OLMADIĞI anlamına gelir. İki yol var (ikisi de bu görevin kapsamı
//! dışındaki bir Laravel değişikliği gerektirir):
//!   (a) `terminal_devices` desenini (bugün yalnız kitchen/barista/komi
//!       istasyonları için var, bkz. migrations/2026_07_26_100100_*) masaüstü
//!       terminaline de genişletmek — kurulumda üretilen `token`'ı
//!       `Authorization: Bearer <token>` ile gönderip sunucuda yeni bir
//!       terminal-token guard/middleware eklemek (ÖNERİLEN — terminal
//!       kavramı zaten var, deseni tekrar kullanmak tutarlı).
//!   (b) Webview'ın oturum çerezini (bir Tauri `Cookie` API'siyle) okuyup bu
//!       istemciye kopyalamak — kırılgan (oturum süresi/2FA/çerez adı
//!       değişirse sessizce bozulur), ÖNERİLMEZ.
//! Bu iskelette `auth_token: Option<String>` alanı (b) yerine (a)'yı
//! varsayarak bırakıldı; sunucu tarafı hazır olana kadar `None` ile çalışır
//! ve her istek muhtemelen 401/302 (login redirect) döner — `health_check`
//! bu durumu "offline" olarak ele alır (bkz. aşağıdaki yorum).

use serde_json::Value;

#[derive(Clone)]
pub struct ApiClient {
    http: reqwest::Client,
    /// ör. "https://qrmenu.bogahostdeveloper.com.tr" — sondaki `/` YOK.
    /// TODO: kurulum sırasında kullanıcıdan alınıp `meta.app_url` içinde
    /// saklanmalı; bugün main.rs'te sabit/ENV'den okunuyor (bkz. main.rs).
    base_url: String,
    /// bkz. yukarıdaki modül dokümantasyonu — TODO (a).
    auth_token: Option<String>,
}

#[derive(Debug)]
pub struct ApiResponse {
    pub status: u16,
    pub body: Value,
}

#[derive(Debug, thiserror::Error)]
pub enum ApiError {
    #[error("ağ hatası: {0}")]
    Network(#[from] reqwest::Error),
    #[error("sunucu yanıtı JSON değil (status {status})")]
    InvalidBody { status: u16 },
}

impl ApiClient {
    pub fn new(base_url: String, auth_token: Option<String>) -> anyhow::Result<Self> {
        let http = reqwest::Client::builder()
            .timeout(std::time::Duration::from_secs(15))
            .build()?;

        Ok(Self {
            http,
            base_url,
            auth_token,
        })
    }

    fn url(&self, path: &str) -> String {
        format!("{}/{}", self.base_url.trim_end_matches('/'), path.trim_start_matches('/'))
    }

    fn apply_auth(&self, builder: reqwest::RequestBuilder) -> reqwest::RequestBuilder {
        match &self.auth_token {
            Some(token) => builder.bearer_auth(token),
            // TODO (a) hazır olana kadar auth yok — istekler muhtemelen
            // sunucudan 302 (login) veya 401 döner; çağıran taraf
            // (sync/pull.rs, sync/replay.rs) bunu "offline/senkron edilemedi"
            // olarak ele almalı, panik ATMAMALI.
            None => builder,
        }
    }

    /// Basit ulaşılabilirlik kontrolü — periyodik bağlantı denetleyicisi
    /// (main.rs'teki arka plan döngüsü) bunu kullanır. Kasıtlı olarak HAFİF
    /// bir uç seçilmeli; TODO: sunucuda gerçek bir `/api/v1/ping` veya
    /// benzeri kimlik-doğrulamasız health endpoint YOK — bugün yalnız TCP/TLS
    /// el sıkışmasının başarısı ölçülüyor (`orders/board`'a HEAD/GET atıp
    /// yalnız "yanıt geldi mi" bakılıyor, 401/302 dahi "online" sayılır çünkü
    /// bağlantı sorunu DEĞİL kimlik sorunu olduğunu gösterir).
    pub async fn health_check(&self) -> bool {
        let req = self.apply_auth(self.http.get(self.url("/api/v1/orders/board")));

        match req.send().await {
            Ok(_resp) => true,
            Err(_e) => false,
        }
    }

    pub async fn get_json(&self, path: &str) -> Result<ApiResponse, ApiError> {
        let req = self.apply_auth(self.http.get(self.url(path)));
        let resp = req.send().await?;
        let status = resp.status().as_u16();
        let body = resp.json::<Value>().await.unwrap_or(Value::Null);

        Ok(ApiResponse { status, body })
    }

    /// `payload` gövdeye AYNEN gider — `op_id` protokol gereği çağıran
    /// tarafından (sync/replay.rs) payload içine zaten eklenmiş olmalı
    /// (bkz. docs/offline-sync-protocol.md §2.2 "gövdeye op_id eklenir").
    pub async fn post_json(&self, path: &str, payload: &Value) -> Result<ApiResponse, ApiError> {
        let req = self.apply_auth(self.http.post(self.url(path)).json(payload));
        let resp = req.send().await?;
        let status = resp.status().as_u16();
        let body = resp.json::<Value>().await.unwrap_or(Value::Null);

        Ok(ApiResponse { status, body })
    }
}
