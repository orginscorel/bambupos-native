<script setup lang="ts">
/**
 * TERMİNAL EKRAN KİLİDİ (§13, Faz D) — otomatik boşta-kalma kilidi + (ileride)
 * elle kilit için tam-ekran örtü. `useTerminalIdleLock`'un `locked` bayrağı
 * true olunca çağıran (PanelLayout) bu bileşeni render eder.
 *
 * #183 KORUNSUN: aktif operatör zaten bellidir (bu bileşen yalnız aktif
 * operatör VARKEN gösterilir — bkz. PanelLayout'taki `enabled` koşulu).
 * Devam etmek için personel yeniden SEÇİLMEZ; TEK PIN yeter — aynı personelin
 * PIN'i `useTerminalOperator().setOperator()` (mevcut `POST /terminal/operator`
 * ucu) ile yeniden doğrulanır (TerminalOperatorGate'in personel-seçim adımı
 * ATLANIR, yalnız PIN adımı tekrarlanır).
 *
 * "Farklı personel / Çıkış" bağlantısı aktif operatörü temizler; bu bileşen
 * kapanınca PanelLayout'taki TerminalOperatorGate (operatör yoksa) devreye
 * girer ve tam personel-seçim akışını sunar.
 */
import { computed, ref } from 'vue';
import { ApiError } from '@/lib/http';
import { useTerminalOperator } from '@/composables/useTerminalOperator';
import AppIcon from '@/Components/ui/AppIcon.vue';

const emit = defineEmits<{ unlocked: [] }>();

const { current, setOperator, clearOperator } = useTerminalOperator();

const pin = ref('');
const submitting = ref(false);
const error = ref('');
const shakeError = ref(false);
const switching = ref(false);

function triggerShake(): void {
    shakeError.value = false;
    requestAnimationFrame(() => {
        shakeError.value = true;
        setTimeout(() => (shakeError.value = false), 420);
    });
}

function pinKey(d: string): void {
    if (submitting.value) return;
    if (d === 'del') {
        pin.value = pin.value.slice(0, -1);
        return;
    }
    if (pin.value.length < 12) pin.value += d;
}

async function submitUnlock(): Promise<void> {
    if (submitting.value || pin.value.length < 4) return;

    // Savunma: bu bileşen normalde yalnız aktif operatör varken gösterilir.
    // Operatör düşmüşse (ör. sunucu idle-timeout araya girdi) yeniden PIN
    // sormanın anlamı yok — kapan, tam personel-seçim gate'i devralsın.
    if (!current.value) {
        emit('unlocked');
        return;
    }

    submitting.value = true;
    error.value = '';
    try {
        await setOperator(current.value.id, pin.value);
        pin.value = '';
        emit('unlocked');
    } catch (e) {
        error.value = e instanceof ApiError ? e.displayMessage : 'PIN doğrulanamadı.';
        pin.value = '';
        triggerShake();
    } finally {
        submitting.value = false;
    }
}

async function switchStaff(): Promise<void> {
    if (switching.value) return;
    switching.value = true;
    try {
        await clearOperator();
    } catch {
        /* oturum düşmüş olabilir; yine de kapat — gate devralır */
    } finally {
        switching.value = false;
        emit('unlocked');
    }
}

const operatorName = computed(() => current.value?.name ?? '');
</script>

<template>
    <div
        class="fixed inset-0 z-[130] flex items-center justify-center bg-overlay/95 px-4 backdrop-blur-2xl backdrop-saturate-50"
        role="dialog"
        aria-modal="true"
        aria-label="Ekran kilitli"
    >
        <div class="animate-gate-in flex w-full max-w-sm flex-col items-center rounded-2xl border border-default bg-raised p-6 text-center shadow-modal">
            <span class="mb-3 flex size-14 items-center justify-center rounded-full bg-primary-soft text-2xl" aria-hidden="true">
                🔒
            </span>
            <h2 class="text-base font-bold text-body sm:text-lg">Ekran kilitlendi</h2>
            <p class="mt-1 text-[13px] text-muted sm:text-sm">
                Boşta kaldığı için ekran kilitlendi.
                <template v-if="operatorName">Devam etmek için <span class="font-semibold text-body">{{ operatorName }}</span> PIN'ini gir.</template>
                <template v-else>Devam etmek için PIN gir.</template>
            </p>

            <div class="my-4 flex items-center justify-center gap-2.5" :class="shakeError ? 'animate-shake' : ''" aria-label="PIN">
                <span
                    v-for="n in Math.max(pin.length, 4)"
                    :key="n + '-' + (n <= pin.length ? 'on' : 'off')"
                    class="size-3.5 rounded-full transition-colors"
                    :class="n <= pin.length ? 'animate-pop bg-primary' : 'bg-strong'"
                />
            </div>

            <p v-if="error" class="mb-2 text-sm text-danger">{{ error }}</p>

            <div class="grid w-full grid-cols-3 gap-2.5">
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
                    aria-label="Kilidi aç"
                    @click="submitUnlock"
                >
                    <span v-if="submitting" class="size-5 animate-spin rounded-full border-2 border-current border-t-transparent" />
                    <AppIcon v-else name="check" :size="22" />
                </button>
            </div>

            <button
                type="button"
                class="mt-4 inline-flex items-center gap-1.5 text-xs font-medium text-muted transition-colors duration-(--dur-fast) hover:text-body disabled:opacity-60"
                :disabled="switching"
                @click="switchStaff"
            >
                <AppIcon name="users" :size="14" />
                Farklı personel / Çıkış
            </button>
        </div>
    </div>
</template>
