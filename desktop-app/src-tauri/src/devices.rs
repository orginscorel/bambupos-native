//! CİHAZ KÖPRÜSÜ — ÖKC, termal/fiş yazıcıları ve ağdaki cihazlar.
//!
//! Tarayıcı yerel ağı tarayamaz ve ham TCP açamaz; bu yüzden bu işler
//! masaüstü uygulamasının native tarafında yapılır ve panele komut olarak
//! sunulur. Panel `window.__TAURI__` varsa bu komutları çağırır, yoksa
//! (saf tarayıcıda) yalnız WebUSB/Web Serial yolunu kullanır.
//!
//! Tasarım kuralı: DIŞ BAĞIMLILIK YOK. Yazıcı listesi ve seri port keşfi
//! işletim sisteminin kendi araçlarıyla yapılır (lpstat/PowerShell), ağ
//! taraması std::net ile. Böylece üç platformda da derleme kırılmaz.

use std::collections::HashMap;
use std::io::Write;
use std::net::{IpAddr, Ipv4Addr, SocketAddr, TcpStream, UdpSocket};
use std::process::Command;
use std::sync::mpsc;
use std::time::Duration;

use serde::Serialize;

/// Bulunan bir cihaz. `kind` panelin rol atamasında kullandığı ayrım.
#[derive(Debug, Clone, Serialize)]
pub struct Device {
    /// "os_printer" | "network" | "serial"
    pub kind: String,
    /// Kullanıcıya gösterilen ad
    pub name: String,
    /// Bağlantı adresi: yazıcı adı, "ip:port" ya da seri port yolu
    pub address: String,
    /// Ek bilgi (üretici, model, port durumu…)
    pub detail: Option<String>,
}

/// İşletim sistemine KURULU yazıcılar.
/// Windows'ta PowerShell `Get-Printer`, diğerlerinde CUPS `lpstat -a`.
#[tauri::command]
pub fn list_os_printers() -> Vec<Device> {
    let mut out = Vec::new();

    #[cfg(target_os = "windows")]
    {
        let res = Command::new("powershell")
            .args([
                "-NoProfile",
                "-Command",
                "Get-Printer | Select-Object -ExpandProperty Name",
            ])
            .output();
        if let Ok(o) = res {
            for line in String::from_utf8_lossy(&o.stdout).lines() {
                let n = line.trim();
                if !n.is_empty() {
                    out.push(Device {
                        kind: "os_printer".into(),
                        name: n.to_string(),
                        address: n.to_string(),
                        detail: Some("Windows yazıcısı".into()),
                    });
                }
            }
        }
    }

    #[cfg(not(target_os = "windows"))]
    {
        // `lpstat -a` çıktısı: "<yazici_adi> accepting requests since ..."
        if let Ok(o) = Command::new("lpstat").arg("-a").output() {
            for line in String::from_utf8_lossy(&o.stdout).lines() {
                if let Some(name) = line.split_whitespace().next() {
                    if !name.is_empty() {
                        out.push(Device {
                            kind: "os_printer".into(),
                            name: name.to_string(),
                            address: name.to_string(),
                            detail: Some("CUPS yazıcısı".into()),
                        });
                    }
                }
            }
        }
    }

    out
}

/// Seri portlar (ÖKC ve seri termal yazıcılar bu yolla bağlanır).
#[tauri::command]
pub fn list_serial_ports() -> Vec<Device> {
    let mut out = Vec::new();

    #[cfg(target_os = "windows")]
    {
        let res = Command::new("powershell")
            .args([
                "-NoProfile",
                "-Command",
                "[System.IO.Ports.SerialPort]::getportnames()",
            ])
            .output();
        if let Ok(o) = res {
            for line in String::from_utf8_lossy(&o.stdout).lines() {
                let p = line.trim();
                if !p.is_empty() {
                    out.push(Device {
                        kind: "serial".into(),
                        name: p.to_string(),
                        address: p.to_string(),
                        detail: Some("Seri port".into()),
                    });
                }
            }
        }
    }

    #[cfg(not(target_os = "windows"))]
    {
        // USB-seri dönüştürücüler ve yerleşik portlar.
        let patterns = ["/dev/tty.usbserial", "/dev/tty.usbmodem", "/dev/ttyUSB", "/dev/ttyACM", "/dev/ttyS"];
        if let Ok(entries) = std::fs::read_dir("/dev") {
            for e in entries.flatten() {
                let path = e.path();
                let s = path.to_string_lossy().to_string();
                if patterns.iter().any(|p| s.starts_with(p)) {
                    out.push(Device {
                        kind: "serial".into(),
                        name: s.rsplit('/').next().unwrap_or(&s).to_string(),
                        address: s.clone(),
                        detail: Some("Seri port".into()),
                    });
                }
            }
        }
    }

    out.sort_by(|a, b| a.address.cmp(&b.address));
    out
}

/// Bu makinenin yerel IPv4 adresi (ağ taramasının başlangıç noktası).
/// Dış dünyaya paket GÖNDERMEZ — UDP soketi yalnız yönlendirme tablosundan
/// hangi arayüzün kullanılacağını öğrenmek için "bağlanır".
fn local_ipv4() -> Option<Ipv4Addr> {
    let sock = UdpSocket::bind("0.0.0.0:0").ok()?;
    sock.connect("8.8.8.8:80").ok()?;
    match sock.local_addr().ok()?.ip() {
        IpAddr::V4(v4) => Some(v4),
        _ => None,
    }
}

