//! Yerel SQLite ayna veritabanının açılışı ve şema uygulaması.
//!
//! İSKELET: `schema.sql` idempotent `CREATE TABLE IF NOT EXISTS` ifadeleri
//! içerir; bugün yalnız TEK SEFER (ilk açılışta) uygulanır. Şema
//! değiştiğinde geriye dönük göç YOK — TODO (bkz. migrations/schema.sql
//! başlığındaki not): numaralı migration dosyalarına geçiş gerekecek.

use std::path::PathBuf;

use rusqlite::Connection;

const SCHEMA_SQL: &str = include_str!("../migrations/schema.sql");

/// `app_data_dir`/bambumpos.sqlite3 içinde açar (yoksa oluşturur), şemayı
/// uygular ve bağlantıyı döner.
///
/// `data_dir`: Tauri'nin platform-özel uygulama veri dizini
/// (`tauri::Manager::path().app_data_dir()`), main.rs içinde çözülüp buraya
/// verilir — bu modül Tauri'ye doğrudan bağımlı OLMASIN diye (test edilebilirlik).
pub fn open(data_dir: PathBuf) -> anyhow::Result<Connection> {
    std::fs::create_dir_all(&data_dir)?;
    let db_path = data_dir.join("bambumpos.sqlite3");

    let conn = Connection::open(db_path)?;

    // WAL: aynı anda okuma (UI listesi) + yazma (senkron replay) kilitlenmesin.
    conn.pragma_update(None, "journal_mode", "WAL")?;
    conn.pragma_update(None, "foreign_keys", "ON")?;

    conn.execute_batch(SCHEMA_SQL)?;

    Ok(conn)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn acilis_semayi_hatasiz_uygular() {
        let conn = Connection::open_in_memory().expect("in-memory ac");
        conn.execute_batch(SCHEMA_SQL).expect("sema uygulanmali");

        let count: i64 = conn
            .query_row(
                "SELECT count(*) FROM sqlite_master WHERE type = 'table' AND name = 'pending_ops'",
                [],
                |row| row.get(0),
            )
            .expect("pending_ops tablosu bulunmali");
        assert_eq!(count, 1);
    }
}
