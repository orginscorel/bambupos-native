<script setup lang="ts">
import { useTheme } from '@/composables/useTheme';
import AppIcon from '@/Components/ui/AppIcon.vue';

defineProps<{
    /** Kart başlığı (ör. "Giriş yap") */
    heading: string;
    /** Başlık altı kısa açıklama */
    subheading?: string;
    /** Kart genişliği: form ekranları sm, PIN ekranı md */
    wide?: boolean;
}>();

const { theme, toggleTheme } = useTheme();
</script>

<template>
    <div class="flex min-h-dvh flex-col bg-surface-alt">
        <!-- Üst: tema düğmesi (sağ köşe) -->
        <header class="flex justify-end p-3">
            <button
                type="button"
                class="flex size-10 items-center justify-center rounded-md text-muted transition-colors duration-(--dur-fast) hover:bg-inset hover:text-body"
                :aria-label="theme === 'dark' ? 'Açık temaya geç' : 'Koyu temaya geç'"
                @click="toggleTheme"
            >
                <AppIcon :name="theme === 'dark' ? 'sun' : 'moon'" :size="18" />
            </button>
        </header>

        <main class="flex grow items-start justify-center px-4 pt-6 pb-10 sm:items-center sm:pt-0">
            <div class="w-full" :class="wide ? 'max-w-md' : 'max-w-sm'">
                <!-- Ürün kimliği: BamBumPOS (kiracıdan bağımsız, sabit) -->
                <div class="mb-7 flex flex-col items-center gap-3 text-center">
                    <span class="flex size-14 items-center justify-center rounded-2xl bg-primary text-on-primary shadow-lg ring-1 ring-black/5">
                        <AppIcon name="qr-code" :size="28" />
                    </span>
                    <div>
                        <p class="text-2xl font-extrabold tracking-tight text-body">BamBumPOS</p>
                        <p class="mt-0.5 text-[11px] font-semibold uppercase tracking-[0.14em] text-muted">Restoran &amp; Kafe Yönetimi</p>
                    </div>
                </div>

                <!-- Kart: NET başlık + form -->
                <div class="rounded-2xl border border-default bg-raised p-6 shadow-card sm:p-7">
                    <div class="mb-5">
                        <h1 class="text-xl font-bold tracking-tight text-body">{{ heading }}</h1>
                        <p v-if="subheading" class="mt-1.5 text-sm leading-relaxed text-muted">{{ subheading }}</p>
                    </div>
                    <slot />
                </div>

                <div class="mt-4 text-center text-sm text-muted">
                    <slot name="footer" />
                </div>
            </div>
        </main>

        <footer class="pb-5 text-center text-xs text-subtle">
            powered by <a href="https://bogahost.com" target="_blank" rel="noopener" class="font-semibold text-muted hover:text-body">bogahost.com</a>
        </footer>
    </div>
</template>
