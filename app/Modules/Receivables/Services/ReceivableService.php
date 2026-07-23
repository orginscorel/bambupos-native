<?php

namespace App\Modules\Receivables\Services;

use App\Modules\Identity\Models\User;
use App\Modules\Identity\Services\AuditLogger;
use App\Modules\Orders\Models\Order;
use App\Modules\Orders\Services\OrderService;
use App\Modules\Receivables\Models\Receivable;
use App\Modules\Receivables\Models\ReceivableTransaction;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;

/**
 * Borçlar/Cari çekirdeği (Adisyon-Cari görev §2):
 *
 *  - "Adisyonu borca taşı": açık+ödenmemiş adisyonun KALAN tutarı
 *    (total_minor - paid_minor) cariye BORÇ olarak yazılır, adisyon
 *    OrderService::markDebtTransferred ile terminal 'debt_transferred'
 *    durumuna geçer (masa BOŞALIR — TableStatusSynchronizer).
 *  - Tahsilat: cari borcu tam/kısmi kapatılır. AŞIRI TAHSİLAT REDDEDİLİR
 *    (para değişmezi) — bakiye asla negatife düşmez.
 *  - `receivables.balance_minor` = receivable_transactions defterinin
 *    TOPLAMI; her mutasyon SATIR KİLİDİYLE + transaction içinde yazılır
 *    (CashSessionService ile aynı desen — kuruş kaybı yok).
 */
class ReceivableService
{
    public function __construct(
        private readonly OrderService $orders,
        private readonly AuditLogger $audit,
    ) {
    }

    /** @param array{branch_id?: int|null, name: string, phone?: string|null, email?: string|null, note?: string|null} $data */
    public function create(array $data, ?User $actor): Receivable
    {
        $receivable = new Receivable([
            'branch_id' => $data['branch_id'] ?? null,
            'name' => trim($data['name']),
            'phone' => $data['phone'] ?? null,
            'email' => $data['email'] ?? null,
            'note' => $data['note'] ?? null,
            'is_active' => true,
        ]);
        $receivable->created_by_id = $actor?->getKey();
        $receivable->save();

        return $receivable;
    }

    /** @param array{branch_id?: int|null, name?: string, phone?: string|null, email?: string|null, note?: string|null, is_active?: bool} $data */
    public function update(Receivable $receivable, array $data): Receivable
    {
        return DB::transaction(function () use ($receivable, $data): Receivable {
            /** @var Receivable $locked */
            $locked = Receivable::query()->lockForUpdate()->findOrFail($receivable->getKey());

            if (array_key_exists('name', $data)) {
                $locked->name = trim((string) $data['name']);
            }
            if (array_key_exists('branch_id', $data)) {
                $locked->branch_id = $data['branch_id'];
            }
            if (array_key_exists('phone', $data)) {
                $locked->phone = $data['phone'];
            }
            if (array_key_exists('email', $data)) {
                $locked->email = $data['email'];
            }
            if (array_key_exists('note', $data)) {
                $locked->note = $data['note'];
            }
            if (array_key_exists('is_active', $data)) {
                $locked->is_active = (bool) $data['is_active'];
            }

            $locked->save();

            return $locked;
        });
    }

