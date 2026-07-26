<?php

namespace App\Modules\Tenancy\Concerns;

use App\Modules\Tenancy\BranchContext;

/**
 * Controller yardımcısı: ŞUBE KAPSAMI tek çözücüye (BranchContext) kısa erişim.
 *
 * Liste/rapor sorguları `->where('branch_id', $this->currentBranchId())` ile
 * süzülür; yazma uçları oluşturulan kaydı geçerli şubeye bağlar. İstekten
 * gelen branch_id ASLA güvenilmez — çözücü personeli kendi şubesine kilitler,
 * yöneticiyi aktif seçili şubesine.
 */
trait ScopesToBranch
{
    protected function branchContext(): BranchContext
    {
        return app(BranchContext::class);
    }

    /** Geçerli şube kimliği. Fail-closed: null olabilir (çağıran boş sonuç döndürür). */
    protected function currentBranchId(): ?int
    {
        return $this->branchContext()->currentBranchId();
    }
}
