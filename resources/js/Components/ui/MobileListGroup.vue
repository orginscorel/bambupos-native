<script setup lang="ts">
/**
 * Gruplu liste kabı (iOS "inset grouped" hissi): beyaz yüzey, yumuşak köşe,
 * satırlar arasında ince hairline ayraç. Her satır AYRI kart DEĞİL — tek yüzey.
 * İçine `ListRow` / `InfoRow` konur. Opsiyonel üst başlık (`SectionHeader` yerine
 * hızlı kullanım için `label`).
 */
withDefaults(
    defineProps<{
        /** Grup üstü küçük başlık (opsiyonel). */
        label?: string;
        /** Grup altı yardımcı/açıklama metni (opsiyonel). */
        footnote?: string;
    }>(),
    {},
);
</script>

<template>
    <section>
        <p
            v-if="label"
            class="px-4 pb-1.5 text-[12px] font-semibold tracking-wide text-subtle uppercase"
        >
            {{ label }}
        </p>
        <div
            class="stagger-in overflow-hidden rounded-2xl border border-default bg-surface shadow-card
                   [&>*:not(:last-child)]:border-b [&>*:not(:last-child)]:border-default/70"
        >
            <slot />
        </div>
        <p v-if="footnote" class="px-4 pt-1.5 text-[12px] leading-relaxed text-subtle">
            {{ footnote }}
        </p>
    </section>
</template>
