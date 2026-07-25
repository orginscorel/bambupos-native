<?php

namespace App\Modules\Reservations\Support;

use App\Modules\Identity\Models\User;
use App\Modules\Reservations\Models\Reservation;
use App\Modules\Reservations\Models\WaitlistEntry;
use App\Modules\Tables\Models\Table;

/**
 * Rezervasyon sunucu-taraflı sunumu.
 *
 * GÜVENLİK: allergy_note (sağlık verisi) yalnız reservations.view_sensitive
 * iznine sahip kullanıcıya serileştirilir; izinsiz kullanıcıya alanın
 * VARLIĞI (has_allergy_note bayrağı) gösterilir ama içeriği asla gitmez.
 */
class ReservationPresenter
{
    /** @return array<string, mixed> */
    public static function panelView(Reservation $reservation, User $viewer): array
    {
        $canSeeSensitive = $viewer->hasPermission('reservations.view_sensitive');

        return [
            'id' => $reservation->id,
            'branch_id' => $reservation->branch_id,
            'customer_name' => $reservation->customer_name,
            'customer_phone' => $reservation->customer_phone,
            'customer_email' => $reservation->customer_email,
            'reserved_at' => $reservation->reserved_at->toIso8601String(),
            // Gösterim şube saat dilimindedir (giriş de öyle yorumlanır).
            'reserved_date' => $reservation->localReservedAt()->format('Y-m-d'),
            'reserved_time' => $reservation->localReservedAt()->format('H:i'),
            'ends_at' => $reservation->endsAt()->toIso8601String(),
            'blocks_until' => $reservation->blocksUntil()->toIso8601String(),
            'duration_minutes' => (int) $reservation->duration_minutes,
            'buffer_minutes' => (int) $reservation->buffer_minutes,
            'party_size' => (int) $reservation->party_size,
            'area_id' => $reservation->area_id,
            'area_name' => $reservation->area?->name,
            'special_note' => $reservation->special_note,
            // Hassas alan: içerik yalnız yetkiliye; diğerlerine yalnız bayrak.
            'has_allergy_note' => filled($reservation->allergy_note),
            'allergy_note' => $canSeeSensitive ? $reservation->allergy_note : null,
            'occasion' => $reservation->occasion,
            'occasion_note' => $reservation->occasion_note,
            'deposit_minor' => (int) $reservation->deposit_minor,
            'deposit_status' => $reservation->deposit_status->value,
            'deposit_status_label' => $reservation->deposit_status->label(),
            'deposit_status_variant' => $reservation->deposit_status->variant(),
            'source' => $reservation->source->value,
            'source_label' => $reservation->source->label(),
            'created_by' => $reservation->created_by,
            'created_by_name' => $reservation->creator?->name,
            'status' => $reservation->status->value,
            'status_label' => $reservation->status->label(),
            'status_icon' => $reservation->status->icon(),
            'status_variant' => $reservation->status->variant(),
            'allowed_transitions' => array_map(
                fn ($s) => $s->value,
                $reservation->status->allowedTransitions(),
            ),
            'cancel_reason' => $reservation->cancel_reason,
            'reminder_status' => $reservation->reminder_status,
            'reminder_sent_at' => $reservation->reminder_sent_at?->toIso8601String(),
            'confirmed_at' => $reservation->confirmed_at?->toIso8601String(),
            'arrived_at' => $reservation->arrived_at?->toIso8601String(),
            'seated_at' => $reservation->seated_at?->toIso8601String(),
            'tables' => $reservation->tables->map(fn (Table $t): array => [
                'id' => $t->id,
                'name' => $t->name,
                'number' => $t->number,
                'capacity' => (int) $t->capacity,
            ])->values()->all(),
            'created_at' => $reservation->created_at?->toIso8601String(),
        ];
    }

    /** Public görünüm (müşteri onay/iptal sayfası + QR talep yanıtı). */
    public static function publicView(Reservation $reservation): array
    {
        return [
            'code' => 'R'.str_pad((string) $reservation->id, 6, '0', STR_PAD_LEFT),
            'customer_name' => $reservation->customer_name,
            'reserved_at' => $reservation->reserved_at->toIso8601String(),
            'reserved_date' => $reservation->localReservedAt()->format('d.m.Y'),
            'reserved_time' => $reservation->localReservedAt()->format('H:i'),
            'party_size' => (int) $reservation->party_size,
            'status' => $reservation->status->value,
            'status_label' => $reservation->status->label(),
        ];
    }

    /** @return array<string, mixed> */
    public static function waitlistView(WaitlistEntry $entry, int $position, int $slotMinutes): array
    {
        $estimated = $entry->quoted_wait_minutes ?? max(1, $position) * $slotMinutes;

        return [
            'id' => $entry->id,
            'branch_id' => $entry->branch_id,
            'customer_name' => $entry->customer_name,
            'customer_phone' => $entry->customer_phone,
            'party_size' => (int) $entry->party_size,
            'note' => $entry->note,
            'status' => $entry->status->value,
            'status_label' => $entry->status->label(),
            'status_icon' => $entry->status->icon(),
            'status_variant' => $entry->status->variant(),
            'position' => $entry->status->isOpen() ? $position : null,
            'quoted_wait_minutes' => $entry->quoted_wait_minutes,
            'estimated_wait_minutes' => $entry->status->isOpen() ? $estimated : null,
            'waiting_since' => $entry->created_at?->toIso8601String(),
            'notified_at' => $entry->notified_at?->toIso8601String(),
            'seated_at' => $entry->seated_at?->toIso8601String(),
            'reservation_id' => $entry->reservation_id,
        ];
    }
}
