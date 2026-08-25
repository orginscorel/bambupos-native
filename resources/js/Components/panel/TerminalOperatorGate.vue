<script setup lang="ts">
/**
 * TERMINAL PERSONEL GİRİŞ GATE'İ + PERSONEL BARI (§13 Faz C-3).
 *
 * Terminal cihazında (is_terminal) İŞLEMİ YAPAN kişinin belli olması için:
 *  - Aktif operatör YOKSA → tam-ekran ZORUNLU giriş (personel listesi + PIN).
 *    Girişte sunucu otomatik mesai başlatır (clock-in). Terminal ekranı bu
 *    gate açıkken kullanılamaz.
 *  - Aktif operatör VARSA → sağ-altta personel barı: kim çalışıyor, ne zaman
 *    başladı, bugün kaç mola, açtığı adisyon / eklediği-iptal ürün + "Oturumu
 *    kapat". Çıkış YALNIZ operatörü temizler — sipariş/ödeme verileri SİLİNMEZ,
 *    cihaz oturumu kapanmaz; yeni personel kendi girişini yapar.
 *
 * Normal (terminal olmayan) oturumda hiçbir şey render etmez.
 */
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import { ApiError } from '@/lib/http';
import { useToast } from '@/composables/useToast';
import {
    useTerminalOperator,
    type TerminalStaffOption,
    type TerminalOperatorStats,
} from '@/composables/useTerminalOperator';
import AppIcon from '@/Components/ui/AppIcon.vue';
import BaseButton from '@/Components/ui/BaseButton.vue';

const { success, danger } = useToast();
const { isTerminal, current, loadOperators, setOperator, clearOperator, loadStats } =
    useTerminalOperator();

/* ---- Giriş (operatör yok) ---- */
const operators = ref<TerminalStaffOption[]>([]);
const listLoading = ref(false);
const selectedId = ref<number | null>(null);
const pin = ref('');
const submitting = ref(false);
const loginError = ref('');

/** Yanlış PIN'de PIN noktalarını sars (native geri bildirim). */
const shakeError = ref(false);
function triggerShake(): void {
    shakeError.value = false;
    requestAnimationFrame(() => {
        shakeError.value = true;
        setTimeout(() => (shakeError.value = false), 420);
    });
}

const selectedName = computed(
    () => operators.value.find((o) => o.id === selectedId.value)?.name ?? '',
);

async function refreshList(): Promise<void> {
    listLoading.value = true;
    try {
        operators.value = await loadOperators();
    } catch {
        /* liste boş kalır */
    } finally {
        listLoading.value = false;
    }
}

function pickStaff(id: number): void {
    selectedId.value = id;
    pin.value = '';
    loginError.value = '';
}

function pinKey(d: string): void {
    if (d === 'del') {
        pin.value = pin.value.slice(0, -1);
        return;
    }
    if (pin.value.length < 12) pin.value += d;
}

async function submitLogin(): Promise<void> {
    if (submitting.value || selectedId.value === null || pin.value.length < 4) return;
    submitting.value = true;
    loginError.value = '';
    try {
        const op = await setOperator(selectedId.value, pin.value);
        success('Giriş yapıldı', `${op.name} · mesai başlatıldı`);
        selectedId.value = null;
        pin.value = '';
    } catch (e) {
        loginError.value = e instanceof ApiError ? e.displayMessage : 'PIN doğrulanamadı.';
        pin.value = '';
        triggerShake();
    } finally {
        submitting.value = false;
    }
}

/* ---- Personel barı (operatör var) ---- */
const stats = ref<TerminalOperatorStats | null>(null);
let statsTimer: ReturnType<typeof setInterval> | null = null;
const clockTick = ref(Date.now());
let clockTimer: ReturnType<typeof setInterval> | null = null;
const loggingOut = ref(false);
const barOpen = ref(true);

async function refreshStats(): Promise<void> {
    if (!current.value) return;
    try {
        stats.value = await loadStats();
    } catch {
        /* geçici hata */
    }
}

/** İşe başlama süresi (canlı): "2 sa 14 dk" */
const workedLabel = computed(() => {
    void clockTick.value;
    const iso = stats.value?.shift_start;
    if (!iso) return null;
    const mins = Math.max(0, Math.floor((Date.now() - new Date(iso).getTime()) / 60000));
    if (mins < 60) return `${mins} dk`;
    return `${Math.floor(mins / 60)} sa ${String(mins % 60).padStart(2, '0')} dk`;
});

