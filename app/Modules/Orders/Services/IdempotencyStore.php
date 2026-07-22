<?php

namespace App\Modules\Orders\Services;

use App\Modules\Orders\Models\OrderIdempotencyKey;
use Illuminate\Database\QueryException;
use Symfony\Component\HttpKernel\Exception\HttpException;

/**
 * Aynı isteğin iki kez gelmesi sipariş/kalem ÇOĞALTMAZ (prompt §12.4).
 *
 * Desen: istemci `Idempotency-Key` başlığı gönderir.
 *  1. Anahtar UNIQUE(tenant_id, key) ile "rezerve edilir" (transaction DIŞI,
 *     hemen commit olur → eşzamanlı ikinci istek MySQL'de bu satırın kilidini
 *     bekler, ilk istek commit edince duplicate-key alır).
 *  2. İş çalışır; yanıt anahtara yazılır.
 *  3. Aynı anahtar tekrar gelirse saklanan yanıt AYNEN döner (`replayed`).
 *     İlk istek hâlâ sürüyorsa kısa bekleyip 409 döner (istemci tekrar dener).
 *  4. İş exception atarsa rezervasyon silinir → dürüst tekrar deneme mümkün.
 */
class IdempotencyStore
{
    /**
     * @param  callable(): array{0: array<string, mixed>, 1: int}  $operation  [yanıt, statusCode]
     * @return array{0: array<string, mixed>, 1: int, 2: bool} [yanıt, statusCode, replayed]
     */
    public function run(int $tenantId, ?string $key, string $endpoint, callable $operation): array
    {
        if ($key === null || $key === '') {
            [$response, $status] = $operation();

            return [$response, $status, false];
        }

        $claim = new OrderIdempotencyKey(['key' => mb_substr($key, 0, 80), 'endpoint' => $endpoint]);
        $claim->tenant_id = $tenantId;

        try {
            $claim->save();
        } catch (QueryException $e) {
            if (! $this->isDuplicate($e)) {
                throw $e;
            }

            return $this->replay($tenantId, $key);
        }

        try {
            [$response, $status] = $operation();
        } catch (\Throwable $e) {
            $claim->delete(); // başarısız iş rezervasyonu tutmaz; istemci yeniden deneyebilir

            throw $e;
        }

        $claim->forceFill([
            'order_id' => $response['order']['id'] ?? null,
            'response' => $response,
            'status_code' => $status,
        ])->save();

        return [$response, $status, false];
    }

    /** @return array{0: array<string, mixed>, 1: int, 2: bool} */
    private function replay(int $tenantId, string $key): array
    {
        // İlk istek işini bitirmemiş olabilir; kısa pencere içinde bekle.
        for ($attempt = 0; $attempt < 10; $attempt++) {
            $row = OrderIdempotencyKey::withoutTenancy()
                ->where('tenant_id', $tenantId)
                ->where('key', mb_substr($key, 0, 80))
                ->first();

            if ($row === null) {
                // İlk istek başarısız olup rezervasyonu silmiş → istemci yeniden denesin.
                throw new HttpException(409, 'Önceki istek başarısız oldu; lütfen yeniden deneyin.');
            }

            if ($row->response !== null) {
                return [$row->response, (int) $row->status_code, true];
            }

            usleep(150_000); // 150 ms × 10 ≈ 1,5 sn pencere
        }

        throw new HttpException(409, 'Aynı istek hâlâ işleniyor; lütfen bekleyin.');
    }

    private function isDuplicate(QueryException $e): bool
    {
        $sqlState = $e->errorInfo[0] ?? null;
        $code = $e->errorInfo[1] ?? null;

        return $sqlState === '23000' || $sqlState === '23505' || $code === 1062 || $code === 19;
    }
}
