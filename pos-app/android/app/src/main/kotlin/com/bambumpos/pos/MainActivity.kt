package com.bambumpos.pos

import android.content.Intent
import android.hardware.usb.UsbManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    /** USB yazıcı / kart POS köprüsü (lib/core/usb_android.dart). */
    private var usb: UsbKopru? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        usb = UsbKopru(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        usb?.kapat()
        usb = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    // Yazıcı takılınca sistem uygulamayı öne getirir (singleTop): listeyi tazele.
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (intent.action == UsbManager.ACTION_USB_DEVICE_ATTACHED) usb?.degisti()
    }
}
