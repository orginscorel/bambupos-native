<script setup lang="ts">
import { computed, onMounted, ref } from 'vue';
import { Head, usePage } from '@inertiajs/vue3';
import { api, ApiError } from '@/lib/http';
import { useToast } from '@/composables/useToast';
import PanelShell from '@/Components/panel/PanelShell.vue';
import AppIcon from '@/Components/ui/AppIcon.vue';
import BaseBadge from '@/Components/ui/BaseBadge.vue';
import BaseButton from '@/Components/ui/BaseButton.vue';
import BaseCard from '@/Components/ui/BaseCard.vue';
import BaseInput from '@/Components/ui/BaseInput.vue';
import BaseModal from '@/Components/ui/BaseModal.vue';
import BaseSelect from '@/Components/ui/BaseSelect.vue';
import EmptyState from '@/Components/ui/EmptyState.vue';
import FormField from '@/Components/ui/FormField.vue';
import {
    fetchRegisters,
    fetchSessionDetail,
    fetchSessions,
    metaFromProps,
    money,
    parseMoney,
    type MovementRow,
    type RegisterRow,
    type SessionReport,
    type SessionRow,
} from './payments';

/**
 * KASA YÖNETİMİ (prompt §16): kasalar, oturum açılış/kapanış, nakit
 * giriş/çıkış/masraf/avans, ters kayıt, sayım (kör), X raporu, Z geçmişi.
 */
const page = usePage();
const meta = metaFromProps(page.props as Record<string, unknown>);
const { success, danger } = useToast();

const registers = ref<RegisterRow[]>([]);
const history = ref<SessionRow[]>([]);
const loading = ref(true);

