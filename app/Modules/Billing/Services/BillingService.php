<?php

namespace App\Modules\Billing\Services;

use App\Modules\Billing\Models\SaasInvoice;
use App\Modules\Billing\Models\SaasPlan;
use App\Modules\Billing\Models\SaasSubscription;
use App\Modules\Tenancy\Models\Tenant;
use Illuminate\Support\Carbon;
use Illuminate\Support\Str;
use RuntimeException;

/**
 * A2 — Abonelik & Faturalama İSKELETİ.
 *
 * BİLİNÇLİ OLARAK YOK: gerçek ödeme sağlayıcı (iyzico/PayTR) tahsilat
 * çağrısı, kart saklama, webhook doğrulama. Bu servis yalnız veri modelini
 * (saas_subscriptions / saas_invoices) tutarlı biçimde günceller — tahsilat
 * gerçekleştiğinde markPaid() dışarıdan (ör. gelecekteki bir ödeme
 * sağlayıcı callback'i veya süper-admin manuel "ödendi işaretle" aksiyonu)
 * çağrılmalıdır.
 */
class BillingService
{
    /**
     * İşletme için abonelik başlat (veya mevcut açık aboneliği döndür).
     * Plan trial ise dönem sonu trial_days sonrasıdır; ücretli planlarda
     * interval'e göre (aylık/yıllık) bir sonraki dönem tarihi hesaplanır.
     */
    public function createSubscription(Tenant $tenant, string $planKey, ?Carbon $periodStart = null): SaasSubscription
    {
        $plan = SaasPlan::query()->where('key', $planKey)->where('is_active', true)->first();

        if (! $plan) {
            throw new RuntimeException("Bilinmeyen veya pasif SaaS planı: {$planKey}");
        }

        $start = $periodStart ?? now();

        return SaasSubscription::query()->create([
            'tenant_id' => $tenant->id,
            'plan_key' => $plan->key,
            'status' => $plan->key === 'trial' ? SaasSubscription::STATUS_TRIAL : SaasSubscription::STATUS_ACTIVE,
            'current_period_end' => $this->nextPeriodEnd($plan, $start),
            'cancel_at_period_end' => false,
        ]);
    }

    /**
     * Bir abonelik için fatura kaydı oluştur (tahsilat YAPMAZ — yalnız
     * kayıt). Tutar verilmezse aboneliğin bağlı olduğu planın fiyatı
     * kullanılır.
     */
    public function recordInvoice(SaasSubscription $subscription, ?int $amountMinor = null, array $opts = []): SaasInvoice
    {
        $plan = $subscription->plan ?? SaasPlan::query()->where('key', $subscription->plan_key)->first();
        $amount = $amountMinor ?? (int) ($plan->price_minor ?? 0);
        $issuedAt = $opts['issued_at'] ?? now();
        $dueAt = $opts['due_at'] ?? Carbon::parse($issuedAt)->addDays(7);

        return SaasInvoice::query()->create([
            'tenant_id' => $subscription->tenant_id,
            'subscription_id' => $subscription->id,
            'number' => $opts['number'] ?? $this->generateInvoiceNumber($subscription->tenant_id),
            'amount_minor' => $amount,
            'currency' => $opts['currency'] ?? ($plan->currency ?? 'TRY'),
            'status' => $opts['status'] ?? ($amount > 0 ? SaasInvoice::STATUS_UNPAID : SaasInvoice::STATUS_PAID),
            'issued_at' => $issuedAt,
            'due_at' => $dueAt,
            'paid_at' => $amount > 0 ? null : $issuedAt,
            'meta' => $opts['meta'] ?? null,
        ]);
    }

    /**
     * Faturayı ödendi işaretle (GERÇEK TAHSİLAT ÇAĞRISI YAPMAZ — bu yalnız
     * veri güncellemesidir; gerçek ödeme sağlayıcı entegrasyonunda bu metot
     * yalnız sağlayıcının başarı callback'i/webhook'u DOĞRULANDIKTAN sonra
     * çağrılmalıdır). Bağlı abonelik varsa dönem sonunu bir sonraki
     * periyoda taşır ve durumunu 'active' yapar.
     */
    public function markPaid(SaasInvoice $invoice, ?Carbon $paidAt = null): SaasInvoice
    {
        if ($invoice->isPaid()) {
            return $invoice;
        }

        $paidAt ??= now();

        $invoice->status = SaasInvoice::STATUS_PAID;
        $invoice->paid_at = $paidAt;
        $invoice->save();

        $subscription = $invoice->subscription;
        if ($subscription) {
            $plan = $subscription->plan;
            $base = $subscription->current_period_end && $subscription->current_period_end->greaterThan($paidAt)
                ? $subscription->current_period_end
                : $paidAt;

            $subscription->status = SaasSubscription::STATUS_ACTIVE;
            $subscription->current_period_end = $plan ? $this->nextPeriodEnd($plan, Carbon::parse($base)) : $subscription->current_period_end;
            $subscription->save();
        }

        return $invoice;
    }

    private function nextPeriodEnd(SaasPlan $plan, Carbon $from): Carbon
    {
        if ($plan->key === 'trial') {
            $days = (int) (config('pricing_saas.plans.trial.trial_days') ?? 14);

            return $from->copy()->addDays($days);
        }

        return $plan->interval === 'yearly'
            ? $from->copy()->addYear()
            : $from->copy()->addMonth();
    }

    private function generateInvoiceNumber(int $tenantId): string
    {
        return sprintf('SAAS-%s-%d-%s', now()->format('Ym'), $tenantId, Str::upper(Str::random(5)));
    }
}
