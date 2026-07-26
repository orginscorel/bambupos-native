<script setup lang="ts">
/**
 * Portal "Profilim": kendi bilgi görüntüle/düzenle (ad/iletişim) + PIN
 * belirle/değiştir (mevcut PIN ucu) + kendi ayarları (bu cihaz push + olay
 * bazlı bildirim tercihleri). Tema düğmesi üst barda (PortalLayout).
 */
import { computed, onMounted, reactive, ref } from 'vue';
import { usePage } from '@inertiajs/vue3';
import { api, ApiError } from '@/lib/http';
import { authFromPage } from '@/types/auth';
import { useToast } from '@/composables/useToast';
import { usePortalPush } from '@/composables/usePortalPush';
import PortalLayout from '@/Layouts/PortalLayout.vue';
import BaseButton from '@/Components/ui/BaseButton.vue';
import BaseInput from '@/Components/ui/BaseInput.vue';
import BaseSwitch from '@/Components/ui/BaseSwitch.vue';
import FormField from '@/Components/ui/FormField.vue';

const page = usePage();
const auth = computed(() => authFromPage(page.props as Record<string, unknown>));
const { success, danger } = useToast();

/* ---------------- Profil bilgisi ---------------- */
const profile = reactive({
    first_name: auth.value?.user?.first_name ?? '',
    last_name: auth.value?.user?.last_name ?? '',
    phone: '',
});
const profileErrors = reactive<Record<string, string>>({});
const savingProfile = ref(false);

async function saveProfile(): Promise<void> {
    savingProfile.value = true;
    Object.keys(profileErrors).forEach((k) => delete profileErrors[k]);
    try {
        await api('/api/v1/portal/profile', { method: 'PUT', body: { ...profile } });
        success('Bilgileriniz güncellendi');
    } catch (e) {
        if (e instanceof ApiError) {
            Object.entries(e.errors).forEach(([k, v]) => (profileErrors[k] = v[0] ?? ''));
            if (!Object.keys(e.errors).length) danger(e.displayMessage);
        }
    } finally {
        savingProfile.value = false;
    }
}

/* ---------------- PIN ---------------- */
const hasPin = ref(auth.value?.user?.has_pin ?? false);
const pin = reactive({ current: '', next: '' });
const pinErrors = reactive<Record<string, string>>({});
const savingPin = ref(false);

async function savePin(): Promise<void> {
    savingPin.value = true;
    Object.keys(pinErrors).forEach((k) => delete pinErrors[k]);
    try {
        await api('/api/v1/portal/profile/pin', {
            method: 'PUT',
            body: { current_pin: pin.current, pin: pin.next },
        });
        hasPin.value = true;
        pin.current = '';
        pin.next = '';
        success('PIN kaydedildi');
    } catch (e) {
        if (e instanceof ApiError) {
            Object.entries(e.errors).forEach(([k, v]) => (pinErrors[k] = v[0] ?? ''));
            if (!Object.keys(e.errors).length) danger(e.displayMessage);
        }
    } finally {
        savingPin.value = false;
    }
}

/* ---------------- Bildirim tercihleri ---------------- */
interface PrefType {
    key: string;
    label: string;
    description: string;
    category: string;
    category_label: string;
    in_app: boolean;
    push: boolean;
}
const prefs = ref<PrefType[]>([]);
const savingPrefs = ref(false);
const push = usePortalPush();

const grouped = computed(() => {
    const map = new Map<string, { label: string; items: PrefType[] }>();
    for (const p of prefs.value) {
        if (!map.has(p.category)) map.set(p.category, { label: p.category_label, items: [] });
        map.get(p.category)!.items.push(p);
    }
    return [...map.values()];
});

async function loadPrefs(): Promise<void> {
    try {
        const res = await api<{ types: PrefType[] }>('/api/v1/notifications/preferences');
        prefs.value = res.types;
    } catch {
        /* sessiz */
    }
}

async function savePrefs(): Promise<void> {
    savingPrefs.value = true;
    try {
        await api('/api/v1/notifications/preferences', {
            method: 'PUT',
            body: { preferences: prefs.value.map((p) => ({ type: p.key, in_app: p.in_app, push: p.push })) },
        });
        success('Bildirim tercihleri kaydedildi');
    } catch (e) {
        danger(e instanceof ApiError ? e.displayMessage : 'Kaydedilemedi.');
    } finally {
        savingPrefs.value = false;
    }
}

async function toggleDevicePush(next: boolean): Promise<void> {
    if (next) {
        const ok = await push.enable();
        if (!ok) danger('Bu cihazda push açılamadı (izin/destek).');
    } else {
        await push.disable();
    }
}

