<script setup lang="ts">
import BaseModal from '@/Components/ui/BaseModal.vue';
import BaseButton from '@/Components/ui/BaseButton.vue';

withDefaults(
    defineProps<{
        open: boolean;
        title: string;
        message: string;
        confirmLabel?: string;
        busy?: boolean;
    }>(),
    { confirmLabel: 'Sil', busy: false },
);

const emit = defineEmits<{ close: []; confirm: [] }>();
</script>

<template>
    <BaseModal :open="open" :title="title" size="sm" @close="emit('close')">
        <p class="text-sm text-body">{{ message }}</p>
        <template #footer>
            <BaseButton variant="secondary" @click="emit('close')">Vazgeç</BaseButton>
            <BaseButton variant="danger" :loading="busy" @click="emit('confirm')">{{ confirmLabel }}</BaseButton>
        </template>
    </BaseModal>
</template>
