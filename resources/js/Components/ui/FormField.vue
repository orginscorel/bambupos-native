<script setup lang="ts">
import { computed, provide, toRef } from 'vue';
import { useId } from '@/composables/useId';
import { FieldKey } from './formField';
import AppIcon from './AppIcon.vue';

const props = withDefaults(
    defineProps<{
        label: string;
        /** Doğrulama hatası; ikon + metinle gösterilir (yalnız renk değil) */
        error?: string;
        hint?: string;
        required?: boolean;
    }>(),
    { error: '', hint: '', required: false },
);

const id = useId('field');
const errorId = `${id}-error`;
const hintId = `${id}-hint`;

const describedBy = computed(() => {
    const ids: string[] = [];
    if (props.error) ids.push(errorId);
    if (props.hint) ids.push(hintId);
    return ids.length ? ids.join(' ') : undefined;
});

provide(FieldKey, {
    id,
    describedBy,
    invalid: computed(() => Boolean(props.error)),
    required: toRef(props, 'required').value,
});
</script>

<template>
    <div class="flex flex-col gap-1.5">
        <label :for="id" class="text-sm font-medium text-body">
            {{ label }}
            <span v-if="required" class="text-danger" aria-hidden="true">*</span>
            <span v-if="required" class="sr-only">(zorunlu)</span>
        </label>
        <slot />
        <p v-if="hint && !error" :id="hintId" class="text-xs text-muted">{{ hint }}</p>
        <p v-if="error" :id="errorId" class="flex items-center gap-1 text-xs font-medium text-danger">
            <AppIcon name="alert-circle" :size="14" />
            {{ error }}
        </p>
    </div>
</template>