const startClock = computed(() => {
    const iso = stats.value?.shift_start;
    if (!iso) return '';
    try {
        return new Date(iso).toLocaleTimeString('tr-TR', { hour: '2-digit', minute: '2-digit' });
    } catch {
        return '';
    }
});

/** Mesai ilerleme çubuğu: 8 saatlik standart vardiyaya göre % (görsel his). */
const SHIFT_TARGET_MIN = 8 * 60;
const shiftPct = computed<number>(() => {
    void clockTick.value;
    const iso = stats.value?.shift_start;
    if (!iso) return 0;
    const mins = Math.max(0, Math.floor((Date.now() - new Date(iso).getTime()) / 60000));
    return Math.min(100, Math.round((mins / SHIFT_TARGET_MIN) * 100));
});

async function doLogout(): Promise<void> {
    if (loggingOut.value) return;
    loggingOut.value = true;
    try {
        await clearOperator();
        stats.value = null;
        void refreshList();
    } catch (e) {
        danger('Çıkış yapılamadı', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen hata.');
    } finally {
        loggingOut.value = false;
    }
}

/* Operatör değişince (giriş/çıkış) stats'i HEMEN tazele — aksi halde yeni giren
 * personel 30 sn boyunca "Mesai kaydı yok" görürdü (clock-in olmasına rağmen). */
watch(current, (op) => {
    if (op) void refreshStats();
    else stats.value = null;
});

/* Zorunlu giriş gate'i açıkken arka plan kaydırmasını KİLİTLE (odak/scroll arka
 * plandaki KDS'e kaçmasın). */
watch(
    () => isTerminal.value && !current.value,
    (locked) => {
        if (typeof document !== 'undefined') document.body.style.overflow = locked ? 'hidden' : '';
    },
    { immediate: true },
);

/* ---- Yaşam döngüsü ---- */
onMounted(() => {
    if (!isTerminal.value) return;
    if (current.value) {
        void refreshStats();
    } else {
        void refreshList();
    }
    statsTimer = setInterval(() => void refreshStats(), 30000);
    clockTimer = setInterval(() => (clockTick.value = Date.now()), 30000);
});

onBeforeUnmount(() => {
    if (statsTimer) clearInterval(statsTimer);
    if (clockTimer) clearInterval(clockTimer);
    if (typeof document !== 'undefined') document.body.style.overflow = '';
});
</script>

<template>
    <template v-if="isTerminal">
        <!-- ============ ZORUNLU GİRİŞ (operatör yok) ============ -->
        <div
            v-if="!current"
            class="fixed inset-0 z-[120] flex items-start justify-center overflow-y-auto bg-overlay/90 px-3 py-4 backdrop-blur-2xl backdrop-saturate-50 sm:items-center sm:px-4"
            role="dialog"
            aria-modal="true"
            aria-label="Personel girişi"
        >
            <div class="animate-gate-in my-auto flex max-h-[calc(100dvh-2rem)] w-full max-w-2xl flex-col overflow-hidden rounded-2xl border border-default bg-raised shadow-modal">
                <div class="shrink-0 border-b border-default px-5 py-3.5 sm:px-6 sm:py-4">
                    <h2 class="flex items-center gap-2 text-base font-bold text-body sm:text-lg">
                        <AppIcon name="users" :size="20" class="text-primary" />
                        Personel Girişi
                    </h2>
                    <p class="mt-0.5 text-[13px] text-muted sm:text-sm">
                        Devam etmek için kendini seç ve PIN'ini gir. Giriş yapınca mesain otomatik başlar.
                    </p>
                </div>

                <div class="grid min-h-0 gap-0 sm:grid-cols-2">
                    <!-- Personel listesi (mobilde: personel seçilince gizlenir, PIN gelir) -->
                    <div
                        class="max-h-[calc(100dvh-11rem)] overflow-y-auto border-b border-default p-3 sm:max-h-[52vh] sm:border-r sm:border-b-0"
                        :class="selectedId !== null ? 'hidden sm:block' : ''"
                    >
                        <p v-if="listLoading" class="p-4 text-center text-sm text-muted">Yükleniyor…</p>
                        <p v-else-if="operators.length === 0" class="p-4 text-center text-sm text-muted">
                            Bu şubede seçilebilir personel yok.
                        </p>
                        <div v-else class="grid gap-2">
                            <button
                                v-for="o in operators"
                                :key="o.id"
                                type="button"
                                class="flex items-center justify-between gap-2 rounded-lg border px-3 py-2.5 text-left transition-colors duration-(--dur-fast)"
                                :class="selectedId === o.id ? 'border-primary bg-primary-soft text-primary' : 'border-default hover:bg-inset'"
                                @click="pickStaff(o.id)"
                            >
                                <span class="min-w-0">
                                    <span class="block truncate font-semibold text-body">{{ o.name }}</span>
                                    <span v-if="o.position" class="block truncate text-xs text-muted">{{ o.position }}</span>
                                </span>
                                <AppIcon v-if="selectedId === o.id" name="check-circle" :size="18" class="shrink-0" />
                            </button>
                        </div>
                    </div>

                    <!-- PIN girişi (mobilde: yalnız personel seçilince görünür) -->
                    <div class="flex-col overflow-y-auto p-4" :class="selectedId === null ? 'hidden sm:flex' : 'flex'">
                        <template v-if="selectedId !== null">
                            <!-- Mobil geri: personel listesine dön -->
                            <button
                                type="button"
                                class="mb-3 inline-flex items-center gap-1 self-start text-sm font-medium text-muted sm:hidden"
                                @click="selectedId = null; pin = ''; loginError = ''"
                            >
                                <AppIcon name="arrow-left" :size="16" /> Personel listesi
                            </button>
                            <p class="mb-1 text-sm text-muted">Seçilen</p>
                            <p class="mb-3 text-base font-bold text-body">{{ selectedName }}</p>

                            <div
                                class="mb-3 flex items-center justify-center gap-2.5"
                                :class="shakeError ? 'animate-shake' : ''"
                                aria-label="PIN"
                            >
                                <span
                                    v-for="n in Math.max(pin.length, 4)"
                                    :key="n + '-' + (n <= pin.length ? 'on' : 'off')"
                                    class="size-3.5 rounded-full transition-colors"
                                    :class="n <= pin.length ? 'animate-pop bg-primary' : 'bg-strong'"
                                />
                            </div>

                            <p v-if="loginError" class="mb-2 text-center text-sm text-danger">{{ loginError }}</p>

                            <div class="grid grid-cols-3 gap-2.5">
                                <button
                                    v-for="d in ['1','2','3','4','5','6','7','8','9']"
                                    :key="d"
                                    type="button"
                                    class="flex h-14 items-center justify-center rounded-2xl border border-default bg-surface text-2xl font-semibold text-body transition-[transform,background-color] duration-(--dur-fast) hover:bg-inset active:scale-90 active:bg-primary-soft"
                                    @click="pinKey(d)"
                                >{{ d }}</button>
                                <button
                                    type="button"
                                    class="flex h-14 items-center justify-center rounded-2xl text-muted transition-transform duration-(--dur-fast) hover:bg-inset active:scale-90"
                                    aria-label="Sil"
                                    @click="pinKey('del')"
                                >
                                    <AppIcon name="arrow-left" :size="20" />
                                </button>
                                <button
                                    type="button"
                                    class="flex h-14 items-center justify-center rounded-2xl border border-default bg-surface text-2xl font-semibold text-body transition-[transform,background-color] duration-(--dur-fast) hover:bg-inset active:scale-90 active:bg-primary-soft"
                                    @click="pinKey('0')"
                                >0</button>
                                <button
                                    type="button"
                                    class="flex h-14 items-center justify-center rounded-2xl bg-primary text-on-primary shadow-card transition-transform duration-(--dur-fast) hover:bg-primary-hover active:scale-90 disabled:opacity-50 disabled:active:scale-100"
                                    :disabled="pin.length < 4 || submitting"
                                    aria-label="Giriş yap"
                                    @click="submitLogin"
                                >
                                    <span v-if="submitting" class="size-5 animate-spin rounded-full border-2 border-current border-t-transparent" />
                                    <AppIcon v-else name="check" :size="22" />
                                </button>
                            </div>
                        </template>
                        <div v-else class="flex flex-1 flex-col items-center justify-center text-center text-muted">
                            <AppIcon name="arrow-left" :size="20" class="mb-2 hidden sm:block" />
                            <p class="text-sm">Soldan personel seç.</p>
                        </div>
                    </div>
                </div>
            </div>
        </div>

        <!-- ============ PERSONEL BARI (operatör var) ============ -->
        <div
            v-else
            class="fixed right-3 bottom-[calc(0.75rem+env(safe-area-inset-bottom))] z-40 w-[min(20rem,calc(100vw-1.5rem))] overflow-hidden rounded-xl border border-default bg-raised shadow-dropdown"
        >
            <button
                type="button"
                class="flex w-full items-center justify-between gap-2 border-b border-default px-3 py-2 text-left"
                @click="barOpen = !barOpen"
            >
                <span class="flex min-w-0 items-center gap-2">
                    <span class="flex size-8 shrink-0 items-center justify-center rounded-full bg-primary-soft text-primary">
                        <AppIcon name="user" :size="16" />
                    </span>
                    <span class="min-w-0">
                        <span class="block truncate text-sm font-bold text-body">{{ current?.name }}</span>
                        <span class="block truncate text-[11px] text-muted">
                            <template v-if="startClock">{{ startClock }}'de başladı</template>
                            <template v-else>Mesai kaydı yok</template>
                        </span>
                    </span>
                </span>
                <AppIcon :name="barOpen ? 'chevron-down' : 'chevron-up'" :size="16" class="shrink-0 text-subtle" />
            </button>

            <div v-if="barOpen" class="flex flex-col gap-2.5 p-3">
                <!-- Mesai süresi + ilerleme çubuğu (canlı) -->
                <div>
                    <div class="flex items-baseline justify-between gap-2">
                        <span class="text-[11px] font-medium text-muted">Mesai süresi</span>
                        <span class="text-sm font-bold text-body tabular-nums">{{ workedLabel ?? '—' }}</span>
                    </div>
                    <div class="mt-1 h-1.5 overflow-hidden rounded-full bg-inset" role="progressbar" :aria-valuenow="shiftPct">
                        <div class="h-full rounded-full bg-primary transition-[width] duration-(--dur-normal)" :style="{ width: shiftPct + '%' }" />
                    </div>
                    <p class="mt-1 text-[10px] text-subtle">
                        <template v-if="startClock">{{ startClock }}'de başladı</template>
                        <template v-else>Mesai kaydı yok</template>
                        <template v-if="(stats?.break_count ?? 0) > 0"> · {{ stats?.break_count }} mola ({{ stats?.break_minutes ?? 0 }} dk)</template>
                    </p>
                </div>

                <!-- Kompakt performans: adisyon · ürün · iptal (tek satır, ayraçlı) -->
                <div class="grid grid-cols-3 divide-x divide-default overflow-hidden rounded-lg border border-default bg-inset/40 text-center">
                    <div class="px-1 py-1.5">
                        <p class="text-base font-bold text-body tabular-nums">{{ stats?.orders_opened ?? 0 }}</p>
                        <p class="text-[10px] text-muted">Adisyon</p>
                    </div>
                    <div class="px-1 py-1.5">
                        <p class="text-base font-bold text-body tabular-nums">{{ stats?.items_added ?? 0 }}</p>
                        <p class="text-[10px] text-muted">Ürün</p>
                    </div>
                    <div class="px-1 py-1.5">
                        <p class="text-base font-bold tabular-nums" :class="(stats?.items_cancelled ?? 0) > 0 ? 'text-warning' : 'text-body'">
                            {{ stats?.items_cancelled ?? 0 }}
                        </p>
                        <p class="text-[10px] text-muted">İptal</p>
                    </div>
                </div>

                <BaseButton variant="secondary" size="sm" block :loading="loggingOut" @click="doLogout">
                    <AppIcon name="logout" :size="15" />
                    Oturumumu kapat
                </BaseButton>
                <p class="text-center text-[10px] text-subtle">Çıkış yalnız seni değiştirir; iş verileri silinmez.</p>
            </div>
        </div>
    </template>
</template>
