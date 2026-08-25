//! `pending_ops` kuyruğu — CRUD yardımcıları.
//!
//! Tasarım kararları için bkz. docs/offline-sync-protocol.md ve
//! migrations/schema.sql (`pending_ops` tablo yorumu). Burada YALNIZ
//! sqlite okuma/yazma var; sunucuya oynatma mantığı `sync::replay` içinde.

use chrono::Utc;
use rusqlite::{params, Connection, OptionalExtension};
use serde_json::Value;
use uuid::Uuid;

#[derive(Debug, Clone)]
pub struct PendingOp {
    pub op_id: String,
    pub scope: String,
    pub endpoint: String,
    pub method: String,
    pub payload_json: String,
    pub order_local_id: Option<String>,
    pub tries: i64,
}

/// Yeni bir operasyonu kuyruğa ekler. `op_id` BURADA üretilir — protokol
/// gereği bu, kullanıcının eylemi TETİKLEDİĞİ an (ağ isteğinden ÇOK ÖNCE,
/// hatta hiç ağ yokken) olmalı; yani çağıran taraf (commands.rs) bunu
/// kullanıcı butona bastığı anda çağırmalı, "senkron zamanı" beklenmemeli.
pub fn enqueue(
    conn: &Connection,
    scope: &str,
    endpoint: &str,
    method: &str,
    payload: &Value,
    order_local_id: Option<&str>,
) -> anyhow::Result<String> {
    let op_id = Uuid::new_v4().to_string();
    let now = Utc::now().to_rfc3339();

    conn.execute(
        "INSERT INTO pending_ops
            (op_id, scope, endpoint, method, payload_json, order_local_id, created_at, status, tries)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, 'pending', 0)",
        params![
            op_id,
            scope,
            endpoint,
            method,
            payload.to_string(),
            order_local_id,
            now,
        ],
    )?;

    Ok(op_id)
}

/// Sıralı-teslim (protokol §2.4): oluşturulma sırasına göre, `pending`
/// durumundaki satırlar. NOT: bu fonksiyon TÜM kuyruğu tek seferde okur —
/// büyük kuyruklarda (binlerce satır) sayfalama gerekebilir (TODO, bugün
/// hacim düşük olduğu için basit tutuldu).
pub fn fetch_pending(conn: &Connection) -> anyhow::Result<Vec<PendingOp>> {
    let mut stmt = conn.prepare(
        "SELECT op_id, scope, endpoint, method, payload_json, order_local_id, tries
         FROM pending_ops
         WHERE status = 'pending'
         ORDER BY created_at ASC, rowid ASC",
    )?;

    let rows = stmt
        .query_map([], |row| {
            Ok(PendingOp {
                op_id: row.get(0)?,
                scope: row.get(1)?,
                endpoint: row.get(2)?,
                method: row.get(3)?,
                payload_json: row.get(4)?,
                order_local_id: row.get(5)?,
                tries: row.get(6)?,
            })
        })?
        .collect::<Result<Vec<_>, _>>()?;

    Ok(rows)
}

pub fn count_pending(conn: &Connection) -> anyhow::Result<i64> {
    let count: i64 = conn.query_row(
        "SELECT count(*) FROM pending_ops WHERE status = 'pending'",
        [],
        |row| row.get(0),
    )?;
    Ok(count)
}

/// Sunucu işlemi TAM BİR KEZ kabul etti (201) ya da daha önce işlenmişi
/// (200 replayed=true) aynen döndü — iki durumda da kuyruktan güvenle
/// SİLİNİR (protokol §2.3).
pub fn remove(conn: &Connection, op_id: &str) -> anyhow::Result<()> {
    conn.execute("DELETE FROM pending_ops WHERE op_id = ?1", params![op_id])?;
    Ok(())
}

/// Geçici hata (ağ/5xx/timeout) — satır KALIR, `tries` artar, `last_error`
/// güncellenir; bir sonraki `replay_queue` turunda AYNI op_id ile tekrar
/// denenir (protokol §2.3 son madde).
pub fn mark_retry(conn: &Connection, op_id: &str, error: &str) -> anyhow::Result<()> {
    let now = Utc::now().to_rfc3339();
    conn.execute(
        "UPDATE pending_ops
         SET tries = tries + 1, last_error = ?2, last_tried_at = ?3, status = 'pending'
         WHERE op_id = ?1",
        params![op_id, error, now],
    )?;
    Ok(())
}

/// Kalıcı hata (4xx validasyon/yetki, ya da op_id çakışması 409-farklı-gövde)
/// — protokole göre kuyruktan SİLİNMELİ + kullanıcıya GÖSTERİLMELİ. Silmeden
/// önce `failed_ops` tablosuna taşınır ki uygulama o an kapalıysa/kullanıcı
/// başka ekrandaysa hata kaybolmasın (bu tablo protokol dokümanında YOK —
/// burada "kullanıcıya göster" gereksinimini karşılamak için EKLENDİ, bkz.
/// SYNC.md "minimum sözleşmenin ötesinde eklenenler").
pub fn mark_failed_permanent(conn: &Connection, op: &PendingOp, error: &str) -> anyhow::Result<()> {
    let now = Utc::now().to_rfc3339();
    conn.execute(
        "INSERT INTO failed_ops (op_id, scope, endpoint, method, payload_json, order_local_id, failed_at, error)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)",
        params![
            op.op_id,
            op.scope,
            op.endpoint,
            op.method,
            op.payload_json,
            op.order_local_id,
            now,
            error,
        ],
    )?;
    remove(conn, &op.op_id)?;
    Ok(())
}

pub fn find(conn: &Connection, op_id: &str) -> anyhow::Result<Option<PendingOp>> {
    conn.query_row(
        "SELECT op_id, scope, endpoint, method, payload_json, order_local_id, tries
         FROM pending_ops WHERE op_id = ?1",
        params![op_id],
        |row| {
            Ok(PendingOp {
                op_id: row.get(0)?,
                scope: row.get(1)?,
                endpoint: row.get(2)?,
                method: row.get(3)?,
                payload_json: row.get(4)?,
                order_local_id: row.get(5)?,
                tries: row.get(6)?,
            })
        },
    )
    .optional()
    .map_err(Into::into)
}
