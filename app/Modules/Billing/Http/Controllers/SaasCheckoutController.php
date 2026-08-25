<?php

namespace App\Modules\Billing\Http\Controllers;

use App\Http\Controllers\Controller;
use App\Modules\Billing\Models\SaasInvoice;
use App\Modules\Billing\Services\SaasPaymentService;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\View\View;

/**
 * Kiracının "Şimdi Öde" akışı (tenant.suspended + yonetim.billing
 * ekranlarındaki buton buraya gelir).
 *
 * BİLİNÇLİ OLARAK `tenant` middleware'i YOK: askıya alınmış işletmenin
 * kullanıcısı zaten EnsureTenantContext tarafından /hesap-askida'ya
 * yönlendirilir; ödeme başlatma ucu o middleware zincirinin İÇİNDE olsaydı
 * askıdaki işletme buraya HİÇ ULAŞAMAZDI (döngü). Kimlik doğrulama burada
 * yalnız oturum + `tenant_id` eşleşmesi ile yapılır (routes/web.php'deki
 * /hesap-askida closure'ıyla AYNI desen).
 */
class SaasCheckoutController extends Controller
{
    public function __construct(private readonly SaasPaymentService $payments)
    {
    }

    /** Belirli bir fatura için ödeme sayfasına yönlendirir. */
    public function start(Request $request, SaasInvoice $invoice): RedirectResponse
    {
        $tenant = $request->user()?->tenant;

        if (! $tenant || (int) $invoice->tenant_id !== (int) $tenant->id) {
            abort(403, 'Bu fatura işletmenize ait değil.');
        }

        if ($invoice->isPaid()) {
            return redirect()->route('saas.pay.result', ['status' => 'already_paid']);
        }

        try {
            $url = $this->payments->checkoutUrlFor($invoice);
        } catch (\Throwable $e) {
            return back()->with('error', 'Çevrimiçi ödeme şu an kullanılamıyor: '.$e->getMessage());
        }

        return redirect()->away($url);
    }

    /** İşletmenin EN GÜNCEL ödenmemiş faturasını bulup ödeme akışını başlatır. */
    public function payLatest(Request $request): RedirectResponse
    {
        $tenant = $request->user()?->tenant;

        $invoice = $tenant
            ? SaasInvoice::query()
                ->where('tenant_id', $tenant->id)
                ->where('status', SaasInvoice::STATUS_UNPAID)
                ->orderByDesc('id')
                ->first()
            : null;

        if (! $invoice) {
            return redirect()->route('tenant.suspended')->with('error', 'Bekleyen bir faturanız yok; hesap durumu için bizimle iletişime geçin.');
        }

        return $this->start($request, $invoice);
    }

    /**
     * Sağlayıcının hosted sayfasından dönüş ekranı (ok/fail/already_paid).
     * KESİN durum YALNIZ webhook'tan gelir (bkz. SaasPaymentCallbackController)
     * — bu sayfa yalnız kullanıcıya bilgilendirme gösterir, veri YAZMAZ.
     */
    public function result(Request $request): View
    {
        return view('tenant.pay-result', [
            'status' => (string) $request->query('status', 'pending'),
        ]);
    }
}
