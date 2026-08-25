<script setup lang="ts">
import PanelShell from '@/Components/panel/PanelShell.vue';
import ShiftsNav from './ShiftsNav.vue';

/**
 * Vardiya & Mesai bölümü kabuğu: PanelShell + iki kademeli gruplu gezinme.
 * Ekranlar 5 gruba toplanır ve her grup tek satırda anlatılır (ShiftsNav);
 * izne göre süzme ShiftsNav içinde yapılır. `active` = bulunulan ekranın anahtarı.
 */
const props = defineProps<{ title: string; active: string }>();
</script>

<template>
    <PanelShell :title="props.title" flush canvas>
        <div class="shrink-0 border-b border-default bg-raised px-4 py-2.5 sm:px-6">
            <ShiftsNav :active="props.active" />
        </div>

        <div class="min-h-0 flex-1 overflow-y-auto p-3 pb-24 sm:p-4 lg:pb-4">
        <div class="mx-auto flex w-full max-w-[1440px] flex-col gap-3">

        <div class="flex flex-col gap-4">
            <slot />
        </div>
        </div>
        </div>
    </PanelShell>
</template>
