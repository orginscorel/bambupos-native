<script setup lang="ts">
import { computed, onMounted, reactive, ref } from 'vue';
import { Head, usePage } from '@inertiajs/vue3';
import { api, ApiError } from '@/lib/http';
import { authFromPage } from '@/types/auth';
import { useToast } from '@/composables/useToast';
import PanelShell from '@/Components/panel/PanelShell.vue';
import AppIcon from '@/Components/ui/AppIcon.vue';
import BaseBadge from '@/Components/ui/BaseBadge.vue';
import BaseButton from '@/Components/ui/BaseButton.vue';
import BaseCard from '@/Components/ui/BaseCard.vue';
import BaseInput from '@/Components/ui/BaseInput.vue';
import BaseModal from '@/Components/ui/BaseModal.vue';
import BaseSelect from '@/Components/ui/BaseSelect.vue';
import BaseSkeleton from '@/Components/ui/BaseSkeleton.vue';
import BaseTabs from '@/Components/ui/BaseTabs.vue';
import FormField from '@/Components/ui/FormField.vue';

/* ================= Tipler ================= */

type Mailer = 'smtp' | 'sendmail' | 'log';
type Scope = 'tenant' | 'platform';
type Source = 'tenant' | 'platform' | 'env';

interface MailSettingDto {
    id: number;
    tenant_id: number | null;
    mailer: Mailer;
    host: string | null;
    port: number | null;
    encryption: 'tls' | 'ssl' | 'none';
    username: string | null;
    from_name: string | null;
    from_address: string | null;
    reply_to: string | null;
    timeout: number;
    has_password: boolean;
}

interface ShowResponse {
    can_manage_platform: boolean;
    effective_source: Source;
    tenant: MailSettingDto | null;
    platform: MailSettingDto | null;
    platform_summary: { exists: boolean; mailer: string | null; from_address: string | null };
    env: { mailer: string; from_address: string | null };
    tenant_smtp_ports: number[];
}

interface MailForm {
    mailer: Mailer;
    host: string;
    port: string;
    encryption: 'tls' | 'ssl' | 'none';
    username: string;
    password: string;
    from_name: string;
    from_address: string;
    reply_to: string;
    timeout: string;
}

const page = usePage();
const auth = computed(() => authFromPage(page.props as Record<string, unknown>));
const { success, danger } = useToast();

/* ================= Durum ================= */

const loading = ref(true);
const loadFailed = ref(false);
const canManagePlatform = ref(false);
const effectiveSource = ref<Source>('env');
const platformSummary = ref<ShowResponse['platform_summary']>({ exists: false, mailer: null, from_address: null });
const envSummary = ref<ShowResponse['env']>({ mailer: 'log', from_address: null });
const tenantPorts = ref<number[]>([25, 465, 587, 2525]);
const hasOverride = ref(false);
const hasPassword = reactive<Record<Scope, boolean>>({ tenant: false, platform: false });

const activeScope = ref<Scope>('tenant');
const tabs = computed(() => [
    { key: 'tenant', label: 'İşletme ayarı', icon: 'settings' },
    ...(canManagePlatform.value ? [{ key: 'platform', label: 'Platform varsayılanı', icon: 'dashboard' }] : []),
]);

function emptyForm(): MailForm {
    return {
        mailer: 'smtp',
        host: '',
        port: '587',
        encryption: 'tls',
        username: '',
        password: '',
        from_name: '',
        from_address: '',
        reply_to: '',
        timeout: '30',
    };
}

const forms = reactive<Record<Scope, MailForm>>({ tenant: emptyForm(), platform: emptyForm() });
const errors = reactive<Record<Scope, Record<string, string>>>({ tenant: {}, platform: {} });
const saving = reactive<Record<Scope, boolean>>({ tenant: false, platform: false });

const form = computed(() => forms[activeScope.value]);
const err = computed(() => errors[activeScope.value]);

