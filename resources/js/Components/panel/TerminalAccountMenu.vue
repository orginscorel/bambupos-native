<script setup lang="ts">
/**
 * TERMİNAL HESAP/OPERATÖR MENÜSÜ (§13, denetim 2026-08-06 — header konsolidasyonu).
 *
 * SORUN: çıkış/personel-değiştir eylemleri dört terminal ekranında (Kitchen/
 * Runner/Cashier/Board) düz bir "Çıkış" butonuydu (yalnız cihaz oturumunu
 * kapatırdı — POST /terminal/logout) VE PanelLayout'ta bundan AYRI, kendi
 * başına bir "Personel değiştir / Çıkış" butonuydu. Kim aktif, personeli nasıl
 * değiştiririm, cihazdan nasıl çıkarım — üç farklı yerde, tutarsız dille.
 *
 * ÇÖZÜM: TEK dropdown — tetikleyici aktif operatörün adını gösterir; içinde
 * "Personel değiştir" (yalnız aktif operatörü temizler → TerminalOperatorGate
 * yeniden personel SEÇTİRİR, cihaz oturumu AÇIK kalır — personel barındaki
 * "Oturumumu kapat" ile AYNI eylem, bkz. TerminalOperatorGate.vue) ve "Çıkış"
 * (POST /terminal/logout — cihaz oturumunu tamamen kapatır, /giris'e döner)
 * ayrı ayrı menü öğeleridir. Backend uçları DEĞİŞMEDİ, yalnız tek yere taşındı.
 *
 * Terminal-dışı (normal panel) oturumda hiçbir şey render etmez.
 */
import { computed, ref } from 'vue';
import { usePage } from '@inertiajs/vue3';
import { api } from '@/lib/http';
import { useTerminalOperator } from '@/composables/useTerminalOperator';
import AppIcon from '@/Components/ui/AppIcon.vue';
import BaseDropdown from '@/Components/ui/BaseDropdown.vue';
import DropdownItem from '@/Components/ui/DropdownItem.vue';

const page = usePage();
// clearOperator() (composable) — YALNIZ uca POST atmakla kalmaz, ardından
// `router.reload({only:['auth']})` ile Inertia'nın `auth` prop'unu tazeler.
// Ham `api('/terminal/operator/clear')` çağrısı bunu YAPMAZ → `current` (ve
// TerminalOperatorGate'in "operatör var mı" kontrolü) sunucuda temizlenmiş
// olsa bile İSTEMCİDE eskisi gibi görünürdü (zorunlu personel-seçim ekranı
// gecikmeli/asla açılmazdı) — composable üzerinden çağrılır.
const { current, clearOperator } = useTerminalOperator();

const terminalStationLabel = computed(() => {
    const key = (page.props.auth as { terminal_station?: string | null } | null)?.terminal_station ?? '';
    const map: Record<string, string> = {
        kasa: 'Kasa',
        order_entry: 'Sipariş Girişi',
        kitchen: 'Mutfak',
        barista: 'Barista',
        nargile: 'Nargile',
        komi: 'Komi',
    };
    return map[key] ?? key;
});

const switchingOperator = ref(false);
async function switchOperator(): Promise<void> {
    // Personel barındaki "Oturumumu kapat" ile BİREBİR aynı eylem: yalnız
    // aktif operatörü temizler; TerminalOperatorGate zorunlu seçim ekranını
    // devralır. Cihaz oturumu AÇIK kalır, sipariş/ödeme verisi silinmez.
    if (switchingOperator.value) return;
    switchingOperator.value = true;
    try {
        await clearOperator();
    } catch {
        /* oturum düşmüş olabilir; TerminalOperatorGate zaten devralır */
    } finally {
        switchingOperator.value = false;
    }
}

const loggingOut = ref(false);
async function logout(): Promise<void> {
    if (loggingOut.value) return;
    loggingOut.value = true;
    try {
        await api('/terminal/logout', { method: 'POST' });
    } catch {
        /* oturum zaten düşmüş olabilir; her durumda giriş ekranına dön */
    }
    window.location.href = '/giris';
}
</script>

<template>
    <BaseDropdown menu-label="Hesap / operatör menüsü" align="right">
        <template #trigger="{ toggle, ariaAttrs }">
            <button
                type="button"
                v-bind="ariaAttrs"
                class="flex h-9 shrink-0 items-center gap-1.5 rounded-full border border-default bg-inset pr-2.5 pl-1 text-xs font-semibold text-body transition-colors duration-(--dur-fast) hover:bg-primary-soft hover:text-primary"
                :aria-label="current ? `Hesap menüsü · ${current.name}` : 'Hesap menüsü'"
                @click="toggle"
            >
                <span class="flex size-7 shrink-0 items-center justify-center rounded-full bg-primary-soft text-primary">
                    <AppIcon name="user" :size="14" />
                </span>
                <span class="hidden max-w-28 truncate sm:inline">{{ current?.name ?? 'Personel' }}</span>
                <AppIcon name="chevron-down" :size="13" class="shrink-0 text-subtle" />
            </button>
        </template>

        <div class="border-b border-default px-3 py-2">
            <p class="truncate text-sm font-bold text-body">{{ current?.name ?? 'Personel seçilmedi' }}</p>
            <p v-if="terminalStationLabel" class="truncate text-[11px] text-muted">Terminal · {{ terminalStationLabel }}</p>
        </div>

        <DropdownItem icon="users" :disabled="switchingOperator" @select="switchOperator">
            Personel değiştir
        </DropdownItem>
        <DropdownItem icon="logout" danger :disabled="loggingOut" @select="logout">
            Çıkış
        </DropdownItem>
    </BaseDropdown>
</template>
