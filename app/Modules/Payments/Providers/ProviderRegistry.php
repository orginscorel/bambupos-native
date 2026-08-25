<?php

namespace App\Modules\Payments\Providers;

use App\Modules\Payments\Contracts\PaymentProviderInterface;
use App\Modules\Payments\Enums\PaymentMethod;
use App\Modules\Payments\Services\PosConfigResolver;
use Illuminate\Contracts\Container\Container;

/**
 * Sağlayıcı kayıt defteri: anahtar → adapter (config/payments.php).
 * Yeni sağlayıcı eklemek = config'e satır + interface implementasyonu;
 * çekirdek koda dokunulmaz (ADR-010 "kod değil konfig değişir").
 */
class ProviderRegistry
{
    /** @var array<string, PaymentProviderInterface> */
    private array $resolved = [];

    public function __construct(
        private readonly Container $container,
        private readonly PosConfigResolver $posConfig,
    ) {
    }

    public function get(string $key): PaymentProviderInterface
    {
        if (isset($this->resolved[$key])) {
            return $this->resolved[$key];
        }

        $map = (array) config('payments.providers', []);

        if (! isset($map[$key])) {
            throw new \InvalidArgumentException("Bilinmeyen ödeme sağlayıcısı: {$key}");
        }

        $provider = $this->container->make($map[$key]);

        if (! $provider instanceof PaymentProviderInterface) {
            throw new \LogicException("{$map[$key]} PaymentProviderInterface uygulamıyor.");
        }

        return $this->resolved[$key] = $provider;
    }

    public function has(string $key): bool
    {
        return array_key_exists($key, (array) config('payments.providers', []));
    }

    /** Yöntem için kullanılacak sağlayıcı anahtarı. */
    public function keyForMethod(PaymentMethod $method, ?string $requested = null): string
    {
        if ($requested !== null && $requested !== '' && $this->has($requested)) {
            return $requested;
        }

        if (! $method->usesTerminal()) {
            return 'cash';
        }

        // ÇOK-İŞLETMELİ ENTEGRATÖR: işletme kendi POS sağlayıcısını seçtiyse (ve kayıtlı
        // ise) onu kullan; yoksa global varsayılana düş. Böylece her işletme farklı
        // cihaz/bankaya bağlanabilir ("kod değil konfig").
        $tenantProvider = $this->posConfig->providerKey();

        if ($tenantProvider !== null && $this->has($tenantProvider)) {
            return $tenantProvider;
        }

        return (string) config('payments.default_terminal_provider', 'mock');
    }
}