function fillForm(scope: Scope, dto: MailSettingDto | null): void {
    if (dto === null) return;
    forms[scope] = {
        mailer: dto.mailer,
        host: dto.host ?? '',
        port: dto.port !== null ? String(dto.port) : '587',
        encryption: dto.encryption ?? 'tls',
        username: dto.username ?? '',
        password: '', // parola sunucudan ASLA gelmez; boş = mevcut korunur
        from_name: dto.from_name ?? '',
        from_address: dto.from_address ?? '',
        reply_to: dto.reply_to ?? '',
        timeout: String(dto.timeout ?? 30),
    };
    hasPassword[scope] = dto.has_password;
}

async function load(): Promise<void> {
    loading.value = true;
    loadFailed.value = false;
    try {
        const data = await api<ShowResponse>('/api/v1/settings/mail');
        canManagePlatform.value = data.can_manage_platform;
        effectiveSource.value = data.effective_source;
        platformSummary.value = data.platform_summary;
        envSummary.value = data.env;
        tenantPorts.value = data.tenant_smtp_ports ?? tenantPorts.value;
        hasOverride.value = data.tenant !== null;
        fillForm('tenant', data.tenant);
        fillForm('platform', data.platform);
    } catch (e) {
        loadFailed.value = true;
        danger('Ayarlar yüklenemedi', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen bir hata oluştu.');
    } finally {
        loading.value = false;
    }
}

onMounted(load);

/* ================= Kaydet ================= */

async function save(scope: Scope): Promise<void> {
    if (saving[scope]) return;
    saving[scope] = true;
    errors[scope] = {};
    const f = forms[scope];
    try {
        const body: Record<string, unknown> = {
            mailer: f.mailer,
            from_name: f.from_name || null,
            from_address: f.from_address,
            reply_to: f.reply_to || null,
        };
        if (f.mailer === 'smtp') {
            body.host = f.host;
            body.port = f.port !== '' ? Number(f.port) : null;
            body.encryption = f.encryption;
            body.username = f.username || null;
            body.timeout = f.timeout !== '' ? Number(f.timeout) : 30;
            // Boş parola gönderilmez → sunucu mevcut parolayı korur.
            if (f.password !== '') body.password = f.password;
        }
        const res = await api<{ setting: MailSettingDto; effective_source: Source }>(
            `/api/v1/settings/mail/${scope}`,
            { method: 'PUT', body },
        );
        effectiveSource.value = res.effective_source;
        if (scope === 'tenant') hasOverride.value = true;
        fillForm(scope, res.setting);
        success('Ayarlar kaydedildi', scope === 'platform' ? 'Platform varsayılanı güncellendi.' : 'İşletme e-posta ayarı güncellendi.');
    } catch (e) {
        if (e instanceof ApiError && Object.keys(e.errors).length > 0) {
            const map: Record<string, string> = {};
            for (const key of Object.keys(e.errors)) map[key] = e.errors[key][0];
            errors[scope] = map;
            danger('Kaydedilemedi', 'Lütfen işaretli alanları düzeltin.');
        } else {
            danger('Kaydedilemedi', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen bir hata oluştu.');
        }
    } finally {
        saving[scope] = false;
    }
}

/* ================= Override kaldırma ================= */

const removeModalOpen = ref(false);
const removing = ref(false);

async function removeOverride(): Promise<void> {
    if (removing.value) return;
    removing.value = true;
    try {
        const res = await api<{ ok: boolean; effective_source: Source }>('/api/v1/settings/mail/tenant', { method: 'DELETE' });
        effectiveSource.value = res.effective_source;
        hasOverride.value = false;
        forms.tenant = emptyForm();
        hasPassword.tenant = false;
        removeModalOpen.value = false;
        success('Override kaldırıldı', 'E-postalar artık platform/sunucu varsayılanıyla gönderilecek.');
    } catch (e) {
        danger('Kaldırılamadı', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen bir hata oluştu.');
    } finally {
        removing.value = false;
    }
}

/* ================= Bağlantı testi ================= */

const testAddress = ref('');
const testing = ref(false);
const testResult = ref<null | { ok: boolean; message: string; note?: string | null }>(null);

onMounted(() => {
    testAddress.value = auth.value?.user?.email ?? '';
});

async function sendTest(): Promise<void> {
    if (testing.value) return;
    testing.value = true;
    testResult.value = null;
    try {
        const res = await api<{ ok: boolean; error?: string; note?: string | null; driver?: string; source?: Source }>(
            '/api/v1/settings/mail/test',
            { method: 'POST', body: { to: testAddress.value } },
        );
        testResult.value = res.ok
            ? {
                ok: true,
                message: `Deneme e-postası "${testAddress.value}" adresine gönderildi (kaynak: ${sourceLabel(res.source ?? effectiveSource.value)}, sürücü: ${res.driver ?? '—'}). Gelen kutusunu (ve spam klasörünü) kontrol edin.`,
                note: res.note ?? null,
            }
            : { ok: false, message: res.error ?? 'E-posta gönderilemedi.' };
    } catch (e) {
        // 422 (geçersiz adres) / 429 (hız sınırı) buradan düşer.
        testResult.value = { ok: false, message: e instanceof ApiError ? e.displayMessage : 'Beklenmeyen bir hata oluştu.' };
    } finally {
        testing.value = false;
    }
}

/* ================= Görsel yardımcılar ================= */

function sourceLabel(source: Source): string {
    return source === 'tenant' ? 'işletme ayarı' : source === 'platform' ? 'platform varsayılanı' : 'sunucu (.env) varsayılanı';
}

const sourceBadge = computed(() => {
    switch (effectiveSource.value) {
        case 'tenant':
            return { variant: 'success' as const, text: 'İşletme override’ı geçerli' };
        case 'platform':
            return { variant: 'info' as const, text: 'Platform varsayılanı geçerli' };
        default:
            return { variant: 'warning' as const, text: 'Sunucu (.env) varsayılanı geçerli' };
    }
});

const mailerOptions = [
    { value: 'smtp', label: 'SMTP (gerçek gönderim)' },
    { value: 'sendmail', label: 'Sendmail (sunucu üzerinden)' },
    { value: 'log', label: 'Log (geliştirme — gerçek gönderim YAPILMAZ)' },
];

const encryptionOptions = [
    { value: 'tls', label: 'TLS / STARTTLS (genelde port 587)' },
    { value: 'ssl', label: 'SSL (genelde port 465)' },
    { value: 'none', label: 'Şifreleme yok' },
];

const passwordPlaceholder = computed(() =>
    hasPassword[activeScope.value] ? '•••••••• (değiştirmek için yeni parola girin)' : 'SMTP parolası',
);
</script>

<template>
    <Head title="E-posta Ayarları" />

    <PanelShell title="E-posta Ayarları">
        <div class="mx-auto flex w-full max-w-3xl flex-col gap-5">

            <!-- ================= Yükleniyor ================= -->
            <template v-if="loading">
                <BaseCard><BaseSkeleton class="h-24" /></BaseCard>
                <BaseCard><BaseSkeleton class="h-64" /></BaseCard>
            </template>

            <template v-else-if="!loadFailed">

                <!-- ================= Geçerli ayar ================= -->
                <BaseCard title="Şu an geçerli ayar">
                    <template #actions>
                        <BaseBadge :variant="sourceBadge.variant">{{ sourceBadge.text }}</BaseBadge>
                    </template>
                    <p class="text-sm text-muted">
                        Bu işletmeden çıkan e-postalar (parola sıfırlama vb.) şu sırayla belirlenir:
                        önce <strong class="text-body">işletme override’ı</strong>, yoksa
                        <strong class="text-body">platform varsayılanı</strong>, o da yoksa
                        <strong class="text-body">sunucu (.env) yapılandırması</strong>.
                    </p>
                    <ul class="mt-3 flex flex-col gap-1.5 text-sm">
                        <li class="flex items-center gap-2">
                            <AppIcon name="check-circle" :size="15"
                                :class="effectiveSource === 'tenant' ? 'text-success' : 'text-subtle opacity-40'" />
                            <span :class="effectiveSource === 'tenant' ? 'font-medium text-body' : 'text-muted'">
                                İşletme override’ı — {{ hasOverride ? 'tanımlı' : 'tanımlı değil' }}
                            </span>
                        </li>
                        <li class="flex items-center gap-2">
                            <AppIcon name="check-circle" :size="15"
                                :class="effectiveSource === 'platform' ? 'text-success' : 'text-subtle opacity-40'" />
                            <span :class="effectiveSource === 'platform' ? 'font-medium text-body' : 'text-muted'">
                                Platform varsayılanı —
                                {{ platformSummary.exists ? `tanımlı (${platformSummary.mailer}${platformSummary.from_address ? ', ' + platformSummary.from_address : ''})` : 'tanımlı değil' }}
                            </span>
                        </li>
                        <li class="flex items-center gap-2">
                            <AppIcon name="check-circle" :size="15"
                                :class="effectiveSource === 'env' ? 'text-success' : 'text-subtle opacity-40'" />
                            <span :class="effectiveSource === 'env' ? 'font-medium text-body' : 'text-muted'">
                                Sunucu (.env) — sürücü: {{ envSummary.mailer }}<template v-if="envSummary.mailer === 'log'"> (e-postalar gerçekte gönderilmez)</template>
                            </span>
                        </li>
                    </ul>
                </BaseCard>

                <!-- ================= Ayar formu ================= -->
                <BaseTabs v-if="canManagePlatform" v-model="activeScope" :tabs="tabs" class="-mb-3" />

                <BaseCard :title="activeScope === 'platform' ? 'Platform varsayılan e-posta ayarı' : 'İşletme e-posta ayarı'">
                    <template v-if="activeScope === 'tenant'" #actions>
                        <BaseBadge :variant="hasOverride ? 'success' : 'neutral'" :no-icon="!hasOverride">
                            {{ hasOverride ? 'Override tanımlı' : 'Override yok' }}
                        </BaseBadge>
                    </template>

                    <p class="mb-4 text-sm text-muted">
                        <template v-if="activeScope === 'platform'">
                            Kendi ayarı olmayan tüm işletmelerin e-postaları buradan gönderilir.
                        </template>
                        <template v-else>
                            İşletmenizin e-postalarını kendi adresinizden göndermek için doldurun.
                            Boş bırakırsanız platform/sunucu varsayılanı kullanılır.
                        </template>
                    </p>

                    <form class="flex flex-col gap-4" novalidate @submit.prevent="save(activeScope)">
                        <FormField label="Sürücü" :error="err.mailer" required>
                            <BaseSelect v-model="form.mailer" :options="mailerOptions" />
                        </FormField>

                        <template v-if="form.mailer === 'smtp'">
                            <div class="grid grid-cols-1 gap-4 sm:grid-cols-3">
                                <div class="sm:col-span-2">
                                    <FormField label="Sunucu adresi" :error="err.host" required>
                                        <BaseInput v-model="form.host" placeholder="ör. smtp.example.com" autocomplete="off" />
                                    </FormField>
                                </div>
                                <FormField
                                    label="Port"
                                    :error="err.port"
                                    :hint="!canManagePlatform ? `İzin verilen portlar: ${tenantPorts.join(', ')}` : ''"
                                    required
                                >
                                    <BaseInput v-model="form.port" inputmode="numeric" placeholder="587" autocomplete="off" />
                                </FormField>
                            </div>

                            <FormField label="Şifreleme" :error="err.encryption" required>
                                <BaseSelect v-model="form.encryption" :options="encryptionOptions" />
                            </FormField>

                            <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
                                <FormField label="Kullanıcı adı" :error="err.username">
                                    <BaseInput v-model="form.username" placeholder="genelde e-posta adresi" autocomplete="off" />
                                </FormField>
                                <FormField
                                    label="Parola"
                                    :error="err.password"
                                    :hint="hasPassword[activeScope] ? 'Kayıtlı bir parola var; boş bırakırsanız korunur.' : ''"
                                >
                                    <BaseInput
                                        v-model="form.password"
                                        type="password"
                                        :placeholder="passwordPlaceholder"
                                        autocomplete="new-password"
                                    />
                                </FormField>
                            </div>
                        </template>

                        <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
                            <FormField label="Gönderen adı" :error="err.from_name">
                                <BaseInput v-model="form.from_name" placeholder="ör. işletme adınız" autocomplete="off" />
                            </FormField>
                            <FormField label="Gönderen adresi" :error="err.from_address" required>
                                <BaseInput v-model="form.from_address" type="email" placeholder="ör. bilgi@isletme.com" autocomplete="off" />
                            </FormField>
                        </div>

                        <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
                            <FormField label="Yanıt adresi (reply-to)" :error="err.reply_to" hint="Boşsa gönderen adresi kullanılır.">
                                <BaseInput v-model="form.reply_to" type="email" autocomplete="off" />
                            </FormField>
                            <FormField v-if="form.mailer === 'smtp'" label="Zaman aşımı (saniye)" :error="err.timeout" hint="5–120 arası">
                                <BaseInput v-model="form.timeout" inputmode="numeric" autocomplete="off" />
                            </FormField>
                        </div>

                        <div class="flex flex-wrap items-center gap-3 pt-1">
                            <BaseButton type="submit" :loading="saving[activeScope]">Kaydet</BaseButton>
                            <BaseButton
                                v-if="activeScope === 'tenant' && hasOverride"
                                variant="danger"
                                type="button"
                                @click="removeModalOpen = true"
                            >
                                Override’ı kaldır
                            </BaseButton>
                        </div>
                    </form>
                </BaseCard>

                <!-- ================= Bağlantı testi ================= -->
                <BaseCard title="Bağlantı testi">
                    <p class="mb-4 text-sm text-muted">
                        Şu an <strong class="text-body">geçerli</strong> ayarla ({{ sourceLabel(effectiveSource) }})
                        girilen adrese gerçek bir deneme e-postası gönderilir. Kaydedilmemiş form
                        değişiklikleri teste dahil değildir — önce kaydedin.
                    </p>
                    <form class="flex max-w-md flex-col gap-4" novalidate @submit.prevent="sendTest">
                        <FormField label="Alıcı adresi" required>
                            <BaseInput v-model="testAddress" type="email" autocomplete="off" />
                        </FormField>
                        <div>
                            <BaseButton type="submit" variant="secondary" :loading="testing">
                                Test e-postası gönder
                            </BaseButton>
                        </div>
                    </form>

                    <div
                        v-if="testResult"
                        class="mt-4 flex items-start gap-2.5 rounded-md border p-3 text-sm"
                        :class="testResult.ok ? 'border-success/40 text-body' : 'border-danger/50 text-body'"
                        role="status"
                    >
                        <AppIcon
                            :name="testResult.ok ? 'check-circle' : 'alert-circle'"
                            :size="18"
                            :class="testResult.ok ? 'mt-0.5 shrink-0 text-success' : 'mt-0.5 shrink-0 text-danger'"
                        />
                        <div class="flex flex-col gap-1">
                            <span class="font-medium">{{ testResult.ok ? 'Gönderim başarılı' : 'Gönderim başarısız' }}</span>
                            <span class="text-muted">{{ testResult.message }}</span>
                            <span v-if="testResult.note" class="font-medium text-warning">{{ testResult.note }}</span>
                        </div>
                    </div>
                </BaseCard>
            </template>

            <!-- ================= Override kaldırma onayı ================= -->
            <BaseModal :open="removeModalOpen" title="Override kaldırılsın mı?" @close="removeModalOpen = false">
                <p class="text-sm text-muted">
                    İşletmenizin özel e-posta ayarı silinecek; e-postalar bundan sonra
                    {{ platformSummary.exists ? 'platform varsayılanıyla' : 'sunucu (.env) varsayılanıyla' }} gönderilecek.
                    Kayıtlı SMTP parolası da silinir.
                </p>
                <div class="mt-5 flex justify-end gap-3">
                    <BaseButton variant="ghost" @click="removeModalOpen = false">Vazgeç</BaseButton>
                    <BaseButton variant="danger" :loading="removing" @click="removeOverride">Kaldır</BaseButton>
                </div>
            </BaseModal>
        </div>
    </PanelShell>
</template>
