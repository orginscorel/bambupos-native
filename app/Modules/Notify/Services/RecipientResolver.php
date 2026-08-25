<?php

namespace App\Modules\Notify\Services;

use App\Modules\Identity\Models\User;
use App\Modules\Kds\Services\KdsService;
use App\Modules\Notify\Enums\NotificationType;
use App\Modules\Tenancy\BranchContext;
use Illuminate\Support\Collection;

/**
 * §8 ALICI ÇÖZÜCÜ — bir olay tipinin bildirimini KİMLERİN alacağını belirler.
 *
 * Kurallar NotificationType kataloğundan gelir (izin / yönetici / istasyon
 * kulvarı). ŞUBE KAPSAMI güvenlik sınırıdır: alıcılar yalnızca olayın şubesine
 * (ya da şubesiz/HQ personeline) süzülür — başka şubenin siparişi başka şubenin
 * mutfağını RAHATSIZ ETMEZ. İstekten gelen veriye güvenilmez; şube olayın
 * kendisinden (Order/Reservation) türetilir.
 */
class RecipientResolver
{
    /** Yönetici tanımı — "yönetim hepsini görür" (kendi şubesi). */
    private const MANAGER_PERMISSIONS = ['reports.view', 'staff.manage', 'settings.manage'];

    public function __construct(
        private readonly KdsService $kds,
        private readonly BranchContext $branchContext,
    ) {}

    /**
     * @param  array<string, mixed>  $context  ['lane'=>?string, 'extra_user_ids'=>int[]]
     * @return Collection<int, User>
     */
    public function resolve(NotificationType $type, int $tenantId, ?int $branchId, array $context = []): Collection
    {
        $permissions = $type->targetPermissions();
        $includeManagers = $type->includeManagers();
        $lane = $type->laneScoped() ? ($context['lane'] ?? null) : null;
        $extraIds = array_map('intval', (array) ($context['extra_user_ids'] ?? []));

        // Kiracının aktif, GERÇEK (terminal olmayan) personeli. Terminal cihazları
        // kendi tam-ekran KDS ekranından ses+görsel uyarı alır; kişisel zil/push
        // taşımaz → bildirim havuzundan hariç.
        $candidates = User::query()
            ->where('tenant_id', $tenantId)
            ->where('is_active', true)
            ->where('is_terminal', false)
            // hasPermission()/permissionKeys() aday başına izinleri sorgular →
            // N+1'i önlemek için rol izinleri + kişisel izinler eager-load edilir.
            ->with(['roles.permissions', 'personalPermissions'])
            ->when($branchId !== null, function ($q) use ($branchId): void {
                // Olayın şubesindeki personel + şubesiz (HQ/çok-şube yönetici) personel.
                $q->where(function ($w) use ($branchId): void {
                    $w->where('branch_id', $branchId)->orWhereNull('branch_id');
                });
            })
            ->get();

        return $candidates->filter(function (User $user) use ($permissions, $includeManagers, $lane, $extraIds): bool {
            // Bağlamsal ek alıcı (ör. SLA'da teslim alan komi) daima dahil.
            if (in_array((int) $user->getKey(), $extraIds, true)) {
                return true;
            }

            $isManager = $this->isManager($user);

            $hasTargetPermission = false;
            foreach ($permissions as $key) {
                if ($user->hasPermission($key)) {
                    $hasTargetPermission = true;
                    break;
                }
            }

            if (! $hasTargetPermission && ! ($includeManagers && $isManager)) {
                return false;
            }

            // İstasyon kulvarı süzgeci (yalnız laneScoped olaylarda): kısıtsız
            // (yönetici/çok-istasyonlu) kullanıcı her kulvarı alır; kısıtlı
            // kullanıcı yalnız kendi kulvarını.
            if ($lane !== null && ! $isManager) {
                $families = $this->kds->stationFamilies($user); // [] = kısıt yok
                if ($families !== [] && ! in_array($lane, $families, true)) {
                    return false;
                }
            }

            return true;
        })->values();
    }

    private function isManager(User $user): bool
    {
        foreach (self::MANAGER_PERMISSIONS as $key) {
            if ($user->hasPermission($key)) {
                return true;
            }
        }

        return false;
    }
}
