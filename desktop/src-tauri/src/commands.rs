//! Frontend'e (dist/index.html + `window.__TAURI__.core.invoke`) açılan
//! komutlar. İSKELET: küçük, kasıtlı olarak dar bir yüzey — tam POS UI'ı bu
//! görevin kapsamı DIŞINDA (bkz. görev kısıtları), bu yüzden yalnız
//! offline/online durumunu ve senkron akışını GÖSTERMEYE yetecek komutlar var.

use chrono::Utc;
use serde::Serialize;
use serde_json::json;
use tauri::{AppHandle, Manager, State, WebviewUrl, WebviewWindowBuilder};
use uuid::Uuid;

use crate::state::AppState;
use crate::sync::{self, queue};

#[derive(Serialize)]
pub struct StatusDto {
    pub online: bool,
    pub pending_ops: i64,
    pub failed_ops: i64,
    pub last_baseline_pull_at: Option<String>,
    pub last_delta_pull_at: Option<String>,
}

#[tauri::command]
pub fn get_status(state: State<AppState>) -> Result<StatusDto, String> {
    let conn = state.db.lock().map_err(|e| e.to_string())?;

    let pending_ops = queue::count_pending(&conn).map_err(|e| e.to_string())?;
    let failed_ops: i64 = conn
        .query_row(
            "SELECT count(*) FROM failed_ops WHERE acknowledged = 0",
            [],
            |row| row.get(0),
        )
        .map_err(|e| e.to_string())?;

    let last_baseline_pull_at = get_meta(&conn, "last_baseline_pull_at");
    let last_delta_pull_at = get_meta(&conn, "last_delta_pull_at");

    Ok(StatusDto {
        online: state.is_online(),
        pending_ops,
        failed_ops,
        last_baseline_pull_at,
        last_delta_pull_at,
    })
}

#[derive(Serialize)]
pub struct SyncSummaryDto {
    pub succeeded: usize,
    pub retried: usize,
    pub failed_permanent: usize,
    pub skipped_unresolved: usize,
    pub pull_ok: bool,
    pub pull_error: Option<String>,
}

/// Kullanıcı "şimdi senkronla" butonuna basınca (ya da arka plan döngüsü
/// otomatik) çağrılır. Ağır işi bloklamamak için `db` kilidini kısa tutar:
/// `sync::run_cycle` kendi içinde connection'ı kullandığı sürece kilitli
/// kalır — TODO: uzun kuyruklarda bu, `get_status` gibi diğer komutları
/// geçici olarak bekletebilir; ileride ayrı bir okuma bağlantısı (rusqlite
/// `Connection` WAL modunda eşzamanlı okumaya izin verir ama tek `Mutex`
/// üzerinden paylaşıldığı için bugün pratikte serileşiyor) düşünülebilir.
#[tauri::command]
pub async fn force_sync(state: State<'_, AppState>) -> Result<SyncSummaryDto, String> {
    let summary = {
        let conn = state.db.lock().map_err(|e| e.to_string())?;
        // NOT: `conn` MutexGuard `Send` degil; async fn icinde `.await`
        // sinirini asamaz. Bu yuzden `sync::run_cycle` cagrisi da senkron
        // (rusqlite zaten senkron) - yalniz `api.post_json`/`get_json`
        // (`reqwest`) await gerektiriyor. TODO (derleme zamaninda netlesecek
        // gercek risk): eger `run_cycle` imzasi `&Connection` + `.await`
        // karistiginda borrow-checker/Send hatasi verirse, kilidi tek bir
        // senkron blokta tutup HTTP cagrilarini `tauri::async_runtime::
        // block_on` ile SARMALAMAK yerine, db islemlerini kucuk senkron
        // fonksiyonlara bolup kilidi HTTP awaiti SIRASINDA birakmak dogru
        // cozum - bu iskelette basitlik icin coz{ulmedi}, ilk `cargo check`
        // bunu netlestirecek (bkz. SYNC.md "Derleme talimati").
        futures_lite_block_on(sync::run_cycle(&conn, &state.api))
    }
    .map_err(|e| e.to_string())?;

    state.set_online(summary.pull.is_ok());

    Ok(SyncSummaryDto {
        succeeded: summary.replay.succeeded,
        retried: summary.replay.retried,
        failed_permanent: summary.replay.failed_permanent,
        skipped_unresolved: summary.replay.skipped_unresolved,
        pull_ok: summary.pull.is_ok(),
        pull_error: summary.pull.err().map(|e| e.to_string()),
    })
}

