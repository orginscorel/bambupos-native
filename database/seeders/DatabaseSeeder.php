<?php

namespace Database\Seeders;

use Illuminate\Database\Seeder;

class DatabaseSeeder extends Seeder
{
    public function run(): void
    {
        $this->call([
            PermissionSeeder::class,
            DemoTenantSeeder::class,
            StaffRoleDefaultsSeeder::class, // var olan kiracılara şablon rol varsayılanları
            CatalogSeeder::class,
            ProductNutritionSeeder::class, // tahmini gramaj+kalori (CatalogSeeder'dan SONRA; yalnız boş alanları doldurur, idempotent)
            InventorySeeder::class, // stok/depo demo verisi (CatalogSeeder'dan SONRA: reçeteler ürünlere bağlanır)
            ShiftsSeeder::class, // vardiya/mesai demo verisi (DemoTenantSeeder'dan SONRA: roller + şube hazır)
            DemoOrdersSeeder::class, // §12 karışık açık adisyon (Mutfak+Barista) — CatalogSeeder'dan SONRA, idempotent
            FeatureSeeder::class, // §9 Eklentiler: demo kiracıda tüm opsiyonel özellikler açık (DemoTenantSeeder'dan SONRA)
        ]);
    }
}
