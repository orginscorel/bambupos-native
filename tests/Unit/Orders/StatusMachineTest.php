<?php

namespace Tests\Unit\Orders;

use App\Modules\Orders\Enums\OrderItemStatus;
use App\Modules\Orders\Enums\OrderStatus;
use PHPUnit\Framework\TestCase;

/** Durum makinesi tablo testi (görev §2). */
class StatusMachineTest extends TestCase
{
    public function test_terminal_durumlarin_cikisi_yoktur(): void
    {
        $this->assertSame([], OrderStatus::Cancelled->transitions());
        $this->assertSame([], OrderStatus::Refunded->transitions());
        $this->assertSame([OrderStatus::Refunded], OrderStatus::Paid->transitions());
    }

    public function test_gecerli_ana_akis(): void
    {
        $chain = [
            OrderStatus::Draft, OrderStatus::Placed, OrderStatus::SentToStation,
            OrderStatus::Accepted, OrderStatus::Preparing, OrderStatus::PartiallyReady,
            OrderStatus::Ready, OrderStatus::AwaitingService, OrderStatus::Served,
            OrderStatus::BillRequested, OrderStatus::PartiallyPaid, OrderStatus::Paid,
        ];

        for ($i = 0; $i < count($chain) - 1; $i++) {
            $this->assertTrue(
                $chain[$i]->canTransitionTo($chain[$i + 1]),
                sprintf('%s → %s geçerli olmalı', $chain[$i]->value, $chain[$i + 1]->value),
            );
        }
    }

    public function test_sacma_gecisler_reddedilir(): void
    {
        $this->assertFalse(OrderStatus::Draft->canTransitionTo(OrderStatus::Ready));
        $this->assertFalse(OrderStatus::Draft->canTransitionTo(OrderStatus::Paid));
        $this->assertFalse(OrderStatus::Paid->canTransitionTo(OrderStatus::Preparing));
        $this->assertFalse(OrderStatus::PendingApproval->canTransitionTo(OrderStatus::Served));
        $this->assertFalse(OrderStatus::Cancelled->canTransitionTo(OrderStatus::Placed));
        $this->assertFalse(OrderStatus::Refunded->canTransitionTo(OrderStatus::Placed));
    }

    public function test_kalem_yalniz_ileri_gider_ara_adim_atlayabilir(): void
    {
        // İçecek: doğrudan alındı → servis edildi
        $this->assertTrue(OrderItemStatus::Placed->canTransitionTo(OrderItemStatus::Served));
        $this->assertTrue(OrderItemStatus::Preparing->canTransitionTo(OrderItemStatus::Ready));

        // Geri dönüş yok
        $this->assertFalse(OrderItemStatus::Ready->canTransitionTo(OrderItemStatus::Preparing));
        $this->assertFalse(OrderItemStatus::Served->canTransitionTo(OrderItemStatus::Ready));

        // Servis edilen kalem iptal edilemez; öncekiler edilebilir
        $this->assertFalse(OrderItemStatus::Served->canTransitionTo(OrderItemStatus::Cancelled));
        $this->assertTrue(OrderItemStatus::Preparing->canTransitionTo(OrderItemStatus::Cancelled));
        $this->assertFalse(OrderItemStatus::Cancelled->canTransitionTo(OrderItemStatus::Placed));
    }

    public function test_her_durumun_etiket_ikon_varyanti_vardir(): void
    {
        foreach (OrderStatus::cases() as $s) {
            $this->assertNotSame('', $s->label());
            $this->assertNotSame('', $s->icon());
            $this->assertNotSame('', $s->variant());
        }

        foreach (OrderItemStatus::cases() as $s) {
            $this->assertNotSame('', $s->label());
            $this->assertNotSame('', $s->icon());
        }
    }
}
