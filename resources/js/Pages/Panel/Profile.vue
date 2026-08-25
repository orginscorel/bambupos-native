<script setup lang="ts">
import { computed, onMounted, ref } from 'vue';
import { Head, usePage } from '@inertiajs/vue3';
import QRCode from 'qrcode';
import { api, ApiError } from '@/lib/http';
import { authFromPage } from '@/types/auth';
import { formatDateTime, formatRelative } from '@/lib/format';
import { useTheme, type Theme } from '@/composables/useTheme';
import { useToast } from '@/composables/useToast';
import PanelShell from '@/Components/panel/PanelShell.vue';
import BaseBadge from '@/Components/ui/BaseBadge.vue';
import BaseButton from '@/Components/ui/BaseButton.vue';
import BaseCard from '@/Components/ui/BaseCard.vue';
import BaseInput from '@/Components/ui/BaseInput.vue';
import BaseModal from '@/Components/ui/BaseModal.vue';
import BaseSelect from '@/Components/ui/BaseSelect.vue';
import BaseSkeleton from '@/Components/ui/BaseSkeleton.vue';
import BaseSwitch from '@/Components/ui/BaseSwitch.vue';
import BaseTabs from '@/Components/ui/BaseTabs.vue';
import EmptyState from '@/Components/ui/EmptyState.vue';
import FormField from '@/Components/ui/FormField.vue';
import AppIcon from '@/Components/ui/AppIcon.vue';
import { usePush } from '@/composables/usePush';

const page = usePage();
const auth = computed(() => authFromPage(page.props as Record<string, unknown>));
const user = computed(() => auth.value?.user ?? null);

const { success, danger } = useToast();
const { theme, setTheme } = useTheme();

const activeTab = ref('profile');
const tabs = [
    { key: 'profile', label: 'Profil', icon: 'user' },
    { key: 'security', label: 'Güvenlik', icon: 'settings' },
    { key: 'notifications', label: 'Bildirimler', icon: 'bell' },
    { key: 'sessions', label: 'Oturumlar', icon: 'dashboard' },
];

const userInitial = computed(() => (user.value?.name?.trim()?.charAt(0) ?? '?').toUpperCase());

/* ================= Tema tercihi ================= */
const savingTheme = ref(false);

async function chooseTheme(value: Theme): Promise<void> {
    setTheme(value);
    savingTheme.value = true;
    try {
        await api('/api/v1/auth/preferences', { method: 'PUT', body: { theme: value } });
    } catch {
        /* localStorage zaten güncel; kalıcılaştırma sonraki girişte tekrar denenir */
    } finally {
        savingTheme.value = false;
    }
}

/* ================= Açılış ekranı tercihi (Personel-Yetki) ================= */
const screenOptions = computed(() => {
    const opts = ((page.props as Record<string, unknown>).auth as { screenOptions?: { key: string; label: string }[] } | undefined)
        ?.screenOptions ?? [];
    return [{ value: '', label: 'Otomatik (rolüme en uygun ekran)' }, ...opts.map((o) => ({ value: o.key, label: o.label }))];
});
const defaultScreen = ref<string>(
    ((page.props as Record<string, unknown>).auth as { user?: { default_screen?: string | null } } | undefined)?.user
        ?.default_screen ?? '',
);
const savingScreen = ref(false);

async function chooseScreen(value: string): Promise<void> {
    defaultScreen.value = value;
    savingScreen.value = true;
    try {
        await api('/api/v1/auth/preferences', { method: 'PUT', body: { default_screen: value || null } });
        success('Açılış ekranı kaydedildi', 'Bir sonraki girişinizde bu ekranla başlarsınız.');
    } catch (e) {
        danger('Kaydedilemedi', e instanceof ApiError ? e.displayMessage : 'Lütfen tekrar deneyin.');
    } finally {
        savingScreen.value = false;
    }
}

/* ================= Parola değiştirme ================= */
const pw = ref({ current: '', next: '', confirm: '' });
const pwErrors = ref<{ current_password?: string; password?: string }>({});
const pwLoading = ref(false);

async function changePassword(): Promise<void> {
    if (pwLoading.value) return;
    pwLoading.value = true;
    pwErrors.value = {};
    try {
        await api('/api/v1/auth/password', {
            method: 'PUT',
            body: {
                current_password: pw.value.current,
                password: pw.value.next,
                password_confirmation: pw.value.confirm,
            },
        });
        pw.value = { current: '', next: '', confirm: '' };
        success('Parola güncellendi', 'Yeni parolanız bir sonraki girişte geçerli olacak.');
    } catch (e) {
        if (e instanceof ApiError) {
            pwErrors.value = { current_password: e.first('current_password'), password: e.first('password') };
            if (!e.first('current_password') && !e.first('password')) danger('Parola değiştirilemedi', e.displayMessage);
        } else {
            danger('Parola değiştirilemedi', 'Beklenmeyen bir hata oluştu.');
        }
    } finally {
        pwLoading.value = false;
    }
}

