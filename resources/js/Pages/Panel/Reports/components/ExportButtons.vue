<script setup lang="ts">
import { ref } from 'vue';
import { ApiError } from '@/lib/http';
import { useToast } from '@/composables/useToast';
import BaseDropdown from '@/Components/ui/BaseDropdown.vue';
import DropdownItem from '@/Components/ui/DropdownItem.vue';
import BaseButton from '@/Components/ui/BaseButton.vue';
import AppIcon from '@/Components/ui/AppIcon.vue';
import { requestExport, type ReportFilterState } from '../reports';

/**
 * "Dışa aktar" düğmesi: seçilen biçim için kuyruğa iş bırakır (§23 —
 * dosya web isteğinde üretilmez). Sonuç "Dışa Aktarımlar" sekmesinde.
 */
const props = defineProps<{
    report: string;
    filters: ReportFilterState;
}>();

const emit = defineEmits<{ queued: [] }>();

const { success, danger } = useToast();
const busy = ref(false);

async function exportAs(format: 'csv' | 'xlsx' | 'pdf'): Promise<void> {
    if (busy.value) return;
    busy.value = true;
    try {
        await requestExport(props.report, format, props.filters);
        success('Dışa aktarma kuyruğa alındı', 'Hazır olunca "Dışa Aktarımlar" sekmesinden indirebilirsiniz.');
        emit('queued');
    } catch (e) {
        danger('Dışa aktarılamadı', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen hata.');
    } finally {
        busy.value = false;
    }
}
</script>

<template>
    <BaseDropdown align="right">
        <template #trigger="{ toggle }">
            <BaseButton variant="ghost" size="sm" :loading="busy" @click="toggle">
                <AppIcon name="arrow-right" :size="14" class="rotate-90" />
                Dışa aktar
            </BaseButton>
        </template>
        <DropdownItem @select="exportAs('csv')">CSV</DropdownItem>
        <DropdownItem @select="exportAs('xlsx')">Excel (XLSX)</DropdownItem>
        <DropdownItem @select="exportAs('pdf')">PDF</DropdownItem>
    </BaseDropdown>
</template>
