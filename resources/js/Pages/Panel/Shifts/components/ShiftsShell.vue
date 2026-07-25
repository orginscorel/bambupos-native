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
    <PanelShell :title="props.title">
        <div class="flex flex-col gap-4">
            <ShiftsNav :active="props.active" />
            <slot />
        </div>
    </PanelShell>
</template>
