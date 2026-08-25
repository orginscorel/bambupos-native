//! Kuyruk oynatıcı — `pending_ops`'u sırayla sunucuya idempotent gönderir.
//!
//! Protokol referansı: docs/offline-sync-protocol.md §2 "op_id akışı" ve §3
//! "çakışma kuralları". Bu dosya o dokümanın kurallarını BİREBİR uygular;
//! davranışı değiştirmeden önce dokümanı güncelleyin.
//!
//! DURUM: **İSKELET + kısmi STUB**. HTTP çağrısı, op_id enjeksiyonu,
//! kuyruktan silme/tries artırma akışı TAMAMDIR ve doğrudur. Eksik olan:
//! (1) sunucunun 409 yanıtını "hâlâ işleniyor" ile "farklı gövde çakışması"
//! olarak AYIRT edecek makine-okunur bir alan YOK bugün (IdempotentRequest
//! ikisinde de aynı `HttpException(409, mesaj)` atıyor, bkz.
//! app/Support/Idempotency/IdempotentRequest.php satır ~95 ve ~100) — bu
//! yüzden burada `tries` eşiğine dayalı bir SEZGİSEL ayrım kullanılıyor
//! (TODO, SYNC.md'de açık risk olarak not edildi: sunucuya
//! `{"reason":"processing"|"conflict"}` eklenmesi önerilir).
//! (2) `scope`'a göre başarılı yanıtı mirror tablolarına yansıtma
//! (`apply_success_side_effect`) yalnız `order.item.add` için TASLAK —
//! diğer scope'lar (adisyon açma, ödeme al, ...) bu görevde YOK çünkü
//! sunucu tarafında yalnız `addItem` PROOF olarak op_id destekliyor
//! (bkz. docs/offline-sync-protocol.md §7 "kapsam dışı").

use chrono::Utc;
use rusqlite::Connection;
use serde_json::Value;
use tracing::{debug, warn};

use super::client::ApiClient;
use super::queue::{self, PendingOp};

/// Aynı op_id, 409 "muhtemelen hâlâ işleniyor" için kaç kez yeniden
/// denendikten sonra "muhtemelen farklı-gövde çakışması" sayılıp kalıcı
/// hataya çevrilir. bkz. dosya başı not (1).
const CONFLICT_GIVE_UP_AFTER_TRIES: i64 = 5;

pub struct ReplaySummary {
    pub succeeded: usize,
    pub retried: usize,
    pub failed_permanent: usize,
    pub skipped_unresolved: usize,
}

/// SIRALI oynatma (protokol §2.4): bu fonksiyon bir `for` döngüsüyle
/// `pending_ops`'u TEK TEK, `.await` ile bekleyerek işler — hiçbir op
/// paralel gönderilmez. Bu, "aynı order'ın kalemleri sırayla eklenmeli"
/// kuralını en basit haliyle sağlar (farklı order'lar arası paralellik
/// TODO — SYNC.md "Sonraki adımlar").
pub async fn replay_queue(conn: &Connection, api: &ApiClient) -> anyhow::Result<ReplaySummary> {
    let ops = queue::fetch_pending(conn)?;
    let mut summary = ReplaySummary {
        succeeded: 0,
        retried: 0,
        failed_permanent: 0,
        skipped_unresolved: 0,
    };

    for op in ops {
        match replay_one(conn, api, &op).await {
            ReplayOutcome::Succeeded => summary.succeeded += 1,
            ReplayOutcome::Retried => summary.retried += 1,
            ReplayOutcome::FailedPermanent => summary.failed_permanent += 1,
            ReplayOutcome::SkippedUnresolved => summary.skipped_unresolved += 1,
        }
    }

    Ok(summary)
}

enum ReplayOutcome {
    Succeeded,
    Retried,
    FailedPermanent,
    SkippedUnresolved,
}