onMounted(() => {
    void loadPrefs();
});
</script>

<template>
    <PortalLayout title="Profilim" active="profile">
        <div class="flex flex-col gap-6">
            <!-- Bilgilerim -->
            <section class="rounded-xl border border-(--ui-border) bg-raised p-5 shadow-(--shadow-card)">
                <h2 class="mb-4 text-sm font-semibold text-body">Bilgilerim</h2>
                <div class="flex flex-col gap-4">
                    <FormField label="Ad" :error="profileErrors.first_name" required>
                        <BaseInput v-model="profile.first_name" autocomplete="given-name" />
                    </FormField>
                    <FormField label="Soyad" :error="profileErrors.last_name">
                        <BaseInput v-model="profile.last_name" autocomplete="family-name" />
                    </FormField>
                    <FormField label="Telefon" :error="profileErrors.phone" hint="İletişim için (opsiyonel)">
                        <BaseInput v-model="profile.phone" type="tel" autocomplete="tel" />
                    </FormField>
                    <div>
                        <BaseButton :loading="savingProfile" @click="saveProfile">Kaydet</BaseButton>
                    </div>
                </div>
            </section>

            <!-- PIN -->
            <section class="rounded-xl border border-(--ui-border) bg-raised p-5 shadow-(--shadow-card)">
                <h2 class="mb-1 text-sm font-semibold text-body">PIN</h2>
                <p class="mb-4 text-xs text-muted">
                    {{ hasPin ? 'PIN’inizi değiştirmek için mevcut PIN’inizi girin.' : 'Hızlı işlemler için bir PIN belirleyin (6-10 rakam).' }}
                </p>
                <div class="flex flex-col gap-4">
                    <FormField v-if="hasPin" label="Mevcut PIN" :error="pinErrors.current_pin" required>
                        <BaseInput v-model="pin.current" type="password" autocomplete="off" inputmode="numeric" />
                    </FormField>
                    <FormField label="Yeni PIN" :error="pinErrors.pin" hint="6-10 rakam; ardışık/tekrar olamaz" required>
                        <BaseInput v-model="pin.next" type="password" autocomplete="new-password" inputmode="numeric" />
                    </FormField>
                    <div>
                        <BaseButton variant="secondary" :loading="savingPin" @click="savePin">
                            {{ hasPin ? 'PIN’i Değiştir' : 'PIN Belirle' }}
                        </BaseButton>
                    </div>
                </div>
            </section>

            <!-- Bildirimler -->
            <section class="rounded-xl border border-(--ui-border) bg-raised p-5 shadow-(--shadow-card)">
                <h2 class="mb-1 text-sm font-semibold text-body">Bildirimler</h2>
                <p class="mb-4 text-xs text-muted">Hangi olayları alacağınızı seçin.</p>

                <div class="mb-4 flex items-center justify-between gap-3 rounded-lg bg-(--color-inset) px-3 py-2.5">
                    <div class="min-w-0">
                        <p class="text-sm font-medium text-body">Bu cihazda push</p>
                        <p class="text-xs text-muted">
                            <template v-if="push.permission.value === 'unsupported'">Bu tarayıcı push desteklemiyor.</template>
                            <template v-else>Anlık bildirimleri bu cihaza al.</template>
                        </p>
                    </div>
                    <BaseSwitch
                        :model-value="push.subscribed.value"
                        :disabled="push.busy.value || push.permission.value === 'unsupported'"
                        aria-label="Bu cihazda push"
                        @update:model-value="toggleDevicePush"
                    />
                </div>

                <div class="flex flex-col gap-5">
                    <div v-for="group in grouped" :key="group.label">
                        <p class="mb-2 text-xs font-semibold uppercase tracking-wide text-subtle">{{ group.label }}</p>
                        <ul class="flex flex-col divide-y divide-(--ui-border) overflow-hidden rounded-lg border border-(--ui-border)">
                            <li v-for="p in group.items" :key="p.key" class="px-3 py-3">
                                <p class="text-sm font-medium text-body">{{ p.label }}</p>
                                <p class="mb-2 text-xs text-muted">{{ p.description }}</p>
                                <div class="flex items-center gap-6">
                                    <BaseSwitch v-model="p.in_app" label="Panelde" label-position="right" />
                                    <BaseSwitch v-model="p.push" label="Push" label-position="right" />
                                </div>
                            </li>
                        </ul>
                    </div>
                </div>

                <div class="mt-4">
                    <BaseButton :loading="savingPrefs" @click="savePrefs">Tercihleri Kaydet</BaseButton>
                </div>
            </section>
        </div>
    </PortalLayout>
</template>