async function load(): Promise<void> {
    loading.value = true;
    try {
        registers.value = await fetchRegisters();
        history.value = (await fetchSessions()).filter((s) => s.status === 'closed').slice(0, 20);
        if (activeSession.value) await openDetail(activeSession.value.id, true);
    } catch (e) {
        danger('Yüklenemedi', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen hata.');
    } finally {
        loading.value = false;
    }
}

onMounted(load);

/* ---- Yeni kasa ---- */
const newRegisterOpen = ref(false);
const newRegisterName = ref('');
const busy = ref(false);

const branchOptions = computed(() => {
    const auth = (page.props as Record<string, any>).auth;
    return (auth?.branches ?? []).map((b: { id: number; name: string }) => ({ value: String(b.id), label: b.name }));
});
const newRegisterBranch = ref('');

async function createRegister(): Promise<void> {
    if (busy.value) return;
    busy.value = true;
    try {
        await api('/api/v1/cash/registers', {
            method: 'POST',
            body: {
                name: newRegisterName.value,
                branch_id: Number(newRegisterBranch.value || branchOptions.value[0]?.value),
            },
        });
        success('Kasa oluşturuldu', newRegisterName.value);
        newRegisterOpen.value = false;
        newRegisterName.value = '';
        await load();
    } catch (e) {
        danger('Oluşturulamadı', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen hata.');
    } finally {
        busy.value = false;
    }
}

/* ---- Oturum açma ---- */
const openTarget = ref<RegisterRow | null>(null);
const openingFloatText = ref('');

function startOpen(register: RegisterRow): void {
    openTarget.value = register;
    // Devir önerisi: son kapanışın sayılan nakiti.
    const lastClosed = history.value.find((s) => s.cash_register_id === register.id);
    openingFloatText.value = lastClosed?.counted_cash_minor != null ? money(lastClosed.counted_cash_minor) : '';
}

async function openSession(): Promise<void> {
    if (!openTarget.value || busy.value) return;
    const amount = parseMoney(openingFloatText.value) ?? 0;
    busy.value = true;
    try {
        await api('/api/v1/cash/sessions', {
            method: 'POST',
            body: { cash_register_id: openTarget.value.id, opening_float_minor: amount },
        });
        success('Kasa açıldı', `Açılış: ${money(amount)} ₺`);
        openTarget.value = null;
        await load();
    } catch (e) {
        danger('Açılamadı', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen hata.');
    } finally {
        busy.value = false;
    }
}

/* ---- Açık oturum detayı (X) ---- */
const activeSession = ref<SessionRow | null>(null);
const movements = ref<MovementRow[]>([]);
const report = ref<SessionReport | null>(null);

async function openDetail(sessionId: number, silent = false): Promise<void> {
    try {
        const res = await fetchSessionDetail(sessionId);
        activeSession.value = res.session;
        movements.value = res.movements;
        report.value = res.report;
    } catch (e) {
        if (!silent) danger('Oturum yüklenemedi', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen hata.');
    }
}

/* ---- Hareket ekleme ---- */
const movementOpen = ref(false);
const movementType = ref('cash_in');
const movementAmountText = ref('');
const movementReason = ref('');

async function addMovement(): Promise<void> {
    if (!activeSession.value || busy.value) return;
    const amount = parseMoney(movementAmountText.value);
    if (!amount || amount <= 0) {
        danger('Tutar geçersiz', 'Pozitif bir tutar girin.');
        return;
    }
    busy.value = true;
    try {
        await api(`/api/v1/cash/sessions/${activeSession.value.id}/movements`, {
            method: 'POST',
            body: { type: movementType.value, amount_minor: amount, reason: movementReason.value },
        });
        success('Hareket eklendi', '');
        movementOpen.value = false;
        movementAmountText.value = '';
        movementReason.value = '';
        await openDetail(activeSession.value.id, true);
    } catch (e) {
        danger('Eklenemedi', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen hata.');
    } finally {
        busy.value = false;
    }
}

/* ---- Ters kayıt ---- */
const reverseTarget = ref<MovementRow | null>(null);
const reverseReason = ref('');

async function doReverse(): Promise<void> {
    if (!reverseTarget.value || !activeSession.value || busy.value) return;
    busy.value = true;
    try {
        await api(`/api/v1/cash/movements/${reverseTarget.value.id}/reverse`, {
            method: 'POST',
            body: { reason: reverseReason.value },
        });
        success('Ters kayıt açıldı', 'Orijinal kayıt izli şekilde düzeltildi.');
        reverseTarget.value = null;
        reverseReason.value = '';
        await openDetail(activeSession.value.id, true);
    } catch (e) {
        danger('Düzeltilemedi', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen hata.');
    } finally {
        busy.value = false;
    }
}

/* ---- Kapanış (kör sayım) ---- */
const closeOpen = ref(false);
const countedText = ref('');
const closingNote = ref('');

const countedMinor = computed(() => parseMoney(countedText.value));
const previewDifference = computed(() => {
    if (countedMinor.value === null || !report.value) return null;
    return countedMinor.value - report.value.expected_cash_minor;
});

async function closeSession(): Promise<void> {
    if (!activeSession.value || busy.value || countedMinor.value === null) return;
    busy.value = true;
    try {
        const res = await api<{ session: SessionRow }>(`/api/v1/cash/sessions/${activeSession.value.id}/close`, {
            method: 'POST',
            body: { counted_cash_minor: countedMinor.value, closing_note: closingNote.value || null },
        });
        const d = res.session.difference_minor ?? 0;
        success('Kasa kapatıldı', d === 0 ? 'Fark yok.' : `Fark: ${d > 0 ? '+' : '−'}${money(Math.abs(d))} ₺`);
        closeOpen.value = false;
        countedText.value = '';
        closingNote.value = '';
        activeSession.value = null;
        report.value = null;
        movements.value = [];
        await load();
    } catch (e) {
        danger('Kapatılamadı', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen hata.');
    } finally {
        busy.value = false;
    }
}
</script>

<template>
    <Head title="Kasa yönetimi" />
    <PanelShell title="Kasa yönetimi" flush canvas>
        <div class="min-h-0 flex-1 overflow-y-auto p-3 pb-24 sm:p-4 lg:pb-4">
        <div class="mx-auto flex w-full max-w-[1440px] flex-col gap-3">

        <div class="flex flex-col gap-4">
            <!-- Kasalar -->
            <BaseCard title="Kasalar" flush>
                <template #actions>
                    <BaseButton v-if="meta.canCashManage" size="sm" variant="secondary" @click="newRegisterOpen = true">
                        <AppIcon name="plus" :size="14" /> Yeni kasa
                    </BaseButton>
                </template>
                <p v-if="loading" class="p-6 text-center text-sm text-muted">Yükleniyor…</p>
                <EmptyState
                    v-else-if="registers.length === 0"
                    title="Kasa tanımlı değil"
                    description="Ödeme oturumu açmak için önce bir kasa oluşturun."
                    icon="cart"
                />
                <ul v-else class="divide-y divide-default">
                    <li v-for="r in registers" :key="r.id" class="flex flex-wrap items-center justify-between gap-2 p-3">
                        <div class="flex items-center gap-3">
                            <AppIcon name="cart" :size="18" class="text-subtle" />
                            <div>
                                <p class="font-medium text-body">{{ r.name }}</p>
                                <p v-if="r.open_session" class="text-xs text-muted">
                                    Z#{{ r.open_session.z_number }} · {{ r.open_session.opened_by ?? '—' }} ·
                                    açılış {{ money(r.open_session.opening_float_minor) }} ₺
                                </p>
                            </div>
                        </div>
                        <div class="flex items-center gap-2">
                            <BaseBadge v-if="r.open_session" variant="success"><AppIcon name="check-circle" :size="12" /> Açık</BaseBadge>
                            <BaseBadge v-else variant="neutral" no-icon>Kapalı</BaseBadge>
                            <BaseButton
                                v-if="r.open_session"
                                size="sm"
                                variant="secondary"
                                @click="openDetail(r.open_session.id)"
                            >
                                Oturumu yönet
                            </BaseButton>
                            <BaseButton
                                v-else-if="meta.canCashManage"
                                size="sm"
                                @click="startOpen(r)"
                            >
                                Kasayı aç
                            </BaseButton>
                        </div>
                    </li>
                </ul>
            </BaseCard>

            <!-- Açık oturum: X raporu + hareketler -->
            <template v-if="activeSession && report">
                <BaseCard :title="`${activeSession.register_name ?? 'Kasa'} · Z#${activeSession.z_number} (açık)`">
                    <template #actions>
                        <div class="flex gap-2">
                            <BaseButton v-if="meta.canCashManage" size="sm" variant="secondary" @click="movementOpen = true">
                                <AppIcon name="plus" :size="14" /> Hareket
                            </BaseButton>
                            <BaseButton v-if="meta.canCashManage" size="sm" variant="danger" @click="closeOpen = true">
                                Sayım & kapanış
                            </BaseButton>
                        </div>
                    </template>

                    <div class="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
                        <div class="rounded-lg border border-default p-3">
                            <p class="text-xs text-muted">Açılış kasası</p>
                            <p class="text-lg font-semibold tabular-nums">{{ money(report.opening_float_minor) }} ₺</p>
                        </div>
                        <div class="rounded-lg border border-default p-3">
                            <p class="text-xs text-muted">Beklenen nakit (X)</p>
                            <p class="text-lg font-semibold tabular-nums">{{ money(report.expected_cash_minor) }} ₺</p>
                        </div>
                        <div class="rounded-lg border border-default p-3">
                            <p class="text-xs text-muted">Tahsilat ({{ report.payments_count }})</p>
                            <p class="text-lg font-semibold tabular-nums">{{ money(report.payments_total_minor) }} ₺</p>
                        </div>
                        <div class="rounded-lg border border-default p-3">
                            <p class="text-xs text-muted">Bahşiş</p>
                            <p class="text-lg font-semibold tabular-nums">{{ money(report.tips_total_minor) }} ₺</p>
                        </div>
                    </div>

                    <div v-if="report.by_method.length > 0" class="mt-3">
                        <p class="mb-1 text-sm font-medium text-body">Yöntem kırılımı</p>
                        <ul class="divide-y divide-default rounded-lg border border-default">
                            <li v-for="m in report.by_method" :key="m.method" class="flex justify-between p-2 text-sm">
                                <span>{{ m.label }} ({{ m.count }})</span>
                                <span class="tabular-nums">{{ money(m.net_minor) }} ₺</span>
                            </li>
                        </ul>
                    </div>
                </BaseCard>

                <BaseCard title="Kasa hareketleri (değişmez defter)" flush>
                    <EmptyState v-if="movements.length === 0" title="Hareket yok" icon="inbox" />
                    <ul v-else class="divide-y divide-default">
                        <li v-for="m in movements" :key="m.id" class="flex flex-wrap items-center justify-between gap-2 p-3 text-sm">
                            <div class="flex min-w-0 flex-col">
                                <span class="flex items-center gap-2 font-medium text-body">
                                    <AppIcon :name="m.direction === 'in' ? 'arrow-right' : 'arrow-left'" :size="14"
                                        :class="m.direction === 'in' ? 'text-success' : 'text-danger'" />
                                    {{ m.type_label }}
                                    <span class="tabular-nums">{{ m.direction === 'in' ? '+' : '−' }}{{ money(m.amount_minor) }} ₺</span>
                                </span>
                                <span class="text-xs text-muted">{{ m.user ?? 'Sistem' }} · {{ m.reason ?? '—' }}</span>
                            </div>
                            <div class="flex items-center gap-2">
                                <BaseBadge v-if="m.reversed_by_id" variant="warning" no-icon>Ters kayıtla düzeltildi</BaseBadge>
                                <BaseBadge v-else-if="m.reverses_id" variant="info" no-icon>Düzeltme kaydı</BaseBadge>
                                <BaseButton
                                    v-if="meta.canCashManage && !m.reversed_by_id && !m.reverses_id && m.type !== 'opening_float' && m.type !== 'payment' && m.type !== 'refund'"
                                    variant="ghost"
                                    size="sm"
                                    @click="reverseTarget = m"
                                >
                                    Ters kayıt
                                </BaseButton>
                            </div>
                        </li>
                    </ul>
                </BaseCard>
            </template>

            <!-- Z geçmişi -->
            <BaseCard title="Kapanan oturumlar (Z geçmişi)" flush>
                <EmptyState v-if="history.length === 0" title="Kapanmış oturum yok" icon="inbox" />
                <ul v-else class="divide-y divide-default">
                    <li v-for="s in history" :key="s.id" class="flex flex-wrap items-center justify-between gap-2 p-3 text-sm">
                        <div class="flex min-w-0 flex-col">
                            <span class="font-medium text-body">{{ s.register_name ?? 'Kasa' }} · Z#{{ s.z_number }}</span>
                            <span class="text-xs text-muted">
                                {{ s.closed_at ? new Date(s.closed_at).toLocaleString('tr-TR') : '' }} · {{ s.closed_by ?? '—' }}
                            </span>
                        </div>
                        <div class="flex items-center gap-2">
                            <BaseBadge
                                :variant="(s.difference_minor ?? 0) === 0 ? 'success' : 'danger'"
                                no-icon
                            >
                                Fark: {{ (s.difference_minor ?? 0) > 0 ? '+' : (s.difference_minor ?? 0) < 0 ? '−' : '' }}{{ money(Math.abs(s.difference_minor ?? 0)) }} ₺
                            </BaseBadge>
                            <BaseButton size="sm" variant="secondary" :href="`/panel/kasa/z/${s.id}`">Z raporu</BaseButton>
                        </div>
                    </li>
                </ul>
            </BaseCard>
        </div>

        <!-- Yeni kasa modalı -->
        <BaseModal :open="newRegisterOpen" title="Yeni kasa" @close="newRegisterOpen = false">
            <div class="flex flex-col gap-3">
                <FormField label="Şube" required>
                    <BaseSelect v-model="newRegisterBranch" :options="branchOptions" placeholder="Şube seç" />
                </FormField>
                <FormField label="Kasa adı" required>
                    <BaseInput v-model="newRegisterName" placeholder="ör. Ana Kasa, Bar Kasası" />
                </FormField>
                <div class="flex justify-end gap-2">
                    <BaseButton variant="secondary" @click="newRegisterOpen = false">Vazgeç</BaseButton>
                    <BaseButton :loading="busy" :disabled="newRegisterName.trim().length < 2" @click="createRegister">Oluştur</BaseButton>
                </div>
            </div>
        </BaseModal>

        <!-- Oturum açma modalı -->
        <BaseModal :open="openTarget !== null" title="Kasa aç" @close="openTarget = null">
            <div class="flex flex-col gap-3">
                <p class="text-sm text-muted">{{ openTarget?.name }} için yeni oturum. Açılış tutarı devir önerisiyle dolu gelir.</p>
                <FormField label="Açılış kasası (₺)" hint="Son kapanışın sayılan nakiti önerilir (devir)">
                    <BaseInput v-model="openingFloatText" inputmode="decimal" placeholder="0,00" />
                </FormField>
                <div class="flex justify-end gap-2">
                    <BaseButton variant="secondary" @click="openTarget = null">Vazgeç</BaseButton>
                    <BaseButton :loading="busy" @click="openSession">Kasayı aç</BaseButton>
                </div>
            </div>
        </BaseModal>

        <!-- Hareket modalı -->
        <BaseModal :open="movementOpen" title="Kasa hareketi" @close="movementOpen = false">
            <div class="flex flex-col gap-3">
                <FormField label="Tür" required>
                    <BaseSelect
                        v-model="movementType"
                        :options="meta.movementTypes.map((t) => ({ value: t.value, label: `${t.label} (${t.direction === 'in' ? 'giriş' : 'çıkış'})` }))"
                    />
                </FormField>
                <FormField label="Tutar (₺)" required>
                    <BaseInput v-model="movementAmountText" inputmode="decimal" placeholder="0,00" />
                </FormField>
                <FormField label="Açıklama" required>
                    <BaseInput v-model="movementReason" placeholder="ör. temizlik malzemesi" />
                </FormField>
                <div class="flex justify-end gap-2">
                    <BaseButton variant="secondary" @click="movementOpen = false">Vazgeç</BaseButton>
                    <BaseButton :loading="busy" :disabled="movementReason.trim().length < 3" @click="addMovement">Ekle</BaseButton>
                </div>
            </div>
        </BaseModal>

        <!-- Ters kayıt modalı -->
        <BaseModal :open="reverseTarget !== null" title="Ters kayıt" @close="reverseTarget = null">
            <div class="flex flex-col gap-3">
                <p class="text-sm text-muted">
                    Kayıtlar silinmez/değiştirilmez; yönü ters yeni kayıt açılır ve ikisi birbirine bağlanır (denetim izi).
                </p>
                <FormField label="Neden" required>
                    <BaseInput v-model="reverseReason" placeholder="ör. hatalı tutar girildi" />
                </FormField>
                <div class="flex justify-end gap-2">
                    <BaseButton variant="secondary" @click="reverseTarget = null">Vazgeç</BaseButton>
                    <BaseButton variant="danger" :loading="busy" :disabled="reverseReason.trim().length < 3" @click="doReverse">
                        Ters kayıt aç
                    </BaseButton>
                </div>
            </div>
        </BaseModal>

        <!-- Kapanış (kör sayım) modalı -->
        <BaseModal :open="closeOpen" title="Sayım & kapanış" @close="closeOpen = false">
            <div class="flex flex-col gap-3">
                <p class="text-sm text-muted">
                    Çekmecedeki nakiti sayıp girin. Beklenen tutar, sayım girilmeden gösterilmez (kör sayım);
                    fark kapanışta hesaplanır ve Z raporuna dondurulur.
                </p>
                <FormField label="Sayılan nakit (₺)" required>
                    <BaseInput v-model="countedText" inputmode="decimal" placeholder="0,00" />
                </FormField>
                <div v-if="countedMinor !== null && report" class="rounded-lg border border-default bg-inset p-3 text-sm">
                    <div class="flex justify-between"><span class="text-muted">Beklenen</span><span class="tabular-nums">{{ money(report.expected_cash_minor) }} ₺</span></div>
                    <div class="flex justify-between"><span class="text-muted">Sayılan</span><span class="tabular-nums">{{ money(countedMinor) }} ₺</span></div>
                    <div class="flex justify-between font-semibold" :class="(previewDifference ?? 0) === 0 ? 'text-success' : 'text-danger'">
                        <span>Fark</span>
                        <span class="tabular-nums">{{ (previewDifference ?? 0) > 0 ? '+' : (previewDifference ?? 0) < 0 ? '−' : '' }}{{ money(Math.abs(previewDifference ?? 0)) }} ₺</span>
                    </div>
                </div>
                <FormField label="Kapanış notu">
                    <BaseInput v-model="closingNote" placeholder="İsteğe bağlı" />
                </FormField>
                <div class="flex justify-end gap-2">
                    <BaseButton variant="secondary" @click="closeOpen = false">Vazgeç</BaseButton>
                    <BaseButton variant="danger" :loading="busy" :disabled="countedMinor === null" @click="closeSession">
                        Kasayı kapat (Z)
                    </BaseButton>
                </div>
            </div>
        </BaseModal>
        </div>
        </div>
    </PanelShell>
</template>
