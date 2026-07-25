<script setup lang="ts">
import { computed, onMounted, ref } from 'vue';
import { Head } from '@inertiajs/vue3';
import { api, ApiError } from '@/lib/http';
import { useToast } from '@/composables/useToast';
import AppIcon from '@/Components/ui/AppIcon.vue';
import BaseButton from '@/Components/ui/BaseButton.vue';
import BaseCard from '@/Components/ui/BaseCard.vue';
import BaseInput from '@/Components/ui/BaseInput.vue';
import ShiftsShell from './components/ShiftsShell.vue';
import type { ClockResponse } from './types';
import { fmtMin, fmtTime } from './lib';

/**
 * /panel/mesai/giris-cikis — kiosk PIN ekranı.
 * - Kimlik PIN'den çözülür (oturum sahibinden değil): ortak tablette her
 *   personel kendi PIN'iyle giriş/çıkış yapar.
 * - KVKK: konum YALNIZ işletme ayarı açık + KENDİ rızası varsa okunur ve
 *   gönderilir; aksi halde tarayıcıdan konum istenmez bile.
 */
const { danger } = useToast();

const pin = ref('');
const staffCode = ref('');
const needCode = ref(false);
const busy = ref<string | null>(null);
const result = ref<ClockResponse | null>(null);
const errorMsg = ref('');

/* KVKK meta */
const locationEnabled = ref(false);
const locationPolicy = ref<string | null>(null);
const myConsent = ref(false);
const consentBusy = ref(false);

onMounted(async () => {
    try {
        const meta = await api<{ location_tracking_enabled: boolean; location_policy: string | null; my_consent: boolean }>(
            '/api/v1/shifts/clock/meta',
        );
        locationEnabled.value = meta.location_tracking_enabled;
        locationPolicy.value = meta.location_policy;
        myConsent.value = meta.my_consent;
    } catch {
        /* meta yüklenemezse konum özelliği kapalı davranır */
    }
});

function press(d: string): void {
    if (pin.value.length >= 10) return;
    pin.value += d;
}

function erase(): void {
    pin.value = pin.value.slice(0, -1);
}

/** Konum yalnız ayar + rıza varsa okunur; yoksa hiç istenmez (KVKK). */
async function readLocation(): Promise<{ lat?: number; lng?: number }> {
    if (!locationEnabled.value || !myConsent.value || !('geolocation' in navigator)) return {};
    return new Promise((resolve) => {
        navigator.geolocation.getCurrentPosition(
            (pos) => resolve({ lat: pos.coords.latitude, lng: pos.coords.longitude }),
            () => resolve({}),
            { timeout: 4000, maximumAge: 60000 },
        );
    });
}

async function act(action: 'status' | 'in' | 'out' | 'break_start' | 'break_end'): Promise<void> {
    if (pin.value.length < 6) {
        errorMsg.value = 'PIN en az 6 hanelidir.';
        return;
    }
    busy.value = action;
    errorMsg.value = '';
    try {
        const location = action === 'in' || action === 'out' ? await readLocation() : {};
        result.value = await api<ClockResponse>('/api/v1/shifts/clock', {
            method: 'POST',
            body: {
                action,
                pin: pin.value,
                staff_code: staffCode.value || null,
                ...location,
            },
        });
        needCode.value = false;
        pin.value = '';
        staffCode.value = '';
    } catch (e) {
        if (e instanceof ApiError) {
            if (e.errors.staff_code) needCode.value = true;
            errorMsg.value = e.displayMessage;
        }
    } finally {
        busy.value = null;
    }
}

async function toggleConsent(): Promise<void> {
    consentBusy.value = true;
    try {
        if (myConsent.value) {
            await api('/api/v1/shifts/location-consent', { method: 'DELETE' });
            myConsent.value = false;
        } else {
            await api('/api/v1/shifts/location-consent', { method: 'POST' });
            myConsent.value = true;
        }
    } catch (e) {
        if (e instanceof ApiError) danger('İşlem tamamlanamadı', e.displayMessage);
    } finally {
        consentBusy.value = false;
    }
}

const stateLabel = computed(() => {
    if (!result.value) return '';
    if (result.value.state.status === 'working') {
        return result.value.state.on_break ? 'Molada' : 'Mesaide';
    }
    return result.value.state.status === 'closed' ? 'Mesai tamamlandı' : 'Mesai dışı';
});
</script>

