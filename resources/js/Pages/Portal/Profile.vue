<script setup lang="ts">
/**
 * Portal "Profilim": kimlik özeti + kendi bilgileri (ad/soyad/telefon) + PIN
 * belirle/değiştir + parola değiştir + aktif oturumlar (diğer cihazlardan çık)
 * + bu cihazda bildirim aç/kapa (görev/mesai push'u). Tema düğmesi üst barda.
 */
import { computed, onMounted, reactive, ref } from 'vue';
import { usePage } from '@inertiajs/vue3';
import { api, ApiError } from '@/lib/http';
import { authFromPage } from '@/types/auth';
import { useToast } from '@/composables/useToast';
import { usePortalPush } from '@/composables/usePortalPush';
import PortalLayout from '@/Layouts/PortalLayout.vue';
import AppIcon from '@/Components/ui/AppIcon.vue';
import BaseButton from '@/Components/ui/BaseButton.vue';
import BaseInput from '@/Components/ui/BaseInput.vue';
import BaseSwitch from '@/Components/ui/BaseSwitch.vue';
import FormField from '@/Components/ui/FormField.vue';

const page = usePage();
const auth = computed(() => authFromPage(page.props as Record<string, unknown>));
const { success, danger } = useToast();

/* ---------------- Kimlik özeti (salt-okunur) ---------------- */
const user = computed(() => auth.value?.user ?? null);

const initials = computed(() => {
    const name = user.value?.name ?? '';
    return (
        name
            .split(/\s+/)
            .filter(Boolean)
            .slice(0, 2)
            .map((p) => p[0]?.toLocaleUpperCase('tr-TR'))
            .join('') || '•'
    );
});

const roleLabel = computed(() => {
    if (user.value?.position) return user.value.position;
    const roles = user.value?.roles ?? [];
    return roles.length ? roles.join(', ') : 'Personel';
});

/* ---------------- Profil bilgisi (AD/SOYAD salt-okunur — yönetici belirler) ---------------- */
const profile = reactive({
    phone: '',
});
const profileErrors = reactive<Record<string, string>>({});
const savingProfile = ref(false);

