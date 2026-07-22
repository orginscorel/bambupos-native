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
                <!-- Marka: ürün-nötr (müşteri adı/logosu yok) -->
                <div class="mb-6 flex flex-col items-center gap-3">
                    <span class="flex size-12 items-center justify-center rounded-xl bg-primary text-on-primary">
                        <AppIcon name="qr-code" :size="26" />
                    </span>
                    <div class="text-center">
                        <h1 class="text-lg font-semibold text-body">{{ heading }}</h1>
                        <p v-if="subheading" class="mt-1 text-sm text-muted">{{ subheading }}</p>
                    </div>
                </div>

                <div class="rounded-lg border border-default bg-raised p-6 shadow-card">
                    <slot />
                </div>

                <div class="mt-4 text-center text-sm text-muted">
                    <slot name="footer" />
                </div>
            </div>
        </main>

        <footer class="pb-5 text-center text-xs text-subtle">powered by bogahost</footer>
    </div>
</template>