/// TODO (gecici): `run_cycle` async, ama `db.lock()` MutexGuard'ı bir
/// `.await` noktasından canlı geçiremiyoruz (Send değil). Gerçek çözüm
/// SYNC.md'de anlatıldığı gibi db erişimini yeniden yapılandırmak; bu
/// yardımcı yalnız İSKELETİN taslak durumda derlenebilir/okunabilir kalması
/// için bir yer tutucu - `cargo check` sonrası KALDIRILMALI.
fn futures_lite_block_on<F: std::future::Future>(fut: F) -> F::Output {
    tauri::async_runtime::block_on(fut)
}

/// Kullanıcı adisyona kalem eklediğinde (offline dahil) çağrılır: `op_id`
/// BURADA, tıklama anında üretilir (protokol §2.1) ve `pending_ops`'a yazılır.
/// Ağ o an var mı yok mu ÖNEMLİ DEĞİL — arka plan döngüsü ya da bir sonraki
/// `force_sync` kuyruğu oynatır. Mirror'a iyimser (optimistic) bir satır da
/// eklenir ki UI ağ beklemeden anında güncellensin (TODO: gerçek toplam/vergi
/// hesaplaması sunucudaki `OrderService`'te - burada YALNIZ kaba bir
/// qty*unit_price gösterimi, kesin değer bir sonraki pull/replay yanıtıyla
/// düzeltilir; kullanıcıya "senkron bekleniyor" rozeti gösterilmesi önerilir).
#[tauri::command]
pub fn enqueue_add_item(
    state: State<AppState>,
    order_local_id: String,
    product_id: i64,
    variant_id: Option<i64>,
    qty: i64,
    note: Option<String>,
) -> Result<String, String> {
    let conn = state.db.lock().map_err(|e| e.to_string())?;

    let payload = json!({
        "product_id": product_id,
        "variant_id": variant_id,
        "qty": qty,
        "note": note,
    });

    // TODO: endpoint'teki server order id yer tutucusu {order} - resolve_endpoint
    // (sync/replay.rs) bunu order_local_id -> mirror_orders.server_id üzerinden
    // cozer; order henuz senkronlanmadiysa bu op dogal olarak beklemede kalir.
    let op_id = queue::enqueue(
        &conn,
        "order.item.add",
        "/api/v1/orders/{order}/items",
        "POST",
        &payload,
        Some(&order_local_id),
    )
    .map_err(|e| e.to_string())?;

    // İyimser yerel satır (TODO: gercek line_total_minor hesaplamasi eksik,
    // unit_price_minor de bilinmiyor - mirror_products'tan cekilmeli).
    let now = Utc::now().to_rfc3339();
    let local_item_id = Uuid::new_v4().to_string();
    conn.execute(
        "INSERT INTO mirror_order_items
            (local_id, order_local_id, product_id, variant_id, status, qty, name,
             unit_price_minor, options_price_minor, line_total_minor, note, created_at, synced_at)
         VALUES (?1, ?2, ?3, ?4, 'placed', ?5, '', 0, 0, 0, ?6, ?7, NULL)",
        rusqlite::params![local_item_id, order_local_id, product_id, variant_id, qty, note, now],
    )
    .map_err(|e| e.to_string())?;

    Ok(op_id)
}

/// STUB — bilinçli olarak sunucuya senkronlamıyor. Bugün yalnız
/// `OrderController::addItem` sunucu tarafında `op_id` idempotency
/// destekliyor (bkz. docs/offline-sync-protocol.md §7 "kapsam dışı":
/// "PaymentController@store, diğer orders.php/payments.php uçları... yalnız
/// addItem PROOF olarak değiştirildi"). `OrderController::store` (adisyon
/// AÇMA) op_id DESTEKLEMİYOR — bu uca offline'da üretilen bir "adisyon aç"
/// niyetini kuyruğa koyup idempotent olmayan bir POST'a karşı REPLAY etmek
/// çift-adisyon riski taşır (protokolün TÜM amacına aykırı). Bu yüzden bu
/// komut şimdilik yalnız YEREL bir adisyon satırı oluşturur (`origin='local'`,
/// `server_id=NULL`, §4 tasarımındaki terminal-önekli geçici numarayla) ve
/// SUNUCUYA HİÇ GÖNDERMEZ. Gerçek senkron için önce sunucu tarafında
/// `OrderController::store`'a aynı `op_id` deseni uygulanmalı (SYNC.md'de
/// "Sonraki adımlar" #1 olarak listelendi).
#[tauri::command]
pub fn open_local_order(state: State<AppState>, table_id: Option<i64>) -> Result<String, String> {
    let conn = state.db.lock().map_err(|e| e.to_string())?;

    let terminal_code = get_meta(&conn, "terminal_code").unwrap_or_else(|| "T0".to_string());
    let seq = bump_terminal_seq(&conn).map_err(|e| e.to_string())?;
    let local_temp_no = format!("{terminal_code}-{seq:03}");

    let local_id = Uuid::new_v4().to_string();
    let now = Utc::now().to_rfc3339();
    // TODO: tenant_id/branch_id bugün sabit/meta'dan okunmuyor - kurulum
    // akışında (ilk çalıştırma sihirbazı, YAZILMADI) meta'ya yazılmalı.
    let tenant_id = get_meta(&conn, "tenant_id").and_then(|v| v.parse::<i64>().ok()).unwrap_or(0);
    let branch_id = get_meta(&conn, "branch_id").and_then(|v| v.parse::<i64>().ok()).unwrap_or(0);

    conn.execute(
        "INSERT INTO mirror_orders
            (local_id, server_id, local_temp_no, tenant_id, branch_id, table_id, status,
             total_minor, currency, version, origin, created_at, updated_at, synced_at)
         VALUES (?1, NULL, ?2, ?3, ?4, ?5, 'open', 0, 'TRY', 0, 'local', ?6, ?6, NULL)",
        rusqlite::params![local_id, local_temp_no, tenant_id, branch_id, table_id, now],
    )
    .map_err(|e| e.to_string())?;

    Ok(local_id)
}

