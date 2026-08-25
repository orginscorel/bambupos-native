<?php

namespace App\Modules\Billing\Http\Controllers;

use App\Http\Controllers\Controller;
use Illuminate\Support\Facades\DB;

/**
 * A2 — Abonelik & Faturalama: süper-admin SALT-OKUNUR genel bakış.
 *
 * Kiracı-üstü (tüm işletmeler) — `superadmin` middleware'i ile korunur
 * (bkz. routes/billing_saas.php). Yalnız DB facade ile okuma yapar; hiçbir
 * yazma/aksiyon ucu YOKTUR (bilinçli — A2 temelinde salt-okuma istendi).
 *
 * NOT: Buradaki gelir SaaS abonelik geliridir (saas_* tabloları) —
 * SuperAdminController::revenue()'daki `payments` (POS/kasa tahsilatı,
 * işletme içi ciro) ile KARIŞTIRILMAMALI, ayrı bir gelir kalemidir.
 */
class BillingOverviewController extends Controller
{
    public function overview()
    {
        $now = now();

        // MRR: yalnız 'active' abonelikler (deneme geliri saymaz). Yıllık
        // planlar aylığa bölünür.
        $activeSubs = DB::table('saas_subscriptions as s')
            ->join('saas_plans as p', 'p.key', '=', 's.plan_key')
            ->where('s.status', 'active')
            ->select('s.id', 's.tenant_id', 's.plan_key', 's.current_period_end', 'p.price_minor', 'p.interval')
            ->get();

        $mrrMinor = (int) $activeSubs->sum(fn ($s) => $s->interval === 'yearly' ? intdiv((int) $s->price_minor, 12) : (int) $s->price_minor);

        $trialCount = DB::table('saas_subscriptions')->where('status', 'trial')->count();
        $activeCount = $activeSubs->count();
        $pastDueCount = DB::table('saas_subscriptions')->where('status', 'past_due')->count();
        $cancelledCount = DB::table('saas_subscriptions')->where('status', 'cancelled')->count();

        // Yaklaşan yenilemeler (7 / 30 gün) — trial + active + past_due.
        $renewalsBase = DB::table('saas_subscriptions as s')
            ->join('tenants as t', 't.id', '=', 's.tenant_id')
            ->join('saas_plans as p', 'p.key', '=', 's.plan_key')
            ->whereIn('s.status', ['trial', 'active', 'past_due'])
            ->whereNotNull('s.current_period_end')
            ->where('s.current_period_end', '>=', $now->copy()->startOfDay())
            ->orderBy('s.current_period_end')
            ->select('s.id', 't.name as tenant_name', 's.plan_key', 'p.name as plan_name', 's.status', 's.current_period_end');

        $upcoming30 = (clone $renewalsBase)->where('s.current_period_end', '<=', $now->copy()->addDays(30)->endOfDay())->limit(50)->get();
        $upcoming7 = $upcoming30->filter(fn ($r) => \Illuminate\Support\Carbon::parse($r->current_period_end)->lte($now->copy()->addDays(7)->endOfDay()))->values();

        // Plan dağılımı: cari (iptal edilmemiş) abonelikler.
        $planDistribution = DB::table('saas_subscriptions')
            ->whereIn('status', ['trial', 'active', 'past_due'])
            ->select('plan_key', DB::raw('COUNT(*) as c'))
            ->groupBy('plan_key')
            ->pluck('c', 'plan_key');

        // Ödenmemiş faturalar.
        $unpaidCount = DB::table('saas_invoices')->where('status', 'unpaid')->count();
        $unpaidMinor = (int) DB::table('saas_invoices')->where('status', 'unpaid')->sum('amount_minor');

        $recentInvoices = DB::table('saas_invoices as i')
            ->join('tenants as t', 't.id', '=', 'i.tenant_id')
            ->orderByDesc('i.id')
            ->limit(10)
            ->select('i.id', 'i.number', 't.name as tenant_name', 'i.amount_minor', 'i.currency', 'i.status', 'i.issued_at', 'i.due_at', 'i.paid_at')
            ->get();

        $plans = DB::table('saas_plans')->orderBy('price_minor')->get(['key', 'name', 'price_minor', 'currency', 'interval', 'is_active']);

        return view('yonetim.billing', [
            'mrrMinor' => $mrrMinor,
            'trialCount' => $trialCount,
            'activeCount' => $activeCount,
            'pastDueCount' => $pastDueCount,
            'cancelledCount' => $cancelledCount,
            'upcoming7' => $upcoming7,
            'upcoming30' => $upcoming30,
            'planDistribution' => $planDistribution,
            'plans' => $plans,
            'unpaidCount' => $unpaidCount,
            'unpaidMinor' => $unpaidMinor,
            'recentInvoices' => $recentInvoices,
            'pendingDemos' => DB::table('demo_requests')->where('status', 'new')->count(),
        ]);
    }
}
