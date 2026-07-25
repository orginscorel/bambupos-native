<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * SERVİS TİPİ yapısal kolonu (kullanıcı 2026-07-25): dine_in / takeaway /
 * package. Önceden yalnız kiosk personel notuna gömülüydü ("Masada servis ·
 * Masa: …") — kanıtlandığı gibi orders'ta ayrı kolon YOKTU; bu yüzden
 * Board/Detail/KDS tip etiketi tutarsızdı. Artık `service_type` tek kaynaktır.
 *
 * `service_type` GÜVENLİ ad (MariaDB rezerve kelime değil). Kanaldan bağımsız:
 * aynı kanaldan (kiosk) her üç tip de gelebilir.
 *
 * Geriye dönük doldurma:
 *  - package kanalı → package; pickup → takeaway; table/qr → dine_in.
 *  - kiosk: personel notundaki eski etiketten çıkarılır (Gel-al/Paket),
 *    yoksa dine_in (varsayılan).
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('orders', function (Blueprint $table) {
            $table->string('service_type', 20)->nullable()->after('channel');
        });

        // Kanal-türevi varsayılan (kiosk hariç).
        DB::table('orders')->where('channel', 'package')->update(['service_type' => 'package']);
        DB::table('orders')->where('channel', 'pickup')->update(['service_type' => 'takeaway']);
        DB::table('orders')->whereIn('channel', ['table', 'qr'])->update(['service_type' => 'dine_in']);

        // Kiosk: eski nota gömülü tipi çıkar (aksi halde dine_in).
        DB::table('orders')->where('channel', 'kiosk')->where('note', 'like', 'Gel-al%')
            ->update(['service_type' => 'takeaway']);
        DB::table('orders')->where('channel', 'kiosk')->where('note', 'like', 'Paket%')
            ->update(['service_type' => 'package']);
        DB::table('orders')->where('channel', 'kiosk')->whereNull('service_type')
            ->update(['service_type' => 'dine_in']);

        // Kalan tüm boşluklar (bilinmeyen kanal) → dine_in.
        DB::table('orders')->whereNull('service_type')->update(['service_type' => 'dine_in']);
    }

    public function down(): void
    {
        Schema::table('orders', function (Blueprint $table) {
            $table->dropColumn('service_type');
        });
    }
};