fn bump_terminal_seq(conn: &rusqlite::Connection) -> rusqlite::Result<i64> {
    let current: i64 = get_meta(conn, "terminal_local_seq")
        .and_then(|v| v.parse().ok())
        .unwrap_or(0);
    let next = current + 1;
    conn.execute(
        "INSERT INTO meta (key, value) VALUES ('terminal_local_seq', ?1)
         ON CONFLICT(key) DO UPDATE SET value = excluded.value",
        rusqlite::params![next.to_string()],
    )?;
    Ok(next)
}

fn get_meta(conn: &rusqlite::Connection, key: &str) -> Option<String> {
    conn.query_row("SELECT value FROM meta WHERE key = ?1", [key], |row| row.get(0))
        .ok()
}

#[derive(Serialize)]
pub struct FailedOpDto {
    pub id: i64,
    pub scope: String,
    pub error: String,
    pub failed_at: String,
}

#[tauri::command]
pub fn list_failed_ops(state: State<AppState>) -> Result<Vec<FailedOpDto>, String> {
    let conn = state.db.lock().map_err(|e| e.to_string())?;
    let mut stmt = conn
        .prepare("SELECT id, scope, error, failed_at FROM failed_ops WHERE acknowledged = 0 ORDER BY failed_at DESC")
        .map_err(|e| e.to_string())?;

    let rows = stmt
        .query_map([], |row| {
            Ok(FailedOpDto {
                id: row.get(0)?,
                scope: row.get(1)?,
                error: row.get(2)?,
                failed_at: row.get(3)?,
            })
        })
        .map_err(|e| e.to_string())?
        .collect::<Result<Vec<_>, _>>()
        .map_err(|e| e.to_string())?;

    Ok(rows)
}

#[tauri::command]
pub fn ack_failed_op(state: State<AppState>, id: i64) -> Result<(), String> {
    let conn = state.db.lock().map_err(|e| e.to_string())?;
    conn.execute("UPDATE failed_ops SET acknowledged = 1 WHERE id = ?1", [id])
        .map_err(|e| e.to_string())?;
    Ok(())
}

/// Çevrimiçiyken çağrılır (dist/index.html'in bağlantı kontrolünden sonra):
/// ONLINE panelin GERÇEK sunucu sayfasını ayrı bir pencerede (label "panel",
/// bkz. capabilities/default.json `windows`) açar. Ana `shell` penceresi
/// (index.html) bilinçli olarak yerelde kalır - böylece dış domaine
/// navigasyon CSP/güvenlik karmaşasına girmeden, Tauri'nin desteklediği
/// "harici URL'li ikinci pencere" deseniyle çözülür.
///
/// TODO: `base_url` bugün `state.api`'nin kurulurken aldığı sabit değer -
/// AppState üzerinde ayrıca expose edilmedi (ApiClient private alan),
/// bu yüzden burada AYNI ortam değişkeni tekrar okunuyor - küçük bir
/// tekrar, TODO: tek kaynağa indirilmeli (ör. AppState::app_url()).
#[tauri::command]
pub fn open_online_panel(app: AppHandle) -> Result<(), String> {
    let base_url = std::env::var("BAMBUMPOS_APP_URL")
        .unwrap_or_else(|_| "https://qrmenu.bogahostdeveloper.com.tr".to_string());

    if let Some(existing) = app.get_webview_window("panel") {
        existing.set_focus().map_err(|e| e.to_string())?;
        return Ok(());
    }

    let url = url::Url::parse(&base_url).map_err(|e| e.to_string())?;

    WebviewWindowBuilder::new(&app, "panel", WebviewUrl::External(url))
        .title("BamBumPOS - Panel")
        .inner_size(1280.0, 800.0)
        .build()
        .map_err(|e| e.to_string())?;

    Ok(())
}
