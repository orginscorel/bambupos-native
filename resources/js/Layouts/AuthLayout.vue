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

/* Sol paneldeki kısa tanıtım — ürünün ne yaptığını giriş anında söyler. */
const features = [
    { i: 'utensils', t: 'Adisyon ve masa yönetimi', d: 'Masa panosu, sipariş girişi, mutfağa gönderme' },
    { i: 'wallet', t: 'Kasa ve tahsilat', d: 'Nakit, kart, kısmi ödeme, borç tahsilatı, Z raporu' },
    { i: 'chef-hat', t: 'Mutfak ve barista ekranları', d: 'Kulvar kuyruğu, gecikme uyarısı, termal fiş' },
    { i: 'chart', t: 'Rapor ve stok', d: 'Ciro, ürün, personel raporları; reçete ve sayım' },
];
</script>

<template>
    <!-- ================= GİRİŞ EKRANI (yeniden tasarım) =================
         Eski ekran ortalanmış tek bir kart ve nötr gri zemindi: bir POS
         uygulamasının açılışından çok "form sayfası" gibi duruyordu.

         Yeni düzen iki panelli: SOLDA markalı koyu panel (ürün kimliği +
         ekranların kısa tanıtımı), SAĞDA giriş formu. Dar ekranda sol panel
         ince bir marka şeridine iner — telefonda form ekranı doldurur.

         Uygulama içinde açıldığında (tam ekran, tarayıcı çubuğu yok) bu
         düzen "gerçek uygulama açılışı" hissi verir. -->
    <div class="auth-root fixed inset-0 flex overflow-hidden">

        <!-- ===== SOL: marka paneli (lg+) ===== -->
        <aside class="auth-brand relative hidden w-[42%] max-w-xl flex-col justify-between p-10 lg:flex">
            <div class="flex items-center gap-3">
                <span class="flex size-11 items-center justify-center rounded-xl bg-white/15 text-white ring-1 ring-white/20">
                    <AppIcon name="qr-code" :size="22" />
                </span>
                <div class="leading-tight">
                    <p class="text-lg font-extrabold tracking-tight text-white">BamBumPOS</p>
                    <p class="text-[11px] font-semibold uppercase tracking-[0.16em] text-white/60">
                        Restoran &amp; Kafe Yönetimi
                    </p>
                </div>
            </div>

            <div>
                <h2 class="max-w-md text-3xl font-bold leading-snug text-white">
                    Adisyondan kasaya, mutfaktan stoğa tek ekran.
                </h2>
                <ul class="mt-7 flex flex-col gap-3.5">
                    <li v-for="f in features" :key="f.t" class="flex items-start gap-3">
                        <span class="mt-0.5 flex size-8 shrink-0 items-center justify-center rounded-lg bg-white/12 text-white ring-1 ring-white/15">
                            <AppIcon :name="f.i" :size="16" />
                        </span>
                        <span class="min-w-0">
                            <span class="block text-sm font-semibold text-white">{{ f.t }}</span>
                            <span class="block text-[13px] leading-snug text-white/65">{{ f.d }}</span>
                        </span>
                    </li>
                </ul>
            </div>

            <p class="text-xs text-white/50">
                powered by
                <a href="https://bogahost.com" target="_blank" rel="noopener" class="font-semibold text-white/75 hover:text-white">bogahost.com</a>
            </p>
        </aside>

        <!-- ===== SAĞ: giriş formu ===== -->
        <main class="relative flex min-w-0 flex-1 flex-col overflow-y-auto bg-surface">
            <!-- Üst şerit: mobil marka + tema düğmesi -->
            <header class="flex shrink-0 items-center justify-between gap-3 p-4 sm:px-6">
                <div class="flex items-center gap-2.5 lg:invisible">
                    <span class="flex size-9 items-center justify-center rounded-lg bg-primary text-on-primary shadow-sm">
                        <AppIcon name="qr-code" :size="18" />
                    </span>
                    <span class="text-[15px] font-extrabold tracking-tight text-body">BamBumPOS</span>
                </div>
                <button
                    type="button"
                    class="flex size-10 shrink-0 items-center justify-center rounded-lg text-muted transition-colors duration-(--dur-fast) hover:bg-inset hover:text-body"
                    :aria-label="theme === 'dark' ? 'Açık temaya geç' : 'Koyu temaya geç'"
                    @click="toggleTheme"
                >
                    <AppIcon :name="theme === 'dark' ? 'sun' : 'moon'" :size="18" />
                </button>
            </header>

            <div class="flex grow items-center justify-center px-4 pb-10 sm:px-6">
                <div class="w-full" :class="wide ? 'max-w-md' : 'max-w-sm'">
                    <div class="mb-6">
                        <h1 class="text-2xl font-bold tracking-tight text-body">{{ heading }}</h1>
                        <p v-if="subheading" class="mt-2 text-sm leading-relaxed text-muted">{{ subheading }}</p>
                    </div>

                    <slot />

                    <div class="mt-5 text-sm text-muted">
                        <slot name="footer" />
                    </div>
                </div>
            </div>

            <footer class="shrink-0 pb-5 text-center text-xs text-subtle lg:hidden">
                powered by
                <a href="https://bogahost.com" target="_blank" rel="noopener" class="font-semibold text-muted hover:text-body">bogahost.com</a>
            </footer>
        </main>
    </div>
</template>

<style scoped>
/*
 * Marka paneli: markanın morundan koyulaşan eğik geçiş + çok hafif ışık
 * düşümü. Renk --ui-primary'den türer; koyu temada da tutarlı kalır.
 */
.auth-brand {
    background-image:
        radial-gradient(900px 420px at 20% 0%, rgb(255 255 255 / 0.10), transparent 60%),
        linear-gradient(160deg, var(--ui-primary) 0%, color-mix(in srgb, var(--ui-primary) 62%, #000) 100%);
}
.auth-root {
    background-color: var(--ui-surface);
}
</style>