async function saveProfile(): Promise<void> {
    savingProfile.value = true;
    Object.keys(profileErrors).forEach((k) => delete profileErrors[k]);
    try {
        await api('/api/v1/portal/profile', { method: 'PUT', body: { phone: profile.phone } });
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
const hasPin = ref(user.value?.has_pin ?? false);
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

/* ---------------- Parola ---------------- */
const password = reactive({ current_password: '', password: '', password_confirmation: '' });
const passwordErrors = reactive<Record<string, string>>({});
const savingPassword = ref(false);

async function savePassword(): Promise<void> {
    savingPassword.value = true;
    Object.keys(passwordErrors).forEach((k) => delete passwordErrors[k]);
    try {
        await api('/api/v1/auth/password', { method: 'PUT', body: { ...password } });
        password.current_password = '';
        password.password = '';
        password.password_confirmation = '';
        success('Parolanız güncellendi');
    } catch (e) {
        if (e instanceof ApiError) {
            Object.entries(e.errors).forEach(([k, v]) => (passwordErrors[k] = v[0] ?? ''));
            if (!Object.keys(e.errors).length) danger(e.displayMessage);
        }
    } finally {
        savingPassword.value = false;
    }
}

/* ---------------- Oturumlar / Cihazlar ---------------- */
interface SessionRow {
    id: string;
    device: string;
    ip: string | null;
    last_active: string | null;
    current: boolean;
}

const sessions = ref<SessionRow[]>([]);
const sessionsAvailable = ref(false);
const dtFmt = new Intl.DateTimeFormat('tr-TR', { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' });

function normalizeSessions(raw: unknown): SessionRow[] {
    // Uç yanıt şekli belirsiz: dizi, {sessions:[]} veya {data:[]} kabul et.
    let list: unknown[] = [];
    if (Array.isArray(raw)) list = raw;
    else if (raw && typeof raw === 'object') {
        const obj = raw as Record<string, unknown>;
        if (Array.isArray(obj.sessions)) list = obj.sessions;
        else if (Array.isArray(obj.data)) list = obj.data;
    }
    return list.map((item, i) => {
        const o = (item ?? {}) as Record<string, unknown>;
        const str = (...keys: string[]): string | null => {
            for (const k of keys) {
                const v = o[k];
                if (typeof v === 'string' && v.trim()) return v;
            }
            return null;
        };
        return {
            id: String(o.id ?? o.session_id ?? i),
            device: str('device', 'device_name', 'user_agent', 'agent', 'platform') ?? 'Bilinmeyen cihaz',
            ip: str('ip', 'ip_address'),
            last_active: str('last_active_at', 'last_used_at', 'last_seen_at', 'last_activity', 'updated_at'),
            current: Boolean(o.is_current ?? o.current ?? o.this_device ?? false),
        };
    });
}

async function loadSessions(): Promise<void> {
    try {
        const res = await api<unknown>('/api/v1/auth/sessions');
        const rows = normalizeSessions(res);
        sessions.value = rows;
        sessionsAvailable.value = true;
    } catch {
        // Uç yoksa/erişilemezse bölümü tamamen gizle.
        sessionsAvailable.value = false;
    }
}

const logoutPassword = ref('');
const logoutError = ref('');
const loggingOutOthers = ref(false);

async function logoutOtherDevices(): Promise<void> {
    loggingOutOthers.value = true;
    logoutError.value = '';
    try {
        await api('/api/v1/auth/logout-other-devices', { method: 'POST', body: { password: logoutPassword.value } });
        logoutPassword.value = '';
        success('Diğer cihazlardaki oturumlar kapatıldı');
        await loadSessions();
    } catch (e) {
        if (e instanceof ApiError) {
            logoutError.value = e.first('password') || e.displayMessage;
        } else {
            logoutError.value = 'İşlem tamamlanamadı.';
        }
    } finally {
        loggingOutOthers.value = false;
    }
}

const sessionFmt = (iso: string | null): string => {
    if (!iso) return '—';
    const d = new Date(iso);
    return Number.isNaN(d.getTime()) ? iso : dtFmt.format(d);
};

/* ---------------- Bu cihazda bildirim ---------------- */
const push = usePortalPush();

/** "Desteklemiyor" nedenini netleştir (çoğu zaman HTTPS/güvenli bağlam eksik). */
const pushHint = computed<string>(() => {
    if (push.permission.value !== 'unsupported') return 'Anlık bildirimleri bu cihaza gönder.';
    if (typeof window !== 'undefined' && window.isSecureContext === false) {
        return 'Bildirimler için güvenli (HTTPS) bağlantı gerekir.';
    }
    const ua = typeof navigator !== 'undefined' ? navigator.userAgent : '';
    const isIos = /iPhone|iPad|iPod/i.test(ua);
    const standalone =
        typeof window !== 'undefined' &&
        (window.matchMedia?.('(display-mode: standalone)').matches ||
            (navigator as unknown as { standalone?: boolean }).standalone === true);
    if (isIos && !standalone) return 'iPhone’da bildirim için uygulamayı Ana Ekrana ekleyin.';
    return 'Bu tarayıcı push desteklemiyor.';
});

async function toggleDevicePush(next: boolean): Promise<void> {
    if (next) {
        const ok = await push.enable();
        if (!ok) danger('Bu cihazda push açılamadı (izin/destek).');
    } else {
        await push.disable();
    }
}

onMounted(() => {
    void loadSessions();
});
</script>

<template>
    <PortalLayout title="Profilim" active="profile" :heading="'Profilim'">
        <!-- Kimlik özeti (salt-okunur) -->
        <div class="p-card p-4">
            <div class="flex items-center gap-4">
                <span
                    class="p-tile p-tile-indigo flex size-14 shrink-0 items-center justify-center rounded-full !p-0 text-lg font-extrabold"
                >
                    {{ initials }}
                </span>
                <div class="min-w-0 flex-1">
                    <p class="truncate text-lg font-semibold text-body">{{ user?.name ?? 'Personel' }}</p>
                    <p class="truncate text-sm font-medium text-(--p-indigo)">{{ roleLabel }}</p>
                    <p v-if="user?.email" class="mt-0.5 flex items-center gap-1 truncate text-xs text-muted">
                        <AppIcon name="user" :size="12" />
                        {{ user.email }}
                        <template v-if="user?.staff_code"> · Kod: {{ user.staff_code }}</template>
                    </p>
                </div>
            </div>
        </div>

        <!-- Bilgilerim -->
        <div class="mt-4 p-card p-4">
            <p class="mb-4 flex items-center gap-2 font-semibold text-body">
                <span class="p-chip" style="--chip-bg: var(--p-indigo-soft); --chip-fg: var(--p-indigo)"><AppIcon name="user" :size="17" /></span>
                Bilgilerim
            </p>
            <div class="flex flex-col gap-4">
                <p class="rounded-lg bg-(--color-inset) px-3 py-2 text-xs text-muted">
                    Ad ve soyad bilgileriniz yöneticiniz tarafından yönetilir; buradan değiştirilemez.
                </p>
                <FormField label="Telefon" :error="profileErrors.phone" hint="İletişim için (opsiyonel)">
                    <BaseInput v-model="profile.phone" type="tel" autocomplete="tel" />
                </FormField>
                <div>
                    <BaseButton :loading="savingProfile" @click="saveProfile">Kaydet</BaseButton>
                </div>
            </div>
        </div>

        <!-- PIN -->
        <div class="mt-4 p-card p-4">
            <p class="mb-1 flex items-center gap-2 font-semibold text-body">
                <span class="p-chip" style="--chip-bg: var(--p-amber-soft); --chip-fg: var(--p-amber)"><AppIcon name="tablet" :size="17" /></span>
                PIN
            </p>
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
        </div>

        <!-- Parola -->
        <div class="mt-4 p-card p-4">
            <p class="mb-1 flex items-center gap-2 font-semibold text-body">
                <span class="p-chip" style="--chip-bg: var(--p-rose-soft); --chip-fg: var(--p-rose)"><AppIcon name="settings" :size="17" /></span>
                Parola
            </p>
            <p class="mb-4 text-xs text-muted">Güvenliğiniz için parolanızı düzenli olarak değiştirin.</p>
            <div class="flex flex-col gap-4">
                <FormField label="Mevcut parola" :error="passwordErrors.current_password" required>
                    <BaseInput v-model="password.current_password" type="password" autocomplete="current-password" />
                </FormField>
                <FormField label="Yeni parola" :error="passwordErrors.password" hint="En az 8 karakter" required>
                    <BaseInput v-model="password.password" type="password" autocomplete="new-password" />
                </FormField>
                <FormField label="Yeni parola (tekrar)" :error="passwordErrors.password_confirmation" required>
                    <BaseInput v-model="password.password_confirmation" type="password" autocomplete="new-password" />
                </FormField>
                <div>
                    <BaseButton variant="secondary" :loading="savingPassword" @click="savePassword">
                        Parolayı Değiştir
                    </BaseButton>
                </div>
            </div>
        </div>

        <!-- Oturumlar / Cihazlar -->
        <div v-if="sessionsAvailable" class="mt-4 p-card p-4">
            <p class="mb-1 flex items-center gap-2 font-semibold text-body">
                <span class="p-chip" style="--chip-bg: var(--p-sky-soft); --chip-fg: var(--p-sky)"><AppIcon name="monitor" :size="17" /></span>
                Oturumlar / Cihazlar
            </p>
            <p class="mb-4 text-xs text-muted">Hesabınızın açık olduğu cihazlar.</p>

            <ul
                v-if="sessions.length"
                class="mb-4 flex flex-col divide-y divide-(--p-card-border) overflow-hidden rounded-xl border border-(--p-card-border)"
            >
                <li v-for="s in sessions" :key="s.id" class="flex items-start gap-3 px-3 py-3">
                    <span class="mt-0.5 flex size-8 shrink-0 items-center justify-center rounded-full bg-(--p-sky-soft) text-(--p-sky)">
                        <AppIcon name="monitor" :size="16" />
                    </span>
                    <div class="min-w-0 flex-1">
                        <p class="flex items-center gap-2 text-sm font-medium text-body">
                            <span class="truncate">{{ s.device }}</span>
                            <span
                                v-if="s.current"
                                class="shrink-0 rounded-full bg-(--p-emerald-soft) px-1.5 py-0.5 text-[10px] font-semibold text-(--p-emerald)"
                            >
                                Bu cihaz
                            </span>
                        </p>
                        <p class="text-xs text-muted">
                            <template v-if="s.ip">{{ s.ip }} · </template>Son etkinlik: {{ sessionFmt(s.last_active) }}
                        </p>
                    </div>
                </li>
            </ul>

            <div class="flex flex-col gap-3 rounded-xl bg-(--color-inset) p-3">
                <p class="text-xs text-muted">Diğer tüm cihazlardaki oturumları kapatmak için parolanızı girin.</p>
                <FormField label="Parola" :error="logoutError">
                    <BaseInput v-model="logoutPassword" type="password" autocomplete="current-password" />
                </FormField>
                <div>
                    <BaseButton
                        variant="danger"
                        :loading="loggingOutOthers"
                        :disabled="!logoutPassword"
                        @click="logoutOtherDevices"
                    >
                        Diğer cihazlardan çık
                    </BaseButton>
                </div>
            </div>
        </div>

        <!-- Bildirim (bu cihaz) -->
        <div class="mt-4 p-card p-4">
            <p class="mb-1 flex items-center gap-2 font-semibold text-body">
                <span class="p-chip" style="--chip-bg: var(--p-teal-soft); --chip-fg: var(--p-teal)"><AppIcon name="bell" :size="17" /></span>
                Bildirimler
            </p>
            <p class="mb-4 text-xs text-muted">Görev ve mesai bildirimlerini bu cihaza alın.</p>
            <div class="flex items-center justify-between gap-3 rounded-xl bg-(--color-inset) px-3 py-2.5">
                <div class="min-w-0">
                    <p class="text-sm font-medium text-body">Bu cihazda bildirim al</p>
                    <p class="text-xs text-muted">{{ pushHint }}</p>
                </div>
                <BaseSwitch
                    :model-value="push.subscribed.value"
                    :disabled="push.busy.value || push.permission.value === 'unsupported'"
                    aria-label="Bu cihazda bildirim al"
                    @update:model-value="toggleDevicePush"
                />
            </div>
        </div>
    </PortalLayout>
</template>
