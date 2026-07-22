<?php

namespace App\Modules\Payments\Contracts;

use App\Modules\Payments\Models\Payment;
use App\Modules\Payments\Providers\CallbackResult;
use App\Modules\Payments\Providers\ProviderResult;
use App\Modules\Payments\Providers\TerminalStatus;
use Illuminate\Http\Request;

/**
 * POS / ödeme sağlayıcı adapter sözleşmesi (prompt §15, ADR-010).
 *
 * KRİTİK KURAL: `sendAmountToTerminal` çağrısının DÖNMÜŞ olması ödemenin
 * tamamlandığı anlamına GELMEZ. Bir ödeme yalnız şu üç yoldan biriyle
 * "başarılı" sayılabilir:
 *   1. Sağlayıcının DOĞRULANMIŞ senkron onay cevabı (ProviderResult approved),
 *   2. İmzası ve zaman damgası doğrulanmış callback (verifyCallback),
 *   3. queryPayment ile sağlayıcıdan alınmış onay.
 * Bu kararı PaymentService verir; adapter yalnız sağlayıcı gerçeğini taşır.
 *
 * Adapter'lar DB'ye yazmaz, Order/paid_minor'a dokunmaz; tek işleri
 * sağlayıcı ile konuşup sonucu DTO olarak döndürmektir.
 */
interface PaymentProviderInterface
{
    /** Sağlayıcı anahtarı (payments.provider kolonuna yazılır). */
    public function key(): string;

    /**
     * Ödeme niyetini sağlayıcıda başlatır (işlem kaydı açar, sağlayıcı
     * işlem kimliği üretir/alır). Henüz tahsilat YOKTUR.
     */
    public function initiatePayment(Payment $payment): ProviderResult;

    /**
     * Tutarı fiziksel terminale gönderir. Dönen sonuç "terminal kabul
     * etti/başlattı" bilgisidir; approved DEĞİLSE ödeme bekliyor kalır.
     */
    public function sendAmountToTerminal(Payment $payment): ProviderResult;

    /** Sağlayıcıdaki güncel işlem durumunu sorgular (kesin kaynak). */
    public function queryPayment(Payment $payment): ProviderResult;

    /** Bekleyen/başarılı işlemi sağlayıcıda iptal (void) eder. */
    public function cancelPayment(Payment $payment): ProviderResult;

    /** Kısmi/tam iade başlatır. */
    public function refundPayment(Payment $payment, int $amountMinor): ProviderResult;

    /** Gün sonu mutabakatı: sağlayıcı kaydı ile yerel kaydı karşılaştırır. */
    public function reconcilePayment(Payment $payment): ProviderResult;

    /**
     * Callback isteğinin İMZASINI ve ZAMAN DAMGASINI doğrular; ham istekten
     * güvenilir alanları çıkarır. Tutar KARŞILAŞTIRMASI PaymentService'te
     * yapılır (tutar asla callback'ten alınmaz — ADR-010).
     */
    public function verifyCallback(Request $request): CallbackResult;

    /** Terminalin erişilebilirlik durumu. */
    public function getTerminalStatus(?string $terminalId): TerminalStatus;
}
