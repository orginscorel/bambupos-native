<?php

namespace Tests\Unit\Catalog;

use App\Modules\Catalog\Support\Money;
use PHPUnit\Framework\TestCase;

/** ADR-007: kuruş-integer para + tek noktada half-up yuvarlama. */
class MoneyTest extends TestCase
{
    public function test_tr_ve_nokta_bicimli_tutarlar_kurusa_cevrilir(): void
    {
        $this->assertSame(12550, Money::parseToMinor('125,50'));
        $this->assertSame(12550, Money::parseToMinor('125.50'));
        $this->assertSame(125000, Money::parseToMinor('1.250,00')); // TR binlik
        $this->assertSame(12500, Money::parseToMinor(125));
        $this->assertSame(0, Money::parseToMinor('0'));
        $this->assertNull(Money::parseToMinor(''));
        $this->assertNull(Money::parseToMinor(null));
        $this->assertNull(Money::parseToMinor('abc'));
    }

    public function test_kdv_dahil_bruttan_net_ve_kdv_payi(): void
    {
        // 110,00 ₺ brüt, %10 KDV → net 100,00 ₺, KDV 10,00 ₺
        $this->assertSame(10000, Money::netFromGross(11000, 10.0));
        $this->assertSame(1000, Money::vatPortionOfGross(11000, 10.0));

        // KDV payı + net = brüt her zaman tutar (yuvarlama tutarlılığı)
        foreach ([9999, 12345, 33333, 1, 99999999] as $gross) {
            foreach ([1.0, 8.0, 10.0, 18.0, 20.0] as $rate) {
                $this->assertSame(
                    $gross,
                    Money::netFromGross($gross, $rate) + Money::vatPortionOfGross($gross, $rate),
                    "brüt={$gross} oran={$rate}",
                );
            }
        }
    }

    public function test_nete_kdv_ekleme_half_up_yuvarlar(): void
    {
        // 100,00 ₺ net + %10 → 110,00 ₺
        $this->assertSame(11000, Money::grossFromNet(10000, 10.0));
        // 33,33 ₺ net + %18 → 3333 * 1.18 = 3932.94 → 3933 kuruş
        $this->assertSame(3933, Money::grossFromNet(3333, 18.0));
        // Oran 0 → değişmez
        $this->assertSame(3333, Money::grossFromNet(3333, 0.0));
    }

    public function test_yuzde_hesabi_half_up(): void
    {
        $this->assertSame(500, Money::percent(10000, 5.0));
        // 1001 × %5 = 50.05 → 50 kuruş; 1010 × %5 = 50.5 → 51 kuruş (half-up)
        $this->assertSame(50, Money::percent(1001, 5.0));
        $this->assertSame(51, Money::percent(1010, 5.0));
    }

    public function test_gorsel_bicim(): void
    {
        $this->assertSame('125,50', Money::toDecimalString(12550));
        $this->assertSame('1.250,00', Money::toDecimalString(125000));
        $this->assertSame('0,00', Money::toDecimalString(0));
    }
}
