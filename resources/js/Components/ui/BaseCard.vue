<script setup lang="ts">
withDefaults(
    defineProps<{
        title?: string;
        /** Gövde iç boşluğunu kaldırır (tablo gömmek için) */
        flush?: boolean;
    }>(),
    { title: '', flush: false },
);
</script>

<template>
    <!-- Kart başlığı hafif TONLU bir şeritte durur ve solunda ince bir marka
         çizgisi vardır. Panel baştan sona tek renkti; kart ile içerik aynı
         yüzeyde olduğu için bölümler birbirine karışıyor ve uzun sayfalarda
         göz yoruyordu. Ton çok düşük opaklıkta (yüzde 40) — vardiya boyu
         bakılan bir ekranda doygun renk yorar. -->
    <section class="overflow-hidden rounded-lg border border-default bg-raised shadow-card">
        <header
            v-if="title || $slots.header || $slots.actions"
            class="flex min-h-11 items-center justify-between gap-3 border-b border-default px-3.5 py-2.5"
        >
            <slot name="header">
                <h2 class="text-sm font-semibold text-body">{{ title }}</h2>
            </slot>
            <slot name="actions" />
        </header>
        <div :class="flush ? '' : 'p-3.5'">
            <slot />
        </div>
        <footer v-if="$slots.footer" class="border-t border-default px-3.5 py-2.5">
            <slot name="footer" />
        </footer>
    </section>
</template>
