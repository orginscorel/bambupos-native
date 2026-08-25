<?php

namespace App\Modules\Billing\Payments;

use App\Modules\Billing\Payments\Contracts\SaasPaymentProvider;
use Illuminate\Contracts\Container\Container;

/**
 * SaaS ödeme sağlayıcı kayıt defteri: anahtar → adapter (config/saas_payment.php).
 * app/Modules/Payments/Providers/ProviderRegistry ile BİREBİR AYNI DESEN
 * ("kod değil konfig değişir") — ayrı bir kayıt defteridir, POS sağlayıcı
 * haritasıyla karıştırılmaz.
 */
class SaasPaymentRegistry
{
    /** @var array<string, SaasPaymentProvider> */
    private array $resolved = [];

    public function __construct(private readonly Container $container)
    {
    }

    /** config('saas_payment.provider') içinde tanımlı AKTİF sağlayıcı. */
    public function current(): SaasPaymentProvider
    {
        return $this->get((string) config('saas_payment.provider', 'manual'));
    }

    public function get(string $key): SaasPaymentProvider
    {
        if (isset($this->resolved[$key])) {
            return $this->resolved[$key];
        }

        $map = (array) config('saas_payment.providers', []);

        if (! isset($map[$key])) {
            throw new \InvalidArgumentException("Bilinmeyen SaaS ödeme sağlayıcısı: {$key}");
        }

        $provider = $this->container->make($map[$key]);

        if (! $provider instanceof SaasPaymentProvider) {
            throw new \LogicException("{$map[$key]} SaasPaymentProvider uygulamıyor.");
        }

        return $this->resolved[$key] = $provider;
    }

    public function has(string $key): bool
    {
        return array_key_exists($key, (array) config('saas_payment.providers', []));
    }
}
