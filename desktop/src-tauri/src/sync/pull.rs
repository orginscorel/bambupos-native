//! Sunucudan istemciye PULL — okuma-modeli aynasını doldurur/tazeler.
//!
//! DURUM: **STUB**. Aşağıdaki fonksiyonlar HTTP çağrısını ve satır sayısını
//! doğru iskeletle kurar ama JSON gövde ayrıştırma/upsert mantığı gerçek
//! sunucu yanıt şekli görülüp (bu görev kapsamında sunucuya istek
//! ATILMADI — yalnız route/controller isimlerinden çıkarım yapıldı)
//! doğrulanmadan TAMAMLANAMAZ. Kullanılan uçlar (bkz. routes/venue.php,
//! routes/orders.php):
//!   - GET /api/v1/venue/tables   (VenueTableController::index)
//!   - GET /api/v1/orders/catalog (OrderCatalogController::index)
//!   - GET /api/v1/orders/board   (OrderController::board)
//! Üçü de `auth:web` oturumu ister — bkz. sync/client.rs başlığındaki
//! kimlik doğrulama riski; bu fonksiyonlar o çözülene kadar pratikte
//! 401/302 alıp `PullError::Unauthenticated` döner.

use chrono::Utc;
use rusqlite::{params, Connection};
use serde_json::Value;

use super::client::ApiClient;

