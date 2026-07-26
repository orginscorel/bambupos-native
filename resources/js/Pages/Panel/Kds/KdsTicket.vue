<script setup lang="ts">
import { computed } from 'vue';
import { renderTicketBody, type ReceiptData } from './useReceiptPrint';

/**
 * FİŞ ÖNİZLEMESİ — giden istasyon/teslim fişinin birebir görüntüsü.
 * Yazdırmayla TEK KAYNAK: markup `renderTicketBody()` ile üretilir (aynı
 * fonksiyon iframe yazdırmasında da kullanılır) → önizleme = çıktı.
 *
 * "Kâğıt" çerçevesi termal fişi taklit eder: dar, beyaz zemin, hafif gölge —
 * KDS teması koyu olsa bile fiş HER ZAMAN siyah-beyaz görünür (gerçek çıktı
 * gibi). Fiyat/tutar YOKTUR (KDS para görmez).
 */
const props = defineProps<{ data: ReceiptData }>();

const html = computed(() => renderTicketBody(props.data));
</script>

<template>
    <div class="flex justify-center">
        <!-- eslint-disable-next-line vue/no-v-html — içerik uygulama tarafından üretilir + esc()'lenir -->
        <div
            class="kds-ticket-paper"
            v-html="html"
        />
    </div>
</template>

<style scoped>
/*
 * Termal kâğıt görünümü — sabit beyaz zemin (KDS temasından bağımsız),
 * dar genişlik (~80mm hissi), kesikli üst/alt kenar, hafif gölge.
 */
.kds-ticket-paper {
    width: 300px;
    max-width: 100%;
    background: #fff;
    color: #000;
    padding: 12px 10px;
    border-radius: 2px;
    box-shadow: 0 6px 24px -8px rgba(0, 0, 0, 0.45);
    border: 1px solid #e5e5e5;
}
</style>
