<script setup lang="ts">
/**
 * BÖLÜM BAŞLIĞI (kurumsal ayraç).
 *
 * Sayfalarda bölümler yalnız boşlukla ayrılıyordu: nerede bittiği nerede
 * başladığı belli olmuyor, boşluk da gereğinden fazla yer kaplıyordu.
 * Bu başlık ince bir çizgiyle bölümü kapatır — az yer kaplar, hiyerarşiyi
 * net kurar ve rapor/panel dilinde "kurumsal" duruşu verir.
 *
 * Kural: BÜYÜK harf, küçük punto, geniş harf aralığı; sağda opsiyonel
 * sayaç/aksiyon. Renk taşımaz — vurguyu içerik yapar.
 */
withDefaults(
    defineProps<{
        label: string;
        /** Sağda gösterilen küçük bağlam metni (sayaç, tutar, tarih…). */
        hint?: string | null;
        /** Başlığın solundaki ikon (AppIcon adı). */
        icon?: string | null;
    }>(),
    { hint: null, icon: null },
);
</script>

<template>
    <div class="flex items-center gap-2.5">
        <span class="flex shrink-0 items-center gap-1.5 text-[11px] font-bold uppercase tracking-[0.08em] text-subtle">
            <AppIcon v-if="icon" :name="icon" :size="13" />
            {{ label }}
        </span>
        <span class="h-px grow bg-(--ui-border)" aria-hidden="true"></span>
        <span v-if="hint" class="shrink-0 text-[11px] font-semibold tabular-nums text-muted">{{ hint }}</span>
        <slot name="actions" />
    </div>
</template>

<script lang="ts">
import AppIcon from './AppIcon.vue';

export default { components: { AppIcon } };
</script>
