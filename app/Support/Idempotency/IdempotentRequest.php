<?php

namespace App\Support\Idempotency;

use App\Support\Idempotency\Models\IdempotencyKey;
use Illuminate\Database\QueryException;
use Symfony\Component\HttpKernel\Exception\HttpException;

/**
 * Genel amaçlı (modül-bağımsız) op_id idempotency katmanı — offline-kuyruk
 * senkronunun sunucu temeli (görev B). bkz. docs/offline-sync-protocol.md.
 *
 * App\Modules\Orders\Services\IdempotencyStore'dan (Idempotency-Key HEADER,
 * tek ağ isteği tekrarını/çift-dokunmayı çözer) BİLİNÇLİ olarak FARKLI bir
 * kaygıyı çözer: `op_id` istemcide işlem KUYRUĞA eklenirken üretilir — ağ
 * isteğinden ÖNCE var olur ve gün(ler) sonra geç senkron olsa da AYNI kalır.
 * İki katman birbirinden bağımsız çalışabilir; addItem'de iç içe kullanılır
 * (bkz. OrderController::addItem).
 *
 * Desen (IdempotencyStore ile aynı iskelet):
 *  1. (tenant_id, op_id) UNIQUE ile satır rezerve edilir (status=processing,
 *     transaction DIŞI → hemen commit olur; eşzamanlı ikinci istek bu satırın
 *     kilidini bekler, ilk istek commit edince duplicate-key alır).
 *  2. Aynı op_id + FARKLI gövde (request_hash uyuşmaz) gelirse 409 — istemci
 *     hatası/çakışma sessizce yutulmaz.
 *  3. Aynı op_id + AYNI gövde: ilk yanıt (response_snapshot) AYNEN döner,
 *     iş TEKRAR ÇALIŞTIRILMAZ.
 *  4. İş exception atarsa rezervasyon silinir → dürüst tekrar deneme mümkün.
 *
 * op_id YOKSA bu katman devre dışıdır — çağıran taraf bugünkü davranışı
 * (ör. Idempotency-Key header akışı) aynen sürdürür; bkz. çağıran kod.
 */
class IdempotentRequest
{
    private const POLL_ATTEMPTS = 10;

    private const POLL_DELAY_US = 150_000; // 150ms × 10 ≈ 1,5sn pencere

    /**
     * @param  array<string, mixed>  $payload  hash'lenecek istek gövdesi (op_id hariç)
     * @param  callable(): array{0: array<string, mixed>, 1: int}  $operation  [yanıt, statusCode]
     * @return array{0: array<string, mixed>, 1: int, 2: bool} [yanıt, statusCode, replayed]
     */
    public function run(int $tenantId, string $opId, string $scope, array $payload, callable $operation): array
    {
        $hash = $this->hash($payload);

        $claim = new IdempotencyKey([
            'op_id' => $opId,
            'scope' => $scope,
            'request_hash' => $hash,
            'status' => 'processing',
        ]);
        $claim->tenant_id = $tenantId;
        $claim->created_at = now();

        try {
            $claim->save();
        } catch (QueryException $e) {
            if (! $this->isDuplicate($e)) {
                throw $e;
            }

            return $this->replay($tenantId, $opId, $hash);
        }

        try {
            [$response, $status] = $operation();
        } catch (\Throwable $e) {
            $claim->delete(); // başarısız iş rezervasyonu tutmaz; istemci yeniden deneyebilir

            throw $e;
        }

        $claim->forceFill([
            'status' => 'completed',
            'response_snapshot' => ['status_code' => $status, 'body' => $response],
        ])->save();

        return [$response, $status, false];
    }

    /** @return array{0: array<string, mixed>, 1: int, 2: bool} */
    private function replay(int $tenantId, string $opId, string $hash): array
    {
        // İlk istek işini bitirmemiş olabilir; kısa pencere içinde bekle.
        for ($attempt = 0; $attempt < self::POLL_ATTEMPTS; $attempt++) {
            $row = IdempotencyKey::withoutTenancy()
                ->where('tenant_id', $tenantId)
                ->where('op_id', $opId)
                ->first();

            if ($row === null) {
                // İlk istek başarısız olup rezervasyonu silmiş → istemci yeniden denesin.
                throw new HttpException(409, 'Önceki istek başarısız oldu; lütfen yeniden deneyin.');
            }

            if ($row->request_hash !== $hash) {
                // AYNI op_id FARKLI gövdeyle: istemci hatası/çakışma — sessizce yutulmaz.
                throw new HttpException(409, 'op_id daha önce farklı bir istekle kullanıldı.');
            }

            if ($row->status === 'completed' && $row->response_snapshot !== null) {
                $snapshot = $row->response_snapshot;

                return [(array) ($snapshot['body'] ?? []), (int) ($snapshot['status_code'] ?? 200), true];
            }

            usleep(self::POLL_DELAY_US);
        }

        throw new HttpException(409, 'Aynı istek hâlâ işleniyor; lütfen bekleyin.');
    }

    private function isDuplicate(QueryException $e): bool
    {
        $sqlState = $e->errorInfo[0] ?? null;
        $code = $e->errorInfo[1] ?? null;

        return $sqlState === '23000' || $sqlState === '23505' || $code === 1062 || $code === 19;
    }

    /**
     * @param  array<string, mixed>  $payload
     */
    private function hash(array $payload): string
    {
        return hash('sha256', json_encode($this->normalize($payload), JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES));
    }

    /** Anahtar sırası isteğe göre değişse de aynı hash çıksın diye özyinelemeli sıralar. */
    private function normalize(mixed $value): mixed
    {
        if (! is_array($value)) {
            return $value;
        }

        ksort($value);

        return array_map(fn ($v) => $this->normalize($v), $value);
    }
}