/* ================= PIN belirleme ================= */
const hasPin = ref(false);
const pinForm = ref({ password: '', pin: '' });
const pinErrors = ref<{ password?: string; pin?: string }>({});
const pinLoading = ref(false);

async function setPin(): Promise<void> {
    if (pinLoading.value) return;
    pinLoading.value = true;
    pinErrors.value = {};
    try {
        await api('/api/v1/auth/pin', {
            method: 'POST',
            body: { password: pinForm.value.password, pin: pinForm.value.pin },
        });
        pinForm.value = { password: '', pin: '' };
        hasPin.value = true;
        success('PIN kaydedildi', 'Artık PIN ile hızlı giriş yapabilirsiniz.');
    } catch (e) {
        if (e instanceof ApiError) {
            pinErrors.value = { password: e.first('password'), pin: e.first('pin') };
            if (!e.first('password') && !e.first('pin')) danger('PIN kaydedilemedi', e.displayMessage);
        } else {
            danger('PIN kaydedilemedi', 'Beklenmeyen bir hata oluştu.');
        }
    } finally {
        pinLoading.value = false;
    }
}

/* ================= İki faktörlü doğrulama ================= */
const twoFactorEnabled = ref(false);
const tfaModalOpen = ref(false);
const tfaStep = ref<'setup' | 'recovery'>('setup');
const tfaSecret = ref('');
const tfaQr = ref('');
const tfaCode = ref('');
const tfaCodeError = ref('');
const tfaLoading = ref(false);
const recoveryCodes = ref<string[]>([]);

const disableModalOpen = ref(false);
const disablePassword = ref('');
const disableError = ref('');
const disableLoading = ref(false);