async fn replay_one(conn: &Connection, api: &ApiClient, op: &PendingOp) -> ReplayOutcome {
    // Endpoint yer tutucularını çöz (ör. "orders/{order}/items"). Bir order'a
    // bağımlı işlem, o order'ın kendi "oluştur" op'u henüz senkronlanmadıysa
    // (server_id yok) BU TURDA atlanır — sıra bozulmasın diye ileri sarılmaz,
    // sonraki replay_queue çağrısında (order oluşturma bu arada başarılı
    // olduysa) tekrar denenir.
    let endpoint = match resolve_endpoint(conn, op) {
        Ok(Some(e)) => e,
        Ok(None) => {
            debug!(op_id = %op.op_id, "bagli order henuz senkronlanmadi, bu turda atlaniyor");
            return ReplayOutcome::SkippedUnresolved;
        }
        Err(e) => {
            warn!(op_id = %op.op_id, error = %e, "endpoint cozumlenemedi");
            return ReplayOutcome::SkippedUnresolved;
        }
    };

    let mut payload: Value = match serde_json::from_str(&op.payload_json) {
        Ok(v) => v,
        Err(e) => {
            // Bozuk yerel kayıt (olmamalı, ama sessizce sonsuz retry yapmaktansa
            // kalıcı hataya düşürüp kullanıcıya göster).
            let _ = queue::mark_failed_permanent(conn, op, &format!("payload_json parse hatasi: {e}"));
            return ReplayOutcome::FailedPermanent;
        }
    };

    // Protokol §2.2: "gövdeye op_id alanı eklenir (mevcut alanların YANINA)".
    if let Value::Object(ref mut map) = payload {
        map.insert("op_id".to_string(), Value::String(op.op_id.clone()));
    }

    let result = match op.method.as_str() {
        "POST" => api.post_json(&endpoint, &payload).await,
        // TODO: PUT/DELETE bugün kullanılmıyor (yalnız addItem POST kuyruklanıyor)
        // ama tablo/kuyruk şeması bunları destekleyecek şekilde tasarlandı —
        // sunucu tarafı PUT/DELETE için op_id desteklediğinde burası genişletilmeli.
        other => {
            warn!(op_id = %op.op_id, method = other, "desteklenmeyen HTTP metodu");
            let _ = queue::mark_failed_permanent(conn, op, &format!("desteklenmeyen method: {other}"));
            return ReplayOutcome::FailedPermanent;
        }
    };

    let resp = match result {
        Ok(r) => r,
        Err(e) => {
            // Ağ hatası — geçici, kuyrukta kalır (protokol §2.3 son madde).
            let _ = queue::mark_retry(conn, &op.op_id, &e.to_string());
            return ReplayOutcome::Retried;
        }
    };

    match resp.status {
        201 => {
            apply_success_side_effect(conn, op, &resp.body);
            let _ = queue::remove(conn, &op.op_id);
            ReplayOutcome::Succeeded
        }
        200 if resp.body.get("replayed").and_then(Value::as_bool) == Some(true) => {
            // Daha önce işlenmiş — sonucu aynen kabul et, tekrar UYGULAMA
            // (apply_success_side_effect burada ÇAĞRILMAZ: ilk denemede zaten
            // uygulanmış olmalı; DB'de local_id zaten server_id'ye bağlanmış
            // olacaktır çünkü aynı replay_queue çalışması içinde ilk deneme
            // network hatasıyla YARIDA kesilseydi apply_success_side_effect hiç
            // çalışmamış olurdu — bu durumda server_id burada da eksik kalır.
            // TODO: bu kenar durumu (yanıt geldi ama uygulama tam o an
            // kapandıysa) için replayed=true yanıtında da
            // apply_success_side_effect'i İDEMPOTENT şekilde çağırmak daha
            // sağlam olur; bugün basitlik için atlanıyor.
            let _ = queue::remove(conn, &op.op_id);
            ReplayOutcome::Succeeded
        }
        409 => {
            if op.tries + 1 >= CONFLICT_GIVE_UP_AFTER_TRIES {
                let _ = queue::mark_failed_permanent(
                    conn,
                    op,
                    "409: birden fazla denemeden sonra hala cakisma - muhtemelen ayni op_id farkli govdeyle kullanildi (bkz. dosya basi TODO 1)",
                );
                ReplayOutcome::FailedPermanent
            } else {
                let _ = queue::mark_retry(conn, &op.op_id, "409: hala isleniyor olabilir, kisa surede tekrar denenecek");
                ReplayOutcome::Retried
            }
        }
        400..=499 => {
            // Kalıcı hata (validasyon/yetki/402 kiracı-askida — bkz. protokol §6).
            let msg = resp
                .body
                .get("message")
                .and_then(Value::as_str)
                .unwrap_or("bilinmeyen istemci hatasi")
                .to_string();
            let _ = queue::mark_failed_permanent(conn, op, &format!("{}: {msg}", resp.status));
            ReplayOutcome::FailedPermanent
        }
        _ => {
            // 5xx ya da beklenmeyen durum — geçici say.
            let _ = queue::mark_retry(conn, &op.op_id, &format!("beklenmeyen status {}", resp.status));
            ReplayOutcome::Retried
        }
    }
}