    /**
     * "Adisyonu borca taşı" — açık+ödenmemiş kalan tutar cariye borç
     * yazılır; adisyon terminal 'debt_transferred' durumuna geçer, masa
     * boşalır. Kilit sırası SABİT (Order → Receivable) — collect() yalnız
     * Receivable kilitler, çapraz kilitlenme (deadlock) oluşmaz.
     */
    public function transferOrderToDebt(Order $order, Receivable $receivable, string $reason, User $actor, ?int $expectedVersion = null): Order
    {
        if ((int) $order->tenant_id !== (int) $receivable->tenant_id) {
            throw ValidationException::withMessages(['receivable_id' => ['Cari bu adisyonun kiracısına ait değil.']]);
        }

        return $this->orders->withLockedOrder($order, $expectedVersion, function (Order $locked) use ($receivable, $reason, $actor): Order {
            if (! $locked->statusEnum()->isOpen()) {
                throw ValidationException::withMessages(['order' => ['Yalnız açık adisyon borca taşınabilir (durum: '.$locked->statusEnum()->label().').']]);
            }

            $remaining = max(0, (int) $locked->total_minor - (int) $locked->paid_minor);

            if ($remaining <= 0) {
                throw ValidationException::withMessages(['order' => ['Bu adisyonun kalan bakiyesi yok; borca taşınacak tutar sıfır.']]);
            }

            /** @var Receivable $lockedReceivable */
            $lockedReceivable = Receivable::query()->lockForUpdate()->findOrFail($receivable->getKey());

            if (! $lockedReceivable->is_active) {
                throw ValidationException::withMessages(['receivable_id' => ['Pasif cariye borç taşınamaz.']]);
            }

            $this->orders->markDebtTransferred($locked, (int) $lockedReceivable->getKey(), $remaining, $actor, [
                'reason' => $reason,
                'receivable_name' => $lockedReceivable->name,
            ]);

            $newBalance = (int) $lockedReceivable->balance_minor + $remaining;
            $lockedReceivable->balance_minor = $newBalance;
            $lockedReceivable->save();

            $ledger = new ReceivableTransaction([
                'receivable_id' => $lockedReceivable->getKey(),
                'order_id' => $locked->getKey(),
                'type' => 'debt_transfer',
                'amount_minor' => $remaining,
                'method' => null,
                'note' => $reason,
                'balance_after_minor' => $newBalance,
                'performed_by_id' => $actor->getKey(),
                'created_at' => now(),
            ]);
            $ledger->tenant_id = $lockedReceivable->tenant_id;
            $ledger->save();

            $this->audit->log('receivables.debt_transferred', $lockedReceivable, ['balance_minor' => $newBalance - $remaining], [
                'order_id' => $locked->getKey(),
                'amount_minor' => $remaining,
                'reason' => $reason,
                'performed_by' => $actor->getKey(),
            ]);

            return $locked;
        });
    }

    /**
     * Tahsilat: tam ya da kısmi. AŞIRI TAHSİLAT REDDEDİLİR (para değişmezi
     * — bakiye asla negatife düşmez; "fazla ödeme" bu tasarımda mümkün
     * değildir, kullanıcı önce doğru/kalan tutarı görür).
     */
    public function collect(Receivable $receivable, int $amountMinor, string $method, ?string $note, User $actor): ReceivableTransaction
    {
        if ($amountMinor <= 0) {
            throw ValidationException::withMessages(['amount_minor' => ['Tahsilat tutarı sıfırın üzerinde olmalı.']]);
        }

        return DB::transaction(function () use ($receivable, $amountMinor, $method, $note, $actor): ReceivableTransaction {
            /** @var Receivable $locked */
            $locked = Receivable::query()->lockForUpdate()->findOrFail($receivable->getKey());

            $balance = (int) $locked->balance_minor;

            if ($amountMinor > $balance) {
                throw ValidationException::withMessages(['amount_minor' => [
                    'Tahsilat tutarı güncel borcu ('.\App\Modules\Catalog\Support\Money::toDecimalString($balance).' TL) aşamaz.',
                ]]);
            }

            $newBalance = $balance - $amountMinor;
            $locked->balance_minor = $newBalance;
            $locked->save();

            $ledger = new ReceivableTransaction([
                'receivable_id' => $locked->getKey(),
                'order_id' => null,
                'type' => 'payment',
                'amount_minor' => -$amountMinor,
                'method' => $method,
                'note' => $note,
                'balance_after_minor' => $newBalance,
                'performed_by_id' => $actor->getKey(),
                'created_at' => now(),
            ]);
            $ledger->tenant_id = $locked->tenant_id;
            $ledger->save();

            $this->audit->log('receivables.payment_collected', $locked, ['balance_minor' => $balance], [
                'amount_minor' => $amountMinor,
                'method' => $method,
                'note' => $note,
                'balance_minor' => $newBalance,
                'performed_by' => $actor->getKey(),
            ]);

            return $ledger;
        });
    }
}