#[derive(Debug, thiserror::Error)]
pub enum PullError {
    #[error("kimlik doğrulanamadı (bkz. sync/client.rs TODO)")]
    Unauthenticated,
    #[error("sunucu hatası: status {0}")]
    ServerError(u16),
    #[error(transparent)]
    Api(#[from] super::client::ApiError),
    #[error(transparent)]
    Db(#[from] rusqlite::Error),
}

pub struct PullSummary {
    pub tables: usize,
    pub products: usize,
    pub open_orders: usize,
}

/// Tam yenileme: masalar + ürünler + açık adisyonlar. Uygulama ilk açıldığında
/// ve her `force_sync` çağrısında (bugün `delta_pull` de buna yönlendiriyor,
/// aşağıya bkz.) çalışır.
pub async fn baseline_pull(conn: &Connection, api: &ApiClient) -> Result<PullSummary, PullError> {
    let tables = pull_tables(conn, api).await?;
    let products = pull_catalog(conn, api).await?;
    let open_orders = pull_open_orders(conn, api).await?;

    set_meta(conn, "last_baseline_pull_at", &Utc::now().to_rfc3339())?;

    Ok(PullSummary {
        tables,
        products,
        open_orders,
    })
}

/// TODO (STUB — ciddi eksik): sunucuda artımlı (delta) çekme için bir
/// `?since=` / cursor sözleşmesi YOK (docs/offline-sync-protocol.md bunu
/// tasarlamadı — yalnız op_id/idempotency katmanı bu görevde uygulandı).
/// Bugün delta_pull, dürüstçe bir "tam yenileme" yapıyor — küçük menü/masa
/// sayıları için kabul edilebilir ama sipariş hacmi arttıkça HER
/// yeniden-bağlanmada tüm board'u çekmek pahalılaşır. Gerçek delta için
/// sunucu tarafında (bu görevin kapsamı DIŞINDA) `updated_at` bazlı bir
/// cursor parametresi eklenmesi önerilir (SYNC.md'de not edildi).
pub async fn delta_pull(conn: &Connection, api: &ApiClient) -> Result<PullSummary, PullError> {
    let summary = baseline_pull(conn, api).await?;
    set_meta(conn, "last_delta_pull_at", &Utc::now().to_rfc3339())?;
    Ok(summary)
}

async fn pull_tables(conn: &Connection, api: &ApiClient) -> Result<usize, PullError> {
    let resp = api.get_json("/api/v1/venue/tables").await?;
    classify_status(resp.status)?;

    // TODO: gerçek gövde şekli doğrulanmadı. Varsayım: `{ "tables": [...] }`
    // ya da doğrudan dizi — ikisini de tolere eden gevşek bir çıkarım:
    let items = extract_array(&resp.body, "tables");
    let now = Utc::now().to_rfc3339();

    for item in &items {
        // TODO: gerçek alan adları (name/is_active/branch_id/tenant_id)
        // sunucu yanıtıyla DOĞRULANMALI — VenueTableController::index'in
        // Presenter/Resource sınıfı bu görevde okunmadı.
        let server_id = item.get("id").and_then(Value::as_i64).unwrap_or(0);
        let tenant_id = item.get("tenant_id").and_then(Value::as_i64).unwrap_or(0);
        let branch_id = item.get("branch_id").and_then(Value::as_i64).unwrap_or(0);
        let name = item.get("name").and_then(Value::as_str).unwrap_or("").to_string();
        let is_active = item.get("is_active").and_then(Value::as_bool).unwrap_or(true) as i64;

        conn.execute(
            "INSERT INTO mirror_tables (server_id, tenant_id, branch_id, name, is_active, synced_at)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6)
             ON CONFLICT(server_id) DO UPDATE SET
                tenant_id = excluded.tenant_id,
                branch_id = excluded.branch_id,
                name = excluded.name,
                is_active = excluded.is_active,
                synced_at = excluded.synced_at",
            params![server_id, tenant_id, branch_id, name, is_active, now],
        )?;
    }

    Ok(items.len())
}

async fn pull_catalog(conn: &Connection, api: &ApiClient) -> Result<usize, PullError> {
    let resp = api.get_json("/api/v1/orders/catalog").await?;
    classify_status(resp.status)?;

    // TODO: OrderCatalogController::index gövdesi (kategoriler > ürünler >
    // varyantlar iç içe mi, düz liste mi?) bu görevde okunmadı — aşağıdaki
    // yalnız üst seviye "products" anahtarı varsayan bir İSKELET.
    let items = extract_array(&resp.body, "products");
    let now = Utc::now().to_rfc3339();

    for item in &items {
        let server_id = item.get("id").and_then(Value::as_i64).unwrap_or(0);
        let tenant_id = item.get("tenant_id").and_then(Value::as_i64).unwrap_or(0);
        let branch_id = item.get("branch_id").and_then(Value::as_i64);
        let name = item.get("name").and_then(Value::as_str).unwrap_or("").to_string();
        let sku = item.get("sku").and_then(Value::as_str);
        let price_minor = item.get("price_minor").and_then(Value::as_i64).unwrap_or(0);
        let currency = item.get("currency").and_then(Value::as_str).unwrap_or("TRY");
        let is_active = item.get("is_active").and_then(Value::as_bool).unwrap_or(true) as i64;

        conn.execute(
            "INSERT INTO mirror_products
                (server_id, tenant_id, branch_id, name, sku, price_minor, currency, is_active, synced_at)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)
             ON CONFLICT(server_id) DO UPDATE SET
                tenant_id = excluded.tenant_id,
                branch_id = excluded.branch_id,
                name = excluded.name,
                sku = excluded.sku,
                price_minor = excluded.price_minor,
                currency = excluded.currency,
                is_active = excluded.is_active,
                synced_at = excluded.synced_at",
            params![server_id, tenant_id, branch_id, name, sku, price_minor, currency, is_active, now],
        )?;

        // TODO: item["variants"] varsa mirror_product_variants'a aynı desenle
        // upsert edilmeli — sunucu gövdesi doğrulanmadan yazılmadı.
    }

    Ok(items.len())
}

async fn pull_open_orders(conn: &Connection, api: &ApiClient) -> Result<usize, PullError> {
    let resp = api.get_json("/api/v1/orders/board").await?;
    classify_status(resp.status)?;

    // TODO: OrderController::board gövdesi (tableCards yapısı, bkz. o
    // fonksiyonun kaynağı) her masa için order özet(ler)i döner — burada
    // yalnız `orders` düz dizisi varsayan bir İSKELET; gerçek şekle göre
    // yeniden yazılmalı. Kalemler (order_items) için ayrıca `orders/{id}`
    // (OrderController::show) çağrısı gerekebilir (board muhtemelen özet
    // döner, kalem detayını değil) — TODO.
    let items = extract_array(&resp.body, "orders");
    let now = Utc::now().to_rfc3339();

    for item in &items {
        let server_id = item.get("id").and_then(Value::as_i64).unwrap_or(0);
        let tenant_id = item.get("tenant_id").and_then(Value::as_i64).unwrap_or(0);
        let branch_id = item.get("branch_id").and_then(Value::as_i64).unwrap_or(0);
        let table_id = item.get("table_id").and_then(Value::as_i64);
        let status = item.get("status").and_then(Value::as_str).unwrap_or("open");
        let total_minor = item.get("total_minor").and_then(Value::as_i64).unwrap_or(0);
        let currency = item.get("currency").and_then(Value::as_str).unwrap_or("TRY");
        let version = item.get("version").and_then(Value::as_i64).unwrap_or(0);
        let local_id = format!("srv-{server_id}"); // server kaynaklı satırlar icin deterministik local_id

        conn.execute(
            "INSERT INTO mirror_orders
                (local_id, server_id, tenant_id, branch_id, table_id, status, total_minor,
                 currency, version, origin, created_at, updated_at, synced_at)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, 'server', ?10, ?10, ?10)
             ON CONFLICT(local_id) DO UPDATE SET
                status = excluded.status,
                total_minor = excluded.total_minor,
                version = excluded.version,
                updated_at = excluded.updated_at,
                synced_at = excluded.synced_at",
            params![local_id, server_id, tenant_id, branch_id, table_id, status, total_minor, currency, version, now],
        )?;
    }

    Ok(items.len())
}

fn extract_array(body: &Value, key: &str) -> Vec<Value> {
    if let Some(arr) = body.get(key).and_then(Value::as_array) {
        return arr.clone();
    }
    if let Some(arr) = body.as_array() {
        return arr.clone();
    }
    Vec::new()
}

fn classify_status(status: u16) -> Result<(), PullError> {
    match status {
        200..=299 => Ok(()),
        401 | 302 | 419 => Err(PullError::Unauthenticated), // 419 = Laravel CSRF/oturum süresi
        _ => Err(PullError::ServerError(status)),
    }
}

fn set_meta(conn: &Connection, key: &str, value: &str) -> rusqlite::Result<()> {
    conn.execute(
        "INSERT INTO meta (key, value) VALUES (?1, ?2)
         ON CONFLICT(key) DO UPDATE SET value = excluded.value",
        params![key, value],
    )?;
    Ok(())
}
