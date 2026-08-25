<script setup lang="ts">
/**
 * TERMİNAL EKRANI ÜST ÇUBUĞU (§13, denetim 2026-08-06 — header tutarlılığı).
 *
 * Kitchen/Runner/Cashier/Board dört BAĞIMSIZ tam-ekran terminal ekranının
 * (PanelShell YOK, `kds-canvas` zemin) üst çubuğu neredeyse BİREBİR aynı
 * markup'ı dört kez tekrarlıyordu (marka bloğu, terminal rozeti, çıkış
 * butonu, tema/tam-ekran düğmeleri) — küçük sürüklenmelerle (biri "Çıkış"
 * yazıyor biri yazmıyor, ikon boyutları farklı). Bu bileşen ORTAK sol+sağ
 * çerçeveyi (marka/geri/menü ... tema/tam-ekran/hesap-menüsü) TEK yerde
 * tutar; ekrana özgü orta durum özeti (bekleyen/gecikti pill'leri vb.) ve ek
 * hızlı-aksiyon düğmeleri (şube seçici, oto-fiş, ses vb.) sayfa tarafında
 * kalır — `status` ve `actions` slot'ları ile enjekte edilir.
 *
 * Mevcut işlevler KORUNDU: geri/menü (yalnız terminal-dışı), terminal kilit
 * rozeti, hesap/operatör menüsü (TerminalAccountMenu — Personel değiştir +
 * Çıkış tek yerde), tema (sayfa kendi `useKdsTheme` örneğini tutar, burada
 * yalnız prop+emit ile yansıtılır), tam ekran (artık `fullscreenchange`
 * olayını dinleyen TEK doğru implementasyon — Kitchen'daki desen, dört
 * ekranda da aynı).
 */
import { computed, onBeforeUnmount, onMounted, ref } from 'vue';
import { usePage } from '@inertiajs/vue3';
import { api } from '@/lib/http';
import AppIcon from '@/Components/ui/AppIcon.vue';
import BaseButton from '@/Components/ui/BaseButton.vue';
import BaseDropdown from '@/Components/ui/BaseDropdown.vue';
import DropdownItem from '@/Components/ui/DropdownItem.vue';
import KdsIcon from '@/Pages/Panel/Kds/KdsIcon.vue';
import TerminalAccountMenu from '@/Components/panel/TerminalAccountMenu.vue';

const props = defineProps<{
    /** "BamBumPOS" markasının altındaki ekran adı (ör. "Mutfak Hazırlık Ekranı"). */
    screenLabel: string;
    /** Sayfanın kendi tema composable'ından (`useKdsTheme`) okunan geçerli tema. */
    theme: 'light' | 'dark';
}>();

const emit = defineEmits<{
    'toggle-theme': [];
    'open-nav': [];
}>();

const page = usePage();
const isTerminal = computed(() => Boolean((page.props.auth as { is_terminal?: boolean } | null)?.is_terminal));

/* Tam ekran: dört ekranda ayrı ayrı (ve birbirinden hafif farklı) tutulan
 * state/olay dinleyicisi buraya taşındı — Esc ile çıkışta da ikon senkron
 * kalsın diye `fullscreenchange` dinlenir (önceden yalnız Kitchen böyleydi). */
const isFullscreen = ref(Boolean(document.fullscreenElement));
function toggleFullscreen(): void {
    if (document.fullscreenElement) {
        void document.exitFullscreen();
    } else {
        void document.documentElement.requestFullscreen?.();
    }
}
function onFsChange(): void {
    isFullscreen.value = Boolean(document.fullscreenElement);
}
onMounted(() => document.addEventListener('fullscreenchange', onFsChange));
onBeforeUnmount(() => document.removeEventListener('fullscreenchange', onFsChange));

/* ---- Oturum sahibi (terminal DIŞI) ----
 * Tam ekran terminal ekranlarında kimin bağlı olduğu hiçbir yerde
 * görünmüyordu; PanelShell'de olan kullanıcı çipi burada yoktu. Yer
 * kaplamadan: baş harf rozeti + (geniş ekranda) ad; tıklayınca profil,
 * tema ve çıkış. Terminal cihazında bu alan TerminalAccountMenu'nündür
 * (operatör kavramı farklıdır) — orada gösterilmez. */
const authUser = computed(
    () => (page.props.auth as { user?: { name?: string; email?: string; position?: string | null } } | null)?.user ?? null,
);

/** Ad-soyaddan avatar baş harfleri (PanelShell ile aynı kural). */
const initials = computed(() =>
    (authUser.value?.name ?? '')
        .split(/\s+/)
        .filter(Boolean)
        .slice(0, 2)
        .map((p) => p[0]?.toLocaleUpperCase('tr-TR'))
        .join(''),
);

