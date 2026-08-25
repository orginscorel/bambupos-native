//! Senkron alt-sistemi: PULL (sunucu -> yerel ayna) + kuyruk oynatma
//! (yerel niyet -> sunucu, idempotent). bkz. desktop/SYNC.md için akışın
//! nesir anlatımı, docs/offline-sync-protocol.md için sunucu sözleşmesi.

pub mod client;
pub mod pull;
pub mod queue;
pub mod replay;

use rusqlite::Connection;

use client::ApiClient;

pub struct SyncCycleSummary {
    pub replay: replay::ReplaySummary,
    pub pull: Result<pull::PullSummary, pull::PullError>,
}

/// Tek bir "yeniden bağlandık" turu: ÖNCE yerel niyetleri sunucuya oynat
/// (kuyruk küçülsün, sunucudaki durum güncel niyetleri yansıtsın), SONRA
/// tazele PULL et (kendi gönderdiklerimiz dahil en güncel görünüm iner).
/// Bu sıra bilinçli: tersi olsaydı (önce pull) az önce kuyruğa attığımız
/// işlemi henüz görmeyen bir görünümü çekip UI'da kısa süreliğine "geri
/// gitmiş" gösterebilirdik.
///
/// Bağlantı sırasında connectivity coptuğunda: `replay_queue` içindeki her
/// op kendi hata sınıflandırmasını yapar (bkz. replay.rs) — burada ekstra
/// try/catch yok, `pull` kısmı ayrı `Result` olarak taşınır ki replay
/// başarılı olsa bile pull ağ hatası verirse çağıran taraf (main.rs döngüsü)
/// bunu ayırt edebilsin.
pub async fn run_cycle(conn: &Connection, api: &ApiClient) -> anyhow::Result<SyncCycleSummary> {
    let replay_summary = replay::replay_queue(conn, api).await?;
    let pull_summary = pull::delta_pull(conn, api).await;

    Ok(SyncCycleSummary {
        replay: replay_summary,
        pull: pull_summary,
    })
}
