<?php

namespace App\Modules\Marketing\Http\Controllers;

use App\Http\Controllers\Controller;
use App\Modules\Marketing\Models\DemoRequest;
use App\Modules\Tenancy\Models\Tenant;
use App\Modules\Tenancy\Services\TenantProvisioner;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;

/**
 * BamBumPOS SaaS SÜPER-ADMIN — kiracı-üstü ürün yönetimi.
 * İşletme (tenant) yönetimi, abonelik/plan, demo talepleri, gelir/kullanım.
 * Tüm sorgular DB facade ile (global tenant-scope BYPASS) → tüm işletmeleri görür.
 */
class SuperAdminController extends Controller
{
    private const PLANS = ['trial' => 'Deneme', 'basic' => 'Başlangıç', 'pro' => 'Pro', 'enterprise' => 'Kurumsal'];

    /** Ödenmiş tahsilat toplamı (kuruş) — tenant filtresi opsiyonel, tarih aralığı opsiyonel. */
    private function revenue(?int $tenantId = null, ?Carbon $from = null, ?Carbon $to = null): int
    {
        $q = DB::table('payments')->whereNotNull('paid_at')->where('kind', '!=', 'refund');
        if ($tenantId !== null) $q->where('tenant_id', $tenantId);
        if ($from !== null) $q->where('paid_at', '>=', $from);
        if ($to !== null) $q->where('paid_at', '<=', $to);
        return (int) $q->sum('amount_minor');
    }

    public function dashboard()
    {
        $now = now();
        $tenants = DB::table('tenants')->count();
        $active = DB::table('tenants')->where('status', 'active')->count();
        $newThisMonth = DB::table('tenants')->where('created_at', '>=', $now->copy()->startOfMonth())->count();
        $pendingDemos = DB::table('demo_requests')->where('status', 'new')->count();

        // Kullanıcı sayısı (personel) + toplam sipariş
        $users = DB::table('users')->where('is_terminal', false)->count();
        $orders = DB::table('orders')->count();

        // Gelir
        $revToday = $this->revenue(null, $now->copy()->startOfDay());
        $revMonth = $this->revenue(null, $now->copy()->startOfMonth());
        $revAll = $this->revenue();

        // İşletme başına bu-ay ciro (en yüksek 5) + kullanıcı sayısı
        $revByTenant = DB::table('payments')
            ->whereNotNull('paid_at')->where('kind', '!=', 'refund')
            ->where('paid_at', '>=', $now->copy()->startOfMonth())
            ->groupBy('tenant_id')->selectRaw('tenant_id, SUM(amount_minor) as m')
            ->pluck('m', 'tenant_id');

        $recentTenants = DB::table('tenants')->orderByDesc('id')->limit(6)
            ->get(['id', 'name', 'slug', 'status', 'plan', 'created_at']);

        $recentDemos = DB::table('demo_requests')->orderByDesc('id')->limit(6)
            ->get(['id', 'name', 'business', 'phone', 'sector', 'status', 'created_at']);

        // Son 14 gün gelir trendi (tüm işletmeler)
        $trend = [];
        for ($i = 13; $i >= 0; $i--) {
            $d = $now->copy()->subDays($i)->startOfDay();
            $trend[] = [
                'label' => $d->format('d.m'),
                'value' => $this->revenue(null, $d, $d->copy()->endOfDay()),
            ];
        }

        return view('yonetim.dashboard', compact(
            'tenants', 'active', 'newThisMonth', 'pendingDemos', 'users', 'orders',
            'revToday', 'revMonth', 'revAll', 'revByTenant', 'recentTenants', 'recentDemos', 'trend'
        ) + ['plans' => self::PLANS]);
    }

    public function tenants(Request $request)
    {
        $q = trim((string) $request->query('q', ''));
        $status = (string) $request->query('status', '');

        $rows = DB::table('tenants')
            ->when($q !== '', fn ($b) => $b->where(fn ($w) => $w->where('name', 'like', "%$q%")->orWhere('slug', 'like', "%$q%")))
            ->when(in_array($status, ['active', 'suspended', 'trial'], true), fn ($b) => $b->where('status', $status))
            ->orderByDesc('id')
            ->get(['id', 'name', 'slug', 'domain', 'status', 'plan', 'trial_ends_at', 'subscribed_until', 'billing_note', 'created_at']);

        $ids = $rows->pluck('id')->all();
        $userCounts = DB::table('users')->whereIn('tenant_id', $ids)->where('is_terminal', false)
            ->groupBy('tenant_id')->selectRaw('tenant_id, COUNT(*) c')->pluck('c', 'tenant_id');
        $revMonth = DB::table('payments')->whereIn('tenant_id', $ids)
            ->whereNotNull('paid_at')->where('kind', '!=', 'refund')
            ->where('paid_at', '>=', now()->startOfMonth())
            ->groupBy('tenant_id')->selectRaw('tenant_id, SUM(amount_minor) m')->pluck('m', 'tenant_id');

        return view('yonetim.tenants', [
            'rows' => $rows, 'userCounts' => $userCounts, 'revMonth' => $revMonth,
            'plans' => self::PLANS, 'q' => $q, 'status' => $status,
            'pendingDemos' => DB::table('demo_requests')->where('status', 'new')->count(),
        ]);
    }