async function startTwoFactor(): Promise<void> {
    tfaLoading.value = true;
    tfaCode.value = '';
    tfaCodeError.value = '';
    try {
        const result = await api<{ secret: string; otpauth_url: string }>('/api/v1/auth/two-factor/enable', {
            method: 'POST',
        });
        tfaSecret.value = result.secret;
        tfaQr.value = await QRCode.toDataURL(result.otpauth_url, { width: 220, margin: 1 });
        tfaStep.value = 'setup';
        tfaModalOpen.value = true;
    } catch (e) {
        danger('2FA başlatılamadı', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen bir hata oluştu.');
    } finally {
        tfaLoading.value = false;
    }
}

async function confirmTwoFactor(): Promise<void> {
    if (tfaLoading.value) return;
    tfaLoading.value = true;
    tfaCodeError.value = '';
    try {
        const result = await api<{ recovery_codes: string[] }>('/api/v1/auth/two-factor/confirm', {
            method: 'POST',
            body: { code: tfaCode.value.trim() },
        });
        recoveryCodes.value = result.recovery_codes;
        twoFactorEnabled.value = true;
        tfaStep.value = 'recovery';
    } catch (e) {
        tfaCodeError.value = e instanceof ApiError ? e.first('code') || e.displayMessage : 'Kod doğrulanamadı.';
    } finally {
        tfaLoading.value = false;
    }
}

async function copyRecoveryCodes(): Promise<void> {
    try {
        await navigator.clipboard.writeText(recoveryCodes.value.join('\n'));
        success('Kopyalandı', 'Kurtarma kodları panoya kopyalandı.');
    } catch {
        danger('Kopyalanamadı', 'Kodları elle not edin.');
    }
}

function finishTwoFactorSetup(): void {
    tfaModalOpen.value = false;
    recoveryCodes.value = [];
    tfaSecret.value = '';
    tfaQr.value = '';
    success('İki faktörlü doğrulama açık', 'Bundan sonraki girişlerde kod istenecek.');
}

async function disableTwoFactor(): Promise<void> {
    if (disableLoading.value) return;
    disableLoading.value = true;
    disableError.value = '';
    try {
        await api('/api/v1/auth/two-factor', { method: 'DELETE', body: { password: disablePassword.value } });
        twoFactorEnabled.value = false;
        disableModalOpen.value = false;
        disablePassword.value = '';
        success('İki faktörlü doğrulama kapatıldı');
    } catch (e) {
        disableError.value =
            e instanceof ApiError ? e.first('password') || e.displayMessage : 'Beklenmeyen bir hata oluştu.';
    } finally {
        disableLoading.value = false;
    }
}

/* ================= Oturumlar ================= */
interface SessionRow {
    id: string;
    ip_address: string | null;
    user_agent: string | null;
    last_activity: string;
    current: boolean;
}

const sessions = ref<SessionRow[]>([]);
const sessionsLoading = ref(false);
const sessionsError = ref('');
const revoking = ref<string | null>(null);

const othersModalOpen = ref(false);
const othersPassword = ref('');
const othersError = ref('');
const othersLoading = ref(false);

function describeAgent(ua: string | null): string {
    if (!ua) return 'Bilinmeyen cihaz';
    const browser = /Edg\//.test(ua)
        ? 'Edge'
        : /OPR\//.test(ua)
          ? 'Opera'
          : /Firefox\//.test(ua)
            ? 'Firefox'
            : /Chrome\//.test(ua)
              ? 'Chrome'
              : /Safari\//.test(ua)
                ? 'Safari'
                : 'Tarayıcı';
    const os = /Windows/.test(ua)
        ? 'Windows'
        : /Android/.test(ua)
          ? 'Android'
          : /iPhone|iPad|iOS/.test(ua)
            ? 'iOS'
            : /Mac OS X|Macintosh/.test(ua)
              ? 'macOS'
              : /Linux/.test(ua)
                ? 'Linux'
                : 'Bilinmeyen sistem';
    return `${browser} · ${os}`;
}

async function loadSessions(): Promise<void> {
    sessionsLoading.value = true;
    sessionsError.value = '';
    try {
        const result = await api<{ sessions: SessionRow[] }>('/api/v1/auth/sessions');
        sessions.value = result.sessions;
    } catch (e) {
        sessionsError.value = e instanceof ApiError ? e.displayMessage : 'Oturumlar yüklenemedi.';
    } finally {
        sessionsLoading.value = false;
    }
}

async function revokeSession(row: SessionRow): Promise<void> {
    revoking.value = row.id;
    try {
        await api(`/api/v1/auth/sessions/${row.id}`, { method: 'DELETE' });
        sessions.value = sessions.value.filter((s) => s.id !== row.id);
        success('Oturum sonlandırıldı');
    } catch (e) {
        danger('Oturum sonlandırılamadı', e instanceof ApiError ? e.displayMessage : 'Lütfen tekrar deneyin.');
    } finally {
        revoking.value = null;
    }
}

async function logoutOtherDevices(): Promise<void> {
    if (othersLoading.value) return;
    othersLoading.value = true;
    othersError.value = '';
    try {
        await api('/api/v1/auth/logout-other-devices', {
            method: 'POST',
            body: { password: othersPassword.value },
        });
        othersModalOpen.value = false;
        othersPassword.value = '';
        await loadSessions();
        success('Diğer cihazlardan çıkış yapıldı');
    } catch (e) {
        othersError.value =
            e instanceof ApiError ? e.first('password') || e.displayMessage : 'Beklenmeyen bir hata oluştu.';
    } finally {
        othersLoading.value = false;
    }
}

/* ================= Bildirimler (§8): kişi tercihleri + web push ================= */
interface PrefType {
    key: string;
    label: string;
    description: string;
    category: string;
    category_label: string;
    in_app: boolean;
    push: boolean;
}

const prefsLoading = ref(true);
const prefTypes = ref<PrefType[]>([]);
const savingPrefs = ref(false);

// Kategoriye göre gruplu gösterim (Siparişler / Mutfak & Teslim / ...).
const prefGroups = computed<{ label: string; types: PrefType[] }[]>(() => {
    const map = new Map<string, { label: string; types: PrefType[] }>();
    for (const t of prefTypes.value) {
        if (!map.has(t.category)) {
            map.set(t.category, { label: t.category_label, types: [] });
        }
        map.get(t.category)!.types.push(t);
    }
    return Array.from(map.values());
});

async function loadPrefs(): Promise<void> {
    prefsLoading.value = true;
    try {
        const res = await api<{ types: PrefType[] }>('/api/v1/notifications/preferences');
        prefTypes.value = res.types;
    } catch {
        /* sessiz — boş liste kalır */
    } finally {
        prefsLoading.value = false;
    }
}

async function savePref(type: PrefType, channel: 'in_app' | 'push', value: boolean): Promise<void> {
    const previous = type[channel];
    type[channel] = value;
    savingPrefs.value = true;
    try {
        await api('/api/v1/notifications/preferences', {
            method: 'PUT',
            body: { preferences: [{ type: type.key, in_app: type.in_app, push: type.push }] },
        });
    } catch (e) {
        type[channel] = previous; // geri al
        danger('Kaydedilemedi', e instanceof ApiError ? e.displayMessage : 'Lütfen tekrar deneyin.');
    } finally {
        savingPrefs.value = false;
    }
}

/* Web push aç/kapa (bu cihaz için). */
const push = usePush();

async function togglePush(value: boolean): Promise<void> {
    if (value) {
        const ok = await push.enable();
        if (ok) {
            success('Push açıldı', 'Bu cihazda masaüstü/mobil bildirim alacaksınız.');
        } else if (push.permission.value === 'denied') {
            danger('İzin reddedildi', 'Tarayıcı ayarlarından bildirim iznini açmanız gerekir.');
        } else if (push.permission.value === 'unsupported') {
            danger('Desteklenmiyor', 'Bu tarayıcı web push desteklemiyor (iOS: ana ekrana ekleyin).');
        } else {
            danger('Push açılamadı', 'Lütfen tekrar deneyin.');
        }
    } else {
        await push.disable();
        success('Push kapatıldı', 'Bu cihazda artık push bildirim almayacaksınız.');
    }
}

onMounted(() => {
    twoFactorEnabled.value = user.value?.two_factor_enabled ?? false;
    hasPin.value = user.value?.has_pin ?? false;
    void loadSessions();
    void loadPrefs();
});
</script>

<template>
    <Head title="Hesabım" />

    <PanelShell title="Hesabım" flush canvas>
        <div class="min-h-0 flex-1 overflow-y-auto p-3 pb-24 sm:p-4 lg:pb-4">
        <div class="mx-auto flex w-full max-w-[1080px] flex-col gap-3">

        <div class="mx-auto flex w-full max-w-5xl flex-col gap-6">
            <div class="flex flex-col gap-1.5">
                <h1 class="text-2xl font-semibold text-body">Hesabım</h1>
                <p class="max-w-2xl text-[15px] leading-relaxed text-muted">
                    Profil bilgileriniz, güvenlik ayarlarınız ve bu hesapla açık oturumlarınız burada.
                </p>
            </div>

            <BaseTabs v-model="activeTab" :tabs="tabs">
            <!-- ================= Profil ================= -->
            <template #profile>
                <div class="flex flex-col divide-y divide-(--ui-border)">
                    <section class="grid grid-cols-1 gap-x-12 gap-y-4 py-8 first:pt-0 md:grid-cols-[260px_1fr]">
                        <div class="flex flex-col gap-1.5">
                            <h2 class="text-base font-semibold text-body">Kimlik</h2>
                            <p class="text-sm leading-relaxed text-muted">
                                Hesap bilgileriniz sistem yönetimi tarafından tanımlanır; burada yalnız görüntülenir.
                            </p>
                        </div>
                        <div class="min-w-0">
                            <BaseCard flush>
                                <div class="flex flex-col gap-6 p-5 sm:p-6">
                                    <div
                                        class="flex flex-wrap items-center gap-4 rounded-lg bg-linear-to-br from-primary-soft to-transparent p-5 sm:p-6"
                                    >
                                        <span
                                            class="flex size-16 shrink-0 items-center justify-center rounded-full bg-primary text-xl font-bold text-on-primary"
                                        >
                                            {{ userInitial }}
                                        </span>
                                        <div class="min-w-0">
                                            <p class="text-lg font-semibold text-body">{{ user?.name || '—' }}</p>
                                            <p class="text-sm text-muted">{{ user?.email || '—' }}</p>
                                            <div class="mt-2 flex flex-wrap gap-1.5">
                                                <BaseBadge v-for="role in user?.roles ?? []" :key="role" variant="primary" no-icon>
                                                    {{ role }}
                                                </BaseBadge>
                                                <span v-if="(user?.roles ?? []).length === 0" class="text-sm text-muted">Rol atanmamış</span>
                                            </div>
                                        </div>
                                    </div>

                                    <dl class="grid grid-cols-1 gap-x-6 gap-y-5 sm:grid-cols-3">
                                        <div>
                                            <dt class="text-xs font-medium text-subtle">Personel kodu</dt>
                                            <dd class="mt-0.5 text-sm text-body">{{ user?.staff_code || '—' }}</dd>
                                        </div>
                                        <div>
                                            <dt class="text-xs font-medium text-subtle">Görev / Ünvan</dt>
                                            <dd class="mt-0.5 text-sm text-body">{{ user?.position || '—' }}</dd>
                                        </div>
                                        <div>
                                            <dt class="text-xs font-medium text-subtle">Son giriş</dt>
                                            <dd class="mt-0.5 text-sm text-body">
                                                {{ user?.last_login_at ? formatDateTime(user.last_login_at) : '—' }}
                                            </dd>
                                        </div>
                                    </dl>
                                </div>
                            </BaseCard>
                        </div>
                    </section>

                    <section class="grid grid-cols-1 gap-x-12 gap-y-4 py-8 md:grid-cols-[260px_1fr]">
                        <div class="flex flex-col gap-1.5">
                            <h2 class="text-base font-semibold text-body">Görünüm</h2>
                            <p class="text-sm leading-relaxed text-muted">
                                Tema tercihiniz bu cihazda ve hesabınızda saklanır.
                            </p>
                        </div>
                        <div class="min-w-0">
                            <BaseCard>
                                <div class="inline-flex rounded-md border border-strong p-0.5" role="group" aria-label="Tema seçimi">
                                    <button
                                        type="button"
                                        class="flex h-9 items-center gap-2 rounded px-4 text-sm font-medium transition-colors duration-(--dur-fast)"
                                        :class="theme === 'light' ? 'bg-primary text-on-primary' : 'text-muted hover:text-body'"
                                        :aria-pressed="theme === 'light'"
                                        @click="chooseTheme('light')"
                                    >
                                        <AppIcon name="sun" :size="16" /> Açık
                                    </button>
                                    <button
                                        type="button"
                                        class="flex h-9 items-center gap-2 rounded px-4 text-sm font-medium transition-colors duration-(--dur-fast)"
                                        :class="theme === 'dark' ? 'bg-primary text-on-primary' : 'text-muted hover:text-body'"
                                        :aria-pressed="theme === 'dark'"
                                        @click="chooseTheme('dark')"
                                    >
                                        <AppIcon name="moon" :size="16" /> Koyu
                                    </button>
                                </div>
                                <p v-if="savingTheme" class="mt-2 text-xs text-subtle">Kaydediliyor…</p>
                            </BaseCard>
                        </div>
                    </section>

                    <section class="grid grid-cols-1 gap-x-12 gap-y-4 py-8 last:pb-0 md:grid-cols-[260px_1fr]">
                        <div class="flex flex-col gap-1.5">
                            <h2 class="text-base font-semibold text-body">Açılış ekranı</h2>
                            <p class="text-sm leading-relaxed text-muted">
                                Giriş yaptığınızda ilk düşeceğiniz ekranı seçin. Otomatik: rolünüze en uygun ekran seçilir.
                            </p>
                        </div>
                        <div class="min-w-0">
                            <BaseCard>
                                <div class="max-w-sm">
                                    <FormField label="Varsayılan ekran">
                                        <BaseSelect
                                            :model-value="defaultScreen"
                                            :options="screenOptions"
                                            :disabled="savingScreen"
                                            @update:model-value="chooseScreen(String($event))"
                                        />
                                    </FormField>
                                </div>
                            </BaseCard>
                        </div>
                    </section>
                </div>
            </template>

            <!-- ================= Güvenlik ================= -->
            <template #security>
                <div class="flex flex-col divide-y divide-(--ui-border)">
                    <section class="grid grid-cols-1 gap-x-12 gap-y-4 py-8 first:pt-0 md:grid-cols-[260px_1fr]">
                        <div class="flex flex-col gap-1.5">
                            <h2 class="text-base font-semibold text-body">Parola</h2>
                            <p class="text-sm leading-relaxed text-muted">
                                Hesabınıza giriş için kullandığınız parola. Değiştirdikten sonra bir sonraki girişte geçerli olur.
                            </p>
                        </div>
                        <div class="min-w-0">
                            <BaseCard>
                                <form class="flex flex-col gap-5" novalidate @submit.prevent="changePassword">
                                    <div class="max-w-sm">
                                        <FormField label="Mevcut parola" :error="pwErrors.current_password" required>
                                            <BaseInput v-model="pw.current" type="password" autocomplete="current-password" />
                                        </FormField>
                                    </div>
                                    <div class="grid grid-cols-1 gap-4 sm:max-w-xl sm:grid-cols-2">
                                        <FormField label="Yeni parola" :error="pwErrors.password" hint="En az 10 karakter" required>
                                            <BaseInput v-model="pw.next" type="password" autocomplete="new-password" />
                                        </FormField>
                                        <FormField label="Yeni parola (tekrar)" required>
                                            <BaseInput v-model="pw.confirm" type="password" autocomplete="new-password" />
                                        </FormField>
                                    </div>
                                    <div>
                                        <BaseButton type="submit" :loading="pwLoading">Parolayı güncelle</BaseButton>
                                    </div>
                                </form>
                            </BaseCard>
                        </div>
                    </section>

                    <section class="grid grid-cols-1 gap-x-12 gap-y-4 py-8 md:grid-cols-[260px_1fr]">
                        <div class="flex flex-col gap-1.5">
                            <h2 class="text-base font-semibold text-body">Hızlı giriş PIN'i</h2>
                            <p class="text-sm leading-relaxed text-muted">
                                PIN, kasada/serviste hızlı giriş içindir: 6-10 hane, yalnız rakam. Tekrarlı (111111) ve
                                ardışık (123456) diziler kabul edilmez.
                            </p>
                        </div>
                        <div class="min-w-0">
                            <BaseCard>
                                <template #actions>
                                    <BaseBadge :variant="hasPin ? 'success' : 'neutral'" :no-icon="!hasPin">
                                        {{ hasPin ? 'Tanımlı' : 'Tanımlı değil' }}
                                    </BaseBadge>
                                </template>
                                <form class="grid grid-cols-1 gap-4 sm:max-w-xl sm:grid-cols-2" novalidate @submit.prevent="setPin">
                                    <FormField label="Parolanız" :error="pinErrors.password" required>
                                        <BaseInput v-model="pinForm.password" type="password" autocomplete="current-password" />
                                    </FormField>
                                    <FormField :label="hasPin ? 'Yeni PIN' : 'PIN'" :error="pinErrors.pin" required>
                                        <BaseInput
                                            v-model="pinForm.pin"
                                            type="password"
                                            inputmode="numeric"
                                            autocomplete="off"
                                            placeholder="••••••"
                                        />
                                    </FormField>
                                    <div class="sm:col-span-2">
                                        <BaseButton type="submit" :loading="pinLoading">
                                            {{ hasPin ? 'PIN\'i değiştir' : 'PIN belirle' }}
                                        </BaseButton>
                                    </div>
                                </form>
                            </BaseCard>
                        </div>
                    </section>

                    <section class="grid grid-cols-1 gap-x-12 gap-y-4 py-8 last:pb-0 md:grid-cols-[260px_1fr]">
                        <div class="flex flex-col gap-1.5">
                            <h2 class="text-base font-semibold text-body">İki faktörlü doğrulama (2FA)</h2>
                            <p class="text-sm leading-relaxed text-muted">
                                Girişte parolanıza ek olarak doğrulama uygulamasından (Google Authenticator, Aegis vb.)
                                6 haneli kod istenir. Hesabınız için önerilen ek koruma katmanı.
                            </p>
                        </div>
                        <div class="min-w-0">
                            <BaseCard>
                                <template #actions>
                                    <BaseBadge :variant="twoFactorEnabled ? 'success' : 'neutral'" :no-icon="!twoFactorEnabled">
                                        {{ twoFactorEnabled ? 'Açık' : 'Kapalı' }}
                                    </BaseBadge>
                                </template>
                                <BaseButton v-if="!twoFactorEnabled" :loading="tfaLoading" @click="startTwoFactor">
                                    2FA'yı etkinleştir
                                </BaseButton>
                                <BaseButton v-else variant="danger" @click="disableModalOpen = true">
                                    2FA'yı devre dışı bırak
                                </BaseButton>
                            </BaseCard>
                        </div>
                    </section>
                </div>
            </template>

            <!-- ================= Oturumlar ================= -->
            <!-- ================= Bildirimler (§8) ================= -->
            <template #notifications>
                <div class="flex flex-col divide-y divide-(--ui-border)">
                    <!-- Web push (bu cihaz) -->
                    <section class="grid grid-cols-1 gap-x-12 gap-y-4 py-8 first:pt-0 md:grid-cols-[260px_1fr]">
                        <div class="flex flex-col gap-1.5">
                            <h2 class="text-base font-semibold text-body">Masaüstü / mobil push</h2>
                            <p class="text-sm leading-relaxed text-muted">
                                Bu cihazda (tarayıcı) push bildirim alın. Panel kapalıyken de sipariş, hazır ve uyarı
                                bildirimleri masaüstünüze düşer.
                            </p>
                        </div>
                        <div class="min-w-0">
                            <BaseCard flush>
                                <div class="flex items-start justify-between gap-4 p-5 sm:p-6">
                                    <div class="min-w-0 flex flex-col gap-0.5">
                                        <span class="text-[15px] font-semibold text-body">Bu cihazda push bildirimleri</span>
                                        <span class="text-sm leading-relaxed text-muted">
                                            <template v-if="push.permission.value === 'unsupported'">
                                                Bu tarayıcı push desteklemiyor. iOS'ta uygulamayı ana ekrana ekleyin.
                                            </template>
                                            <template v-else-if="push.permission.value === 'denied'">
                                                Bildirim izni reddedilmiş — tarayıcı ayarlarından açmanız gerekir.
                                            </template>
                                            <template v-else-if="push.subscribed.value">Bu cihazda açık.</template>
                                            <template v-else>Kapalı — açmak için izin vermeniz istenir.</template>
                                        </span>
                                    </div>
                                    <BaseSwitch
                                        :model-value="push.subscribed.value"
                                        :busy="push.busy.value"
                                        :disabled="push.permission.value === 'unsupported' || push.permission.value === 'denied'"
                                        aria-label="Bu cihazda push bildirimlerini aç/kapat"
                                        @update:model-value="togglePush($event)"
                                    />
                                </div>
                            </BaseCard>
                        </div>
                    </section>

                    <!-- Olay tipi tercihleri (kalem kalem) -->
                    <section class="grid grid-cols-1 gap-x-12 gap-y-4 py-8 md:grid-cols-[260px_1fr]">
                        <div class="flex flex-col gap-1.5">
                            <h2 class="text-base font-semibold text-body">Neyi bildirelim?</h2>
                            <p class="text-sm leading-relaxed text-muted">
                                Her olay için panel-içi zil ve push'u ayrı ayrı açıp kapatın. Yalnız rolünüzle ilgili
                                olaylar size ulaşır.
                            </p>
                        </div>
                        <div class="min-w-0 flex flex-col gap-5">
                            <div v-if="prefsLoading" class="flex flex-col gap-3">
                                <BaseSkeleton v-for="n in 3" :key="n" variant="rect" size-class="h-16 w-full" />
                            </div>

                            <EmptyState
                                v-else-if="prefTypes.length === 0"
                                icon="bell"
                                title="Ayarlanacak bildirim yok"
                                description="Rolünüze uygun bildirim tipi bulunmuyor."
                            />

                            <BaseCard v-for="group in prefGroups" v-else :key="group.label" flush>
                                <div class="border-b border-default px-4 py-2.5 sm:px-5">
                                    <span class="text-xs font-semibold uppercase tracking-wide text-subtle">{{ group.label }}</span>
                                </div>
                                <ul class="divide-y divide-(--ui-border)">
                                    <li v-for="type in group.types" :key="type.key" class="flex flex-col gap-3 px-4 py-4 sm:px-5">
                                        <div class="min-w-0 flex flex-col gap-0.5">
                                            <span class="text-[15px] font-semibold text-body">{{ type.label }}</span>
                                            <span class="text-sm leading-relaxed text-muted">{{ type.description }}</span>
                                        </div>
                                        <div class="flex flex-wrap items-center gap-x-8 gap-y-2">
                                            <BaseSwitch
                                                :model-value="type.in_app"
                                                label="Panel zili"
                                                label-position="left"
                                                :aria-label="`${type.label} — panel zili`"
                                                @update:model-value="savePref(type, 'in_app', $event)"
                                            />
                                            <BaseSwitch
                                                :model-value="type.push"
                                                label="Push"
                                                label-position="left"
                                                :aria-label="`${type.label} — push`"
                                                @update:model-value="savePref(type, 'push', $event)"
                                            />
                                        </div>
                                    </li>
                                </ul>
                            </BaseCard>
                        </div>
                    </section>
                </div>
            </template>

            <template #sessions>
                <section class="grid grid-cols-1 gap-x-12 gap-y-4 md:grid-cols-[260px_1fr]">
                    <div class="flex flex-col gap-1.5">
                        <h2 class="text-base font-semibold text-body">Aktif cihazlar</h2>
                        <p class="text-sm leading-relaxed text-muted">
                            Hesabınıza giriş yapılmış tüm cihaz ve tarayıcılar. Tanımadığınız bir cihaz görürseniz
                            hemen sonlandırın.
                        </p>
                    </div>
                    <div class="min-w-0">
                        <BaseCard flush>
                            <template #actions>
                                <BaseButton
                                    v-if="sessions.length > 1"
                                    variant="secondary"
                                    size="sm"
                                    @click="othersModalOpen = true"
                                >
                                    <AppIcon name="logout" :size="15" />
                                    Diğer cihazlardan çıkış
                                </BaseButton>
                            </template>

                            <div v-if="sessionsLoading" class="flex flex-col gap-3 p-4 sm:p-5">
                                <BaseSkeleton v-for="n in 2" :key="n" variant="rect" size-class="h-20 w-full" />
                            </div>

                            <div v-else-if="sessionsError" class="p-4 sm:p-5">
                                <div
                                    class="flex items-start gap-2.5 rounded-md border border-danger-border bg-danger-soft px-3 py-2.5 text-sm text-danger"
                                    role="alert"
                                >
                                    <AppIcon name="alert-circle" :size="17" class="mt-0.5" />
                                    <p>{{ sessionsError }}</p>
                                </div>
                            </div>

                            <EmptyState
                                v-else-if="sessions.length === 0"
                                icon="dashboard"
                                title="Aktif oturum bulunamadı"
                                description="Bu beklenmedik bir durum; sayfayı yenilemeyi deneyin."
                            />

                            <ul v-else class="flex flex-col gap-3 p-4 sm:p-5">
                                <li
                                    v-for="row in sessions"
                                    :key="row.id"
                                    class="flex flex-col gap-3 rounded-lg border border-default p-4 sm:flex-row sm:items-center sm:justify-between sm:gap-4 sm:p-5"
                                >
                                    <div class="flex items-start gap-3.5 sm:items-center">
                                        <span class="flex size-11 shrink-0 items-center justify-center rounded-full bg-inset text-muted">
                                            <AppIcon name="dashboard" :size="20" />
                                        </span>
                                        <div class="min-w-0">
                                            <p class="flex flex-wrap items-center gap-2 text-sm font-semibold text-body">
                                                {{ describeAgent(row.user_agent) }}
                                                <BaseBadge v-if="row.current" variant="success">Bu cihaz</BaseBadge>
                                            </p>
                                            <p class="mt-1 text-xs text-muted">
                                                IP: {{ row.ip_address || '—' }} · Son etkinlik:
                                                {{ formatRelative(row.last_activity) }}
                                            </p>
                                        </div>
                                    </div>
                                    <BaseButton
                                        v-if="!row.current"
                                        variant="secondary"
                                        size="sm"
                                        class="self-start sm:self-auto"
                                        :loading="revoking === row.id"
                                        @click="revokeSession(row)"
                                    >
                                        <AppIcon name="trash" :size="15" />
                                        Sonlandır
                                    </BaseButton>
                                </li>
                            </ul>
                        </BaseCard>
                    </div>
                </section>
            </template>
            </BaseTabs>
        </div>

        <!-- ===== 2FA kurulum modalı ===== -->
        <BaseModal
            :open="tfaModalOpen"
            :title="tfaStep === 'setup' ? 'İki faktörlü doğrulama kurulumu' : 'Kurtarma kodlarınız'"
            :dismissable="tfaStep === 'setup'"
            @close="tfaModalOpen = false"
        >
            <div v-if="tfaStep === 'setup'" class="flex flex-col gap-4">
                <p class="text-sm text-muted">
                    Doğrulama uygulamanızla aşağıdaki kareyi okutun ya da gizli anahtarı elle girin; ardından
                    uygulamanın ürettiği 6 haneli kodu doğrulayın.
                </p>
                <div class="flex justify-center">
                    <img
                        v-if="tfaQr"
                        :src="tfaQr"
                        alt="2FA kurulum QR kodu"
                        class="rounded-md border border-default bg-white p-2"
                        width="180"
                        height="180"
                    />
                </div>
                <div class="rounded-md bg-inset px-3 py-2 text-center">
                    <p class="text-xs text-subtle">Gizli anahtar (elle giriş için)</p>
                    <p class="mt-0.5 font-mono text-sm font-semibold tracking-wider break-all text-body">
                        {{ tfaSecret }}
                    </p>
                </div>
                <FormField label="Doğrulama kodu" :error="tfaCodeError" required>
                    <BaseInput
                        v-model="tfaCode"
                        inputmode="numeric"
                        autocomplete="one-time-code"
                        placeholder="000000"
                    />
                </FormField>
            </div>

            <div v-else class="flex flex-col gap-4">
                <div
                    class="flex items-start gap-2.5 rounded-md border border-warning-border bg-warning-soft px-3 py-2.5 text-sm text-warning"
                >
                    <AppIcon name="alert-triangle" :size="17" class="mt-0.5" />
                    <p>
                        Bu kodlar <strong>yalnız bir kez</strong> gösterilir. Telefonunuza erişemezseniz girişte
                        bunlardan birini kullanabilirsiniz. Güvenli bir yerde saklayın.
                    </p>
                </div>
                <ul class="grid grid-cols-2 gap-2">
                    <li
                        v-for="code in recoveryCodes"
                        :key="code"
                        class="rounded-md bg-inset px-3 py-2 text-center font-mono text-sm text-body"
                    >
                        {{ code }}
                    </li>
                </ul>
                <BaseButton variant="secondary" @click="copyRecoveryCodes">Kodları kopyala</BaseButton>
            </div>

            <template #footer>
                <template v-if="tfaStep === 'setup'">
                    <BaseButton variant="ghost" @click="tfaModalOpen = false">Vazgeç</BaseButton>
                    <BaseButton :loading="tfaLoading" @click="confirmTwoFactor">Doğrula ve etkinleştir</BaseButton>
                </template>
                <BaseButton v-else @click="finishTwoFactorSetup">Kodları sakladım, bitir</BaseButton>
            </template>
        </BaseModal>

        <!-- ===== 2FA kapatma modalı ===== -->
        <BaseModal
            :open="disableModalOpen"
            title="2FA'yı devre dışı bırak"
            size="sm"
            @close="disableModalOpen = false"
        >
            <div class="flex flex-col gap-4">
                <p class="text-sm text-muted">
                    Hesabınızın ikinci koruma katmanı kaldırılacak. Devam etmek için parolanızı girin.
                </p>
                <FormField label="Parolanız" :error="disableError" required>
                    <BaseInput v-model="disablePassword" type="password" autocomplete="current-password" />
                </FormField>
            </div>
            <template #footer>
                <BaseButton variant="ghost" @click="disableModalOpen = false">Vazgeç</BaseButton>
                <BaseButton variant="danger" :loading="disableLoading" @click="disableTwoFactor">
                    Devre dışı bırak
                </BaseButton>
            </template>
        </BaseModal>

        <!-- ===== Diğer cihazlardan çıkış modalı ===== -->
        <BaseModal
            :open="othersModalOpen"
            title="Diğer cihazlardan çıkış"
            size="sm"
            @close="othersModalOpen = false"
        >
            <div class="flex flex-col gap-4">
                <p class="text-sm text-muted">
                    Bu cihaz dışındaki tüm oturumlar sonlandırılacak. Devam etmek için parolanızı girin.
                </p>
                <FormField label="Parolanız" :error="othersError" required>
                    <BaseInput v-model="othersPassword" type="password" autocomplete="current-password" />
                </FormField>
            </div>
            <template #footer>
                <BaseButton variant="ghost" @click="othersModalOpen = false">Vazgeç</BaseButton>
                <BaseButton variant="danger" :loading="othersLoading" @click="logoutOtherDevices">
                    Oturumları sonlandır
                </BaseButton>
            </template>
        </BaseModal>
        </div>
        </div>
    </PanelShell>
</template>
