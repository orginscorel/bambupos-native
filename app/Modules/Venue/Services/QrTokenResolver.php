<?php

namespace App\Modules\Venue\Services;

use App\Modules\Identity\Services\AuditLogger;
use App\Modules\Tables\Models\Table;
use App\Modules\Tenancy\Models\Branch;
use App\Modules\Venue\Models\QrScan;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\RateLimiter;

/**
 * ADR-008: public QR akışında kiracı + şube + masa YALNIZ opak token'dan
 * çözülür; istekten kimlik parametresi asla kabul edilmez. Sorgular
 * bilinçli olarak tenant-scope'suz çalışır (public uçta bağlam yoktur);
 * dönen modelin tenant'ı sonucun içinde taşınır ve sipariş fazı yazma
 * işlemlerinde bu tenant'ı bağlama koyarak kullanacaktır — böylece
 * "başka masaya sipariş" token bilinmeden imkânsızdır.
 */
class QrTokenResolver
{
    /** Aynı IP'den 10 dk içinde bu kadar geçersiz deneme = şüpheli (denetim kaydı). */
    private const SUSPICIOUS_INVALID_THRESHOLD = 10;

    public function __construct(private readonly AuditLogger $audit)
    {
    }

    public function resolve(string $token, Request $request): QrTokenResolution
    {
        $token = strtoupper(trim($token));

        // Biçim: 26 karakter base32 (ADR-008). Uymayan girdi DB'ye inmez.
        if (preg_match('/^[A-Z2-7]{26}$/', $token) !== 1) {
            $this->logScan($request, $token, 'invalid');

            return QrTokenResolution::invalid();
        }

        // 1) Masa token'ı
        $table = Table::withoutTenancy()->where('qr_token', $token)->first();

        if ($table !== null) {
            return $this->resolveTable($table, $token, $request);
        }

        // 2) Şube token'ı (genel menü / paket servis QR'ı)
        $branch = Branch::withoutTenancy()->where('qr_token', $token)->first();

        if ($branch !== null) {
            return $this->resolveBranch($branch, $token, $request);
        }

        // 3) Rotasyonla geçersiz kılınmış eski token → 410 (ADR-008)
        $revokedTable = Table::withoutTenancy()->where('previous_qr_token', $token)->first();
        $revokedBranch = $revokedTable === null
            ? Branch::withoutTenancy()->where('previous_qr_token', $token)->first()
            : null;

        if ($revokedTable !== null || $revokedBranch !== null) {
            $this->logScan($request, $token, 'revoked',
                $revokedTable?->tenant_id ?? $revokedBranch?->tenant_id,
                $revokedTable?->id);

            return QrTokenResolution::revoked();
        }

        $this->logScan($request, $token, 'invalid');
        $this->detectSuspicious($request);

        return QrTokenResolution::invalid();
    }

    private function resolveTable(Table $table, string $token, Request $request): QrTokenResolution
    {
        $branch = Branch::withoutTenancy()->find($table->branch_id);
        $tenant = $table->tenant()->first();

        if ($branch === null || $tenant === null || ! $tenant->isActive()
            || ! $branch->is_active || ! $table->is_active) {
            $this->logScan($request, $token, 'inactive', $table->tenant_id, $table->id);

            return QrTokenResolution::inactive();
        }

        $this->logScan($request, $token, 'ok', $table->tenant_id, $table->id);

        return QrTokenResolution::ok($tenant, $branch, $table);
    }

    private function resolveBranch(Branch $branch, string $token, Request $request): QrTokenResolution
    {
        $tenant = $branch->tenant()->first();

        if ($tenant === null || ! $tenant->isActive() || ! $branch->is_active) {
            $this->logScan($request, $token, 'inactive', $branch->tenant_id);

            return QrTokenResolution::inactive();
        }

        $this->logScan($request, $token, 'ok', $branch->tenant_id);

        return QrTokenResolution::ok($tenant, $branch, null);
    }

    private function logScan(Request $request, string $token, string $result, ?int $tenantId = null, ?int $tableId = null): void
    {
        QrScan::query()->create([
            'tenant_id' => $tenantId,
            'table_id' => $tableId,
            'token' => substr($token, 0, 26),
            'result' => $result,
            'ip_hash' => QrScan::hashIp($request->ip()),
            'user_agent' => mb_substr((string) $request->userAgent(), 0, 255) ?: null,
        ]);
    }

    /**
     * Aynı IP'den kısa sürede çok sayıda geçersiz token = token tarama
     * girişimi; denetim kaydına düşülür (pencere başına bir kez).
     */
    private function detectSuspicious(Request $request): void
    {
        $ipHash = QrScan::hashIp($request->ip());

        $invalidCount = QrScan::query()
            ->where('ip_hash', $ipHash)
            ->where('result', 'invalid')
            ->where('created_at', '>=', now()->subMinutes(10))
            ->count();

        if ($invalidCount < self::SUSPICIOUS_INVALID_THRESHOLD) {
            return;
        }

        // Pencere başına tek denetim kaydı (log seli olmasın).
        $key = 'qr-suspicious:'.$ipHash;

        if (RateLimiter::tooManyAttempts($key, 1)) {
            return;
        }

        RateLimiter::hit($key, 600);

        $this->audit->log('qr.suspicious_scan', null, null, [
            'ip_hash' => $ipHash,
            'invalid_count_10m' => $invalidCount,
            'user_agent' => mb_substr((string) $request->userAgent(), 0, 255),
        ]);
    }
}