    public function tenantUpdate(Request $request, int $id): RedirectResponse
    {
        $data = $request->validate([
            'status' => ['required', Rule::in(['active', 'suspended', 'trial'])],
            'plan' => ['nullable', Rule::in(array_keys(self::PLANS))],
            'subscribed_until' => ['nullable', 'date'],
            'billing_note' => ['nullable', 'string', 'max:255'],
        ]);

        DB::table('tenants')->where('id', $id)->update([
            'status' => $data['status'],
            'plan' => $data['plan'] ?? null,
            'subscribed_until' => $data['subscribed_until'] ?? null,
            'billing_note' => $data['billing_note'] ?? null,
            'updated_at' => now(),
        ]);

        return back()->with('ok', 'İşletme güncellendi.');
    }

    /** Yeni POS mağazası aç — tenant + şube + roller + sahip kullanıcı (tek aksiyon). */
    public function tenantStore(Request $request, TenantProvisioner $provisioner): RedirectResponse
    {
        $data = $request->validate([
            'name' => ['required', 'string', 'max:120'],
            'owner_name' => ['nullable', 'string', 'max:120'],
            'owner_email' => ['required', 'email', 'max:190', Rule::unique('users', 'email')],
            'plan' => ['nullable', Rule::in(array_keys(self::PLANS))],
            'trial_days' => ['nullable', 'integer', 'min:0', 'max:365'],
        ], [], ['owner_email' => 'sahip e-postası']);

        $result = $provisioner->provision([
            'name' => $data['name'],
            'owner_name' => $data['owner_name'] ?? null,
            'owner_email' => $data['owner_email'],
            'plan' => $data['plan'] ?? 'trial',
            'trial_days' => $data['trial_days'] ?? 14,
        ]);

        // Sahip parolası YALNIZ bir kez gösterilir (session flash; saklanmaz).
        return back()->with('provisioned', [
            'name' => $result['tenant']->name,
            'slug' => $result['tenant']->slug,
            'email' => $result['owner']->email,
            'password' => $result['password'],
        ])->with('ok', $result['tenant']->name . ' oluşturuldu.');
    }

    /** Askıya al / yeniden aç (geri alınabilir; oturum ve veri korunur). */
    public function tenantSetStatus(Request $request, int $id): RedirectResponse
    {
        $data = $request->validate([
            'action' => ['required', Rule::in(['suspend', 'activate'])],
            'note' => ['nullable', 'string', 'max:255'],
        ]);

        $tenant = Tenant::query()->findOrFail($id);

        if ($data['action'] === 'suspend') {
            $tenant->suspend($data['note'] ?? null);
            $msg = $tenant->name . ' askıya alındı.';
        } else {
            $tenant->activate();
            $msg = $tenant->name . ' yeniden açıldı.';
        }

        return back()->with('ok', $msg);
    }

    public function demoRequests(Request $request)
    {
        $status = (string) $request->query('status', '');
        $rows = DemoRequest::query()
            ->when(in_array($status, ['new', 'contacted', 'won', 'lost'], true), fn ($b) => $b->where('status', $status))
            ->orderByDesc('id')->limit(300)->get();

        $counts = DemoRequest::query()->groupBy('status')->selectRaw('status, COUNT(*) c')->pluck('c', 'status');

        return view('yonetim.demo-requests', [
            'rows' => $rows, 'counts' => $counts, 'status' => $status,
            'pendingDemos' => (int) ($counts['new'] ?? 0),
        ]);
    }

    public function demoUpdate(Request $request, int $id): RedirectResponse
    {
        $data = $request->validate(['status' => ['required', Rule::in(['new', 'contacted', 'won', 'lost'])]]);
        $r = DemoRequest::findOrFail($id);
        $r->status = $data['status'];
        $r->handled_at = $data['status'] === 'new' ? null : now();
        $r->save();

        return back()->with('ok', 'Talep güncellendi.');
    }
}