/// AYNI AĞI TARA: /24 ağındaki 254 adresi verilen portlarda dener.
///
/// Varsayılan portlar: 9100 (RAW/JetDirect — termal ve fiş yazıcılarının
/// standart portu), 631 (IPP), 515 (LPD). ÖKC cihazları da çoğunlukla
/// 9100 ya da üreticiye özel bir port dinler; ek port verilebilir.
///
/// Tarama paralel yapılır (her adres için kısa zaman aşımı), aksi hâlde
/// 254 adres × 3 port sırayla denenince dakikalar sürerdi.
#[tauri::command]
pub fn scan_network(ports: Option<Vec<u16>>, timeout_ms: Option<u64>) -> Vec<Device> {
    let ports = ports.unwrap_or_else(|| vec![9100, 631, 515]);
    let timeout = Duration::from_millis(timeout_ms.unwrap_or(300));

    let Some(me) = local_ipv4() else {
        return Vec::new();
    };
    let o = me.octets();

    let (tx, rx) = mpsc::channel::<Device>();
    let mut handles = Vec::new();

    for host in 1u8..=254 {
        let ip = Ipv4Addr::new(o[0], o[1], o[2], host);
        let ports = ports.clone();
        let tx = tx.clone();
        handles.push(std::thread::spawn(move || {
            for p in ports {
                let addr = SocketAddr::from((ip, p));
                if TcpStream::connect_timeout(&addr, timeout).is_ok() {
                    let label = match p {
                        9100 => "RAW/ESC-POS yazıcı (9100)",
                        631 => "IPP yazıcı (631)",
                        515 => "LPD yazıcı (515)",
                        _ => "Açık port",
                    };
                    let _ = tx.send(Device {
                        kind: "network".into(),
                        name: format!("{ip}:{p}"),
                        address: format!("{ip}:{p}"),
                        detail: Some(label.into()),
                    });
                }
            }
        }));
    }
    drop(tx);

    let mut found: Vec<Device> = rx.iter().collect();
    for h in handles {
        let _ = h.join();
    }

    found.sort_by(|a, b| a.address.cmp(&b.address));
    found
}

/// AĞ YAZICISINA ham bayt gönder (ESC/POS fiş, ÖKC komutu…).
/// Baytlar panelden sayı dizisi olarak gelir; metin dönüşümü panelde yapılır
/// (Türkçe karakter haritası orada tanımlı, iki yerde tutulmaz).
#[tauri::command]
pub fn raw_print_network(host: String, port: u16, bytes: Vec<u8>) -> Result<String, String> {
    let addr = format!("{host}:{port}");
    let sock: SocketAddr = addr.parse().map_err(|_| format!("Geçersiz adres: {addr}"))?;
    let mut stream = TcpStream::connect_timeout(&sock, Duration::from_millis(2500))
        .map_err(|e| format!("Bağlanılamadı ({addr}): {e}"))?;
    stream
        .set_write_timeout(Some(Duration::from_millis(4000)))
        .ok();
    stream
        .write_all(&bytes)
        .map_err(|e| format!("Yazdırılamadı: {e}"))?;
    stream.flush().map_err(|e| format!("Gönderilemedi: {e}"))?;
    Ok(format!("{} bayt gönderildi → {}", bytes.len(), addr))
}

/// İŞLETİM SİSTEMİ YAZICISINA ham bayt gönder.
/// Unix'te `lp -o raw`, Windows'ta paylaşılan yazıcıya doğrudan kopyalama.
#[tauri::command]
pub fn raw_print_os(printer: String, bytes: Vec<u8>) -> Result<String, String> {
    use std::io::Write as _;

    let tmp = std::env::temp_dir().join("bambumpos-print.bin");
    std::fs::write(&tmp, &bytes).map_err(|e| format!("Geçici dosya yazılamadı: {e}"))?;

    #[cfg(target_os = "windows")]
    let res = Command::new("cmd")
        .args(["/C", "copy", "/B", &tmp.to_string_lossy(), &format!("\\\\localhost\\{printer}")])
        .output();

    #[cfg(not(target_os = "windows"))]
    let res = Command::new("lp")
        .args(["-d", &printer, "-o", "raw", &tmp.to_string_lossy()])
        .output();

    match res {
        Ok(o) if o.status.success() => Ok(format!("{} bayt gönderildi → {}", bytes.len(), printer)),
        Ok(o) => {
            let err = String::from_utf8_lossy(&o.stderr).trim().to_string();
            Err(if err.is_empty() { "Yazdırma başarısız".into() } else { err })
        }
        Err(e) => Err(format!("Yazdırma komutu çalıştırılamadı: {e}")),
    }
}

/// Tek adres/port'un ulaşılabilirliğini sınar ("test bağlantısı" düğmesi).
#[tauri::command]
pub fn probe_device(host: String, port: u16, timeout_ms: Option<u64>) -> Result<bool, String> {
    let addr = format!("{host}:{port}");
    let sock: SocketAddr = addr.parse().map_err(|_| format!("Geçersiz adres: {addr}"))?;
    let t = Duration::from_millis(timeout_ms.unwrap_or(1200));
    Ok(TcpStream::connect_timeout(&sock, t).is_ok())
}

/// Köprünün varlığını ve ortamını bildirir (panel "native mod" rozetini
/// buna bakarak gösterir).
#[tauri::command]
pub fn bridge_info() -> HashMap<String, String> {
    let mut m = HashMap::new();
    m.insert("bridge".into(), "bambumpos-desktop".into());
    m.insert("version".into(), env!("CARGO_PKG_VERSION").to_string());
    m.insert("os".into(), std::env::consts::OS.to_string());
    m.insert("arch".into(), std::env::consts::ARCH.to_string());
    if let Some(ip) = local_ipv4() {
        m.insert("local_ip".into(), ip.to_string());
    }
    m
}