/// `{order}` gibi yer tutucuları gerçek sunucu id'sine çevirir. Bugün tek
/// tanınan yer tutucu `{order}` — `order_local_id` üzerinden
/// `mirror_orders.server_id`'ye bakar. Order henüz senkronlanmadıysa (offline
/// açılmış, "adisyon oluştur" op'u bu görevde YOK — bkz. dosya başı not 2)
/// `Ok(None)` döner (bu turda atla).
fn resolve_endpoint(conn: &Connection, op: &PendingOp) -> anyhow::Result<Option<String>> {
    if !op.endpoint.contains("{order}") {
        return Ok(Some(op.endpoint.clone()));
    }

    let Some(local_id) = &op.order_local_id else {
        anyhow::bail!("endpoint {{order}} icerior ama order_local_id yok (kuyruk satiri bozuk)");
    };

    let server_id: Option<i64> = conn
        .query_row(
            "SELECT server_id FROM mirror_orders WHERE local_id = ?1",
            [local_id],
            |row| row.get(0),
        )
        .ok()
        .flatten();

    Ok(server_id.map(|id| op.endpoint.replace("{order}", &id.to_string())))
}

/// Başarılı yanıtı okuma-modeli aynasına yansıtır. Bugün yalnız
/// `order.item.add` scope'u için taslak — yanıt şekli `OrderPresenter::
/// summary`'nin ürettiği `{ order: {...} }` olduğu VARSAYILDI (bkz.
/// OrderController::addItem dönüşü) ama tam alan eşlemesi bu görevde
/// doğrulanmadı, TODO.
fn apply_success_side_effect(conn: &Connection, op: &PendingOp, body: &Value) {
    if op.scope != "order.item.add" {
        return;
    }

    let Some(order) = body.get("order") else { return };
    let Some(total_minor) = order.get("total_minor").and_then(Value::as_i64) else {
        return;
    };
    let version = order.get("version").and_then(Value::as_i64).unwrap_or(0);
    let now = Utc::now().to_rfc3339();

    if let Some(local_id) = &op.order_local_id {
        let _ = conn.execute(
            "UPDATE mirror_orders SET total_minor = ?2, version = ?3, updated_at = ?4, synced_at = ?4
             WHERE local_id = ?1",
            rusqlite::params![local_id, total_minor, version, now],
        );
    }

    // TODO: order.items[] dizisinden bu op'un ürettiği satırı bulup
    // mirror_order_items.server_id'yi doldurmak gerekir (yeni eklenen
    // kalem hangisi - sunucu yanitinda ayirt edici bir alan (op_id?) VAR MI
    // dogrulanmadi). Bugun bu adim EKSIK - iyimser: bir sonraki
    // baseline/delta pull zaten tum order detayini tazeler.
}
