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
            InventorySeeder::class, // stok/depo demo verisi (CatalogSeeder'dan SONRA: reçeteler ürünlere bağlanır)
            ShiftsSeeder::class, // vardiya/mesai demo verisi (DemoTenantSeeder'dan SONRA: roller + şube hazır)
        ]);
    }
}
