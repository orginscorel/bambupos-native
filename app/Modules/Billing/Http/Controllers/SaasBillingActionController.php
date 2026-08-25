<?php

namespace App\Modules\Billing\Http\Controllers;

use App\Http\Controllers\Controller;
use App\Modules\Billing\Models\SaasInvoice;
use App\Modules\Billing\Services\BillingService;
use App\Modules\Billing\Services\SaasPaymentService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\RedirectResponse;

/**
 * Süper-admin faturalama AKSİYONLARI — BillingOverviewController BİLİNÇLİ
 * OLARAK salt-okunur bırakıldığı için (bkz. o dosyanın docblock'u, "A2
 * temelinde salt-okuma istendi") ayrı bir controller'dır; mevcut kararı
 * BOZMAZ, yalnız üstüne YENİ uçlar ekler.
 *
 * Manuel mod (varsayılan — SAAS_PAYMENT_PROVIDER boş): canlı tahsilat YOK,
 * süper-admin burada faturayı elle "ödendi" işaretler (BillingService'in
 * baştan beri beklediği entegrasyon noktası — bkz. BillingService docblock'u:
 * "...süper-admin manuel 'ödendi işaretle' aksiyonu... çağrılmalıdır").
 * iyzico/PayTR modunda ise tenant'ın kendi ödeme bağlantısı üretilip
 * admin panelden görüntülenebilir/kopyalanabilir (gerçek tahsilat yine
 * yalnız webhook'tan gelir — bu uç asla "ödendi" YAZMAZ).
 */
class SaasBillingActionController extends Controller
{
    public function __construct(
        private readonly BillingService $billing,
        private readonly SaasPaymentService $payments,
    ) {
    }

    /** Faturayı elle "ödendi" işaretle + askıdaysa işletmeyi yeniden aç. */
    public function markPaid(SaasInvoice $invoice): RedirectResponse
    {
        if ($invoice->isPaid()) {
            return back()->with('ok', $invoice->number.' zaten ödenmiş.');
        }

        $this->billing->markPaid($invoice);

        $tenant = $invoice->tenant;
        if ($tenant && $tenant->isSuspended()) {
            $tenant->activate();
        }

        return back()->with('ok', $invoice->number.' elle ödendi işaretlendi'.($tenant ? ' — '.$tenant->name.' yeniden açıldı (askıdaysa).' : '.'));
    }

    /** Aktif sağlayıcı üzerinden fatura ödeme bağlantısını üretir (admin önizleme/kopyalama). */
    public function payLink(SaasInvoice $invoice): JsonResponse
    {
        try {
            $url = $this->payments->checkoutUrlFor($invoice);
        } catch (\Throwable $e) {
            return response()->json(['ok' => false, 'message' => $e->getMessage()], 422);
        }

        return response()->json(['ok' => true, 'url' => $url]);
    }
}