<template>
    <Head title="Giriş / Çıkış" />
    <ShiftsShell title="İşe Giriş / Çıkış" active="clock">
        <div class="mx-auto grid w-full max-w-3xl grid-cols-1 gap-4 md:grid-cols-2">
            <!-- PIN pedi -->
            <BaseCard title="PIN ile işlem">
                <div class="flex flex-col gap-3">
                    <div
                        class="flex h-12 items-center justify-center rounded-md border border-strong bg-inset text-2xl tracking-[0.4em]"
                        aria-label="Girilen PIN"
                    >
                        {{ '•'.repeat(pin.length) || ' ' }}
                    </div>

                    <div v-if="needCode">
                        <BaseInput v-model="staffCode" placeholder="Personel kodu (ör. P-100)" />
                        <p class="mt-1 text-xs text-muted">Bu PIN birden fazla personelle eşleşti; kodunuzu da girin.</p>
                    </div>

                    <p v-if="errorMsg" class="flex items-center gap-1.5 text-sm text-danger" role="alert">
                        <AppIcon name="alert-circle" :size="16" />
                        {{ errorMsg }}
                    </p>

                    <div class="grid grid-cols-3 gap-2">
                        <button
                            v-for="d in ['1', '2', '3', '4', '5', '6', '7', '8', '9']"
                            :key="d"
                            type="button"
                            class="h-12 rounded-md border border-strong bg-raised text-lg font-semibold text-body transition-colors hover:bg-inset active:bg-primary-soft"
                            @click="press(d)"
                        >
                            {{ d }}
                        </button>
                        <button
                            type="button"
                            class="h-12 rounded-md border border-strong bg-raised text-sm font-medium text-muted transition-colors hover:bg-inset"
                            @click="pin = ''"
                        >
                            Temizle
                        </button>
                        <button
                            type="button"
                            class="h-12 rounded-md border border-strong bg-raised text-lg font-semibold text-body transition-colors hover:bg-inset active:bg-primary-soft"
                            @click="press('0')"
                        >
                            0
                        </button>
                        <button
                            type="button"
                            class="flex h-12 items-center justify-center rounded-md border border-strong bg-raised text-muted transition-colors hover:bg-inset"
                            aria-label="Sil"
                            @click="erase()"
                        >
                            <AppIcon name="arrow-left" :size="18" />
                        </button>
                    </div>

                    <div class="grid grid-cols-2 gap-2">
                        <BaseButton :loading="busy === 'in'" @click="act('in')">Giriş Yap</BaseButton>
                        <BaseButton variant="danger" :loading="busy === 'out'" @click="act('out')">Çıkış Yap</BaseButton>
                        <BaseButton variant="secondary" :loading="busy === 'break_start'" @click="act('break_start')">
                            Mola Başlat
                        </BaseButton>
                        <BaseButton variant="secondary" :loading="busy === 'break_end'" @click="act('break_end')">
                            Mola Bitir
                        </BaseButton>
                    </div>
                    <BaseButton variant="ghost" size="sm" :loading="busy === 'status'" @click="act('status')">
                        Durumumu göster
                    </BaseButton>
                </div>
            </BaseCard>

            <div class="flex flex-col gap-4">
                <!-- Sonuç -->
                <BaseCard title="Son işlem">
                    <div v-if="result" class="flex flex-col gap-2 text-sm">
                        <p class="text-base font-semibold text-body">{{ result.user.name }}</p>
                        <p class="flex items-center gap-1.5">
                            <span
                                class="inline-block size-2 rounded-full"
                                :class="result.state.status === 'working' ? (result.state.on_break ? 'bg-warning' : 'bg-success') : 'bg-strong'"
                            />
                            <span class="font-medium text-body">{{ stateLabel }}</span>
                        </p>
                        <template v-if="result.entry">
                            <p class="text-muted">Giriş: {{ fmtTime(result.entry.clock_in_at) }}</p>
                            <p v-if="result.entry.clock_out_at" class="text-muted">Çıkış: {{ fmtTime(result.entry.clock_out_at) }}</p>
                            <p v-if="result.entry.break_total_min > 0" class="text-muted">
                                Mola: {{ fmtMin(result.entry.break_total_min) }}
                            </p>
                            <p v-if="result.entry.worked_min !== null" class="text-muted">
                                Çalışılan: <span class="font-medium text-body">{{ fmtMin(result.entry.worked_min) }}</span>
                            </p>
                            <p v-if="result.entry.overtime_min > 0" class="text-success">
                                Fazla mesai: {{ fmtMin(result.entry.overtime_min) }}
                            </p>
                            <p v-if="result.entry.late_min > 0" class="text-warning">Geç kalma: {{ fmtMin(result.entry.late_min) }}</p>
                        </template>
                    </div>
                    <p v-else class="text-sm text-muted">
                        PIN'inizi girip işlem seçin. Bu ekran ortak cihazda açık bırakılabilir; her personel kendi
                        PIN'iyle işlem yapar.
                    </p>
                </BaseCard>

                <!-- KVKK: konum -->
                <BaseCard v-if="locationEnabled" title="Konum doğrulaması (isteğe bağlı)">
                    <div class="flex flex-col gap-2 text-sm">
                        <p class="text-muted">
                            İşletme, giriş/çıkışta konum doğrulamasını açtı. Konumunuz yalnız
                            <strong>açık rızanız varsa</strong> kaydedilir; rızayı dilediğinizde geri çekebilirsiniz.
                        </p>
                        <p v-if="locationPolicy" class="rounded-md bg-inset p-2 text-xs text-muted">{{ locationPolicy }}</p>
                        <div class="flex items-center justify-between">
                            <span class="font-medium text-body">
                                Rızam: {{ myConsent ? 'verildi' : 'verilmedi' }}
                            </span>
                            <BaseButton size="sm" :variant="myConsent ? 'secondary' : 'primary'" :loading="consentBusy" @click="toggleConsent">
                                {{ myConsent ? 'Rızayı geri çek' : 'Rıza veriyorum' }}
                            </BaseButton>
                        </div>
                        <p class="text-xs text-subtle">Bu tercih yalnız şu an oturumu açık olan hesap için geçerlidir.</p>
                    </div>
                </BaseCard>
            </div>
        </div>
    </ShiftsShell>
</template>