const loggingOut = ref(false);
async function logout(): Promise<void> {
    if (loggingOut.value) return;
    loggingOut.value = true;
    try {
        await api('/api/v1/auth/logout', { method: 'POST' });
    } catch {
        /* oturum zaten düşmüş olabilir; her durumda giriş ekranına dön */
    }
    window.location.href = '/giris';
}
</script>

<template>
    <header class="flex items-center gap-2 border-b border-default bg-raised px-3 py-1.5 shadow-[0_6px_16px_-12px_rgba(0,0,0,0.6)]">
        <!-- ===== SOL: menü (yalnız terminal-dışı) + marka + ekran adı =====
             "Panele dön" oku KALDIRILDI: aynı gezinme zaten menü çekmecesinde
             var, iki ayrı düğme yan yana yer harcıyordu. -->
        <BaseButton v-if="!isTerminal" variant="ghost" size="md" icon-only label="Menüyü aç" @click="emit('open-nav')">
            <AppIcon name="menu" :size="18" />
        </BaseButton>

        <div class="flex min-w-0 items-center gap-2">
            <span class="flex size-8 shrink-0 items-center justify-center rounded-lg bg-primary text-on-primary shadow-sm ring-1 ring-black/5">
                <AppIcon name="qr-code" :size="17" />
            </span>
            <div class="min-w-0 leading-tight">
                <p class="truncate text-[13px] font-extrabold tracking-tight text-body">BamBumPOS</p>
                <p class="truncate text-[10.5px] font-semibold uppercase tracking-wide text-muted">{{ screenLabel }}</p>
            </div>
        </div>

        <!-- ===== ORTA: ekrana özgü özet durum (bekleyen/gecikti/hazır vb.) ===== -->
        <slot name="status" />

        <!-- ===== SAĞ: ekrana özgü hızlı aksiyonlar + ortak tema/tam-ekran/hesap ===== -->
        <div class="ml-auto flex flex-wrap items-center justify-end gap-1.5">
            <slot name="actions" />

            <BaseButton
                variant="ghost"
                size="md"
                icon-only
                :label="theme === 'dark' ? 'Açık temaya geç' : 'Koyu temaya geç'"
                @click="emit('toggle-theme')"
            >
                <KdsIcon :name="theme === 'dark' ? 'sun' : 'moon'" :size="18" />
            </BaseButton>

            <BaseButton
                variant="ghost"
                size="md"
                icon-only
                :label="isFullscreen ? 'Tam ekrandan çık' : 'Tam ekran'"
                @click="toggleFullscreen"
            >
                <KdsIcon :name="isFullscreen ? 'compress' : 'expand'" :size="18" />
            </BaseButton>

            <!-- Terminal-dışı (yönetici tarayıcıda bu ekranı önizliyor) hesap/
                 operatör kavramı yok — yalnız terminal cihazında gösterilir. -->
            <TerminalAccountMenu v-if="isTerminal" />

            <!-- Terminal DIŞI: kompakt oturum çipi (baş harf + ad) -->
            <BaseDropdown v-else-if="authUser" align="right" menu-label="Hesap">
                <template #trigger="{ toggle, ariaAttrs }">
                    <button
                        type="button"
                        v-bind="ariaAttrs"
                        class="flex max-w-44 items-center gap-2 rounded-full border border-default bg-inset py-1 pe-2.5 ps-1 text-start transition hover:border-strong"
                        :title="authUser.name"
                        @click="toggle"
                    >
                        <span class="flex size-7 shrink-0 items-center justify-center rounded-full bg-primary-soft text-[11px] font-bold text-primary">
                            {{ initials || '•' }}
                        </span>
                        <span class="hidden min-w-0 flex-col leading-tight md:flex">
                            <span class="truncate text-xs font-semibold text-body">{{ authUser.name }}</span>
                            <span v-if="authUser.position" class="truncate text-[10.5px] text-muted">{{ authUser.position }}</span>
                        </span>
                        <AppIcon name="chevron-down" :size="14" class="hidden shrink-0 text-subtle md:block" />
                    </button>
                </template>

                <div class="border-b border-default px-3 py-2.5" @click.stop>
                    <p class="truncate text-sm font-medium text-body">{{ authUser.name }}</p>
                    <p class="truncate text-xs text-muted">{{ authUser.email }}</p>
                </div>
                <DropdownItem icon="dashboard" href="/panel">Panele dön</DropdownItem>
                <DropdownItem icon="user" href="/panel/profil">Profil ve oturumlar</DropdownItem>
                <DropdownItem :icon="theme === 'dark' ? 'sun' : 'moon'" @select="emit('toggle-theme')">
                    {{ theme === 'dark' ? 'Açık temaya geç' : 'Koyu temaya geç' }}
                </DropdownItem>
                <DropdownItem icon="logout" danger :disabled="loggingOut" @select="logout">Çıkış yap</DropdownItem>
            </BaseDropdown>
        </div>
    </header>
</template>
