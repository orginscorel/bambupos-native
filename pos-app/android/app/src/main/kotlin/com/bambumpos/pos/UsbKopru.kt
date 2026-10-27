package com.bambumpos.pos

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbEndpoint
import android.hardware.usb.UsbInterface
import android.hardware.usb.UsbManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/**
 * USB'ye takılı fiş yazıcısı / kart POS cihazları.
 *
 *  - liste: takılı cihazlar (vid, pid, sınıflar, üretici, ürün, izin)
 *  - izinIste: sistem izin penceresi (PendingIntent, Android 12+ FLAG_MUTABLE)
 *  - yaz: ESC/POS baytını bulk OUT ucuna parça parça gönderir (arka planda)
 *  - olay: takma / çıkarma → Dart listeyi yeniler
 *
 * Bütün USB G/Ç tek arka plan iş parçacığında; yanıt ana iş parçacığından.
 */
class UsbKopru(private val ctx: Context, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private val usb = ctx.getSystemService(Context.USB_SERVICE) as UsbManager
    private val isci = Executors.newSingleThreadExecutor()
    private val ana = Handler(Looper.getMainLooper())
    private val kanal = MethodChannel(messenger, "bambumpos/usb")
    private val olayKanali = EventChannel(messenger, "bambumpos/usb/olay")
    private var olay: EventChannel.EventSink? = null
    private val bekleyenIzin = HashMap<String, MutableList<MethodChannel.Result>>()
    private val izinEylemi = ctx.packageName + ".USB_IZIN"

    private val takCikar = object : BroadcastReceiver() {
        override fun onReceive(c: Context, i: Intent) = degisti()
    }

    private val izinAlici = object : BroadcastReceiver() {
        override fun onReceive(c: Context, i: Intent) {
            if (i.action != izinEylemi) return
            val aygit: UsbDevice? = if (Build.VERSION.SDK_INT >= 33) {
                i.getParcelableExtra(UsbManager.EXTRA_DEVICE, UsbDevice::class.java)
            } else {
                @Suppress("DEPRECATION") i.getParcelableExtra(UsbManager.EXTRA_DEVICE)
            }
            val verildi = i.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)
            val ad = aygit?.deviceName
            // Aygıt bilgisi gelmezse bekleyen tüm istekler sonuçlanır.
            val bekleyen = if (ad != null) listOfNotNull(bekleyenIzin.remove(ad)) else bekleyenIzin.values.toList().also { bekleyenIzin.clear() }
            for (liste in bekleyen) for (r in liste) r.success(verildi || (aygit != null && usb.hasPermission(aygit)))
            degisti()
        }
    }

    init {
        kanal.setMethodCallHandler(this)
        olayKanali.setStreamHandler(this)
        val f = IntentFilter().apply {
            addAction(UsbManager.ACTION_USB_DEVICE_ATTACHED)
            addAction(UsbManager.ACTION_USB_DEVICE_DETACHED)
        }
        if (Build.VERSION.SDK_INT >= 33) {
            ctx.registerReceiver(takCikar, f, Context.RECEIVER_EXPORTED)
            ctx.registerReceiver(izinAlici, IntentFilter(izinEylemi), Context.RECEIVER_NOT_EXPORTED)
        } else {
            ctx.registerReceiver(takCikar, f)
            ctx.registerReceiver(izinAlici, IntentFilter(izinEylemi))
        }
    }

    fun kapat() {
        try { ctx.unregisterReceiver(takCikar) } catch (_: Exception) {}
        try { ctx.unregisterReceiver(izinAlici) } catch (_: Exception) {}
        kanal.setMethodCallHandler(null)
        olayKanali.setStreamHandler(null)
        for (liste in bekleyenIzin.values) for (r in liste) r.success(false)
        bekleyenIzin.clear()
        isci.shutdown()
    }

    fun degisti() {
        ana.post { olay?.success("degisti") }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { olay = events }
    override fun onCancel(arguments: Any?) { olay = null }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "liste" -> arkada(result) { liste() }
            "izinIste" -> izinIste(call.argument<String>("ad"), result)
            "yaz" -> {
                val ad = call.argument<String>("ad")
                val veri = call.argument<ByteArray>("veri")
                val kopya = (call.argument<Int>("kopya") ?: 1).coerceIn(1, 5)
                if (ad == null || veri == null) {
                    result.error("ARGUMAN", "aygıt / veri yok", null)
                    return
                }
                isci.execute {
                    try {
                        yaz(ad, veri, kopya)
                        ana.post { result.success(null) }
                    } catch (e: UsbHatasi) {
                        ana.post { result.error(e.kod, e.message, null) }
                    } catch (e: Exception) {
                        ana.post { result.error("HATA", e.message ?: e.javaClass.simpleName, null) }
                    }
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun arkada(result: MethodChannel.Result, is_: () -> Any?) {
        isci.execute {
            try {
                val r = is_()
                ana.post { result.success(r) }
            } catch (e: Exception) {
                ana.post { result.error("HATA", e.message ?: e.javaClass.simpleName, null) }
            }
        }
    }

    private fun liste(): List<Map<String, Any?>> = usb.deviceList.values.map { d ->
        val izin = usb.hasPermission(d)
        val siniflar = ArrayList<Int>()
        siniflar.add(d.deviceClass)
        for (i in 0 until d.interfaceCount) siniflar.add(d.getInterface(i).interfaceClass)
        mapOf(
            "ad" to d.deviceName,
            "vid" to d.vendorId,
            "pid" to d.productId,
            "uretici" to guvenli { d.manufacturerName },
            "urun" to guvenli { d.productName },
            // Android 10+: seri numarası yalnız izinle okunur.
            "seri" to if (izin) guvenli { d.serialNumber } else null,
            "siniflar" to siniflar,
            "izin" to izin,
            "bulkOut" to (yaziciUcu(d) != null),
        )
    }

    private fun <T> guvenli(f: () -> T?): T? = try { f() } catch (_: Exception) { null }

    private fun izinIste(ad: String?, result: MethodChannel.Result) {
        val d = usb.deviceList[ad ?: ""]
        if (d == null) {
            result.success(false)
            return
        }
        if (usb.hasPermission(d)) {
            result.success(true)
            return
        }
        val ilk = !bekleyenIzin.containsKey(d.deviceName)
        bekleyenIzin.getOrPut(d.deviceName) { ArrayList() }.add(result)
        if (!ilk) return
        try {
            var bayrak = PendingIntent.FLAG_UPDATE_CURRENT
            // Sistem EXTRA_DEVICE / EXTRA_PERMISSION_GRANTED ekleyebilsin diye değiştirilebilir;
            // Android 14+ değiştirilebilir PendingIntent açık (paketli) Intent ister.
            if (Build.VERSION.SDK_INT >= 31) bayrak = bayrak or PendingIntent.FLAG_MUTABLE
            val pi = PendingIntent.getBroadcast(ctx, 7301, Intent(izinEylemi).setPackage(ctx.packageName), bayrak)
            usb.requestPermission(d, pi)
        } catch (e: Exception) {
            bekleyenIzin.remove(d.deviceName)?.forEach { it.success(false) }
        }
    }

    /** Yazıcı arayüzü (sınıf 7) öncelikli; yoksa bulk OUT ucu olan ilk arayüz. */
    private fun yaziciUcu(d: UsbDevice): Pair<UsbInterface, UsbEndpoint>? {
        var yedek: Pair<UsbInterface, UsbEndpoint>? = null
        for (i in 0 until d.interfaceCount) {
            val arayuz = d.getInterface(i)
            for (e in 0 until arayuz.endpointCount) {
                val uc = arayuz.getEndpoint(e)
                if (uc.type == UsbConstants.USB_ENDPOINT_XFER_BULK && uc.direction == UsbConstants.USB_DIR_OUT) {
                    if (arayuz.interfaceClass == UsbConstants.USB_CLASS_PRINTER) return Pair(arayuz, uc)
                    if (yedek == null) yedek = Pair(arayuz, uc)
                }
            }
        }
        return yedek
    }

    private class UsbHatasi(val kod: String, mesaj: String) : Exception(mesaj)

    private fun yaz(ad: String, veri: ByteArray, kopya: Int) {
        val d = usb.deviceList[ad] ?: throw UsbHatasi("YOK", "USB yazıcı bağlı değil")
        if (!usb.hasPermission(d)) throw UsbHatasi("IZIN", "USB izni yok")
        val (arayuz, uc) = yaziciUcu(d) ?: throw UsbHatasi("ARAYUZ", "bulk OUT ucu yok")
        val baglanti = usb.openDevice(d) ?: throw UsbHatasi("ACILAMADI", "openDevice başarısız")
        try {
            if (!baglanti.claimInterface(arayuz, true)) throw UsbHatasi("ACILAMADI", "arayüz alınamadı")
            try {
                val parca = 4096
                repeat(kopya) {
                    var ofset = 0
                    while (ofset < veri.size) {
                        val n = minOf(parca, veri.size - ofset)
                        val gonderilen = baglanti.bulkTransfer(uc, veri, ofset, n, 5000)
                        if (gonderilen <= 0) throw UsbHatasi("YAZMA", "aktarım başarısız (yazıcı meşgul ya da kağıt yok)")
                        ofset += gonderilen
                    }
                }
            } finally {
                baglanti.releaseInterface(arayuz)
            }
        } finally {
            baglanti.close()
        }
    }
}
