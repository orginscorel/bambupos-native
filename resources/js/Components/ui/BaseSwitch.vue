<script setup lang="ts">
import { useId } from '@/composables/useId';

/**
 * Anahtar (switch): açık/kapalı durumlar için tek dokunuşluk kontrol.
 * BaseCheckbox'ın "anlık etki" kardeşi — kaydetme beklemeyen aç/kapa
 * işlemlerinde (aktif/pasif, mevcut/tükendi, izin hücresi) kullanılır.
 *
 * Erişilebilirlik: role="switch" + aria-checked; Space/Enter ile değişir.
 */
const props = withDefaults(
    defineProps<{
        modelValue?: boolean;
        /** Görünen etiket; boş bırakılırsa yalnız anahtar çizilir (aria-label verin). */
        label?: string;
        description?: string;
        /** Etiket görsel gizli, ekran okuyucuya açık (tablo hücreleri). */
        ariaLabel?: string;
        disabled?: boolean;
        /** İstek sürerken kilitle (iyimser güncelleme yapmayan kullanımlar). */
        busy?: boolean;
        /** Kompakt boy (tablo satırları). */
        size?: 'sm' | 'md';
        /** Tehlikeli izin hücreleri: açıkken uyarı rengi. */
        variant?: 'primary' | 'danger';
        /** Etiket solda mı sağda mı dursun. */
        labelPosition?: 'left' | 'right';
    }>(),
    {
        modelValue: false,
        label: '',
        description: '',
        ariaLabel: '',
        disabled: false,
        busy: false,
        size: 'md',
        variant: 'primary',
        labelPosition: 'right',
    },
);

const emit = defineEmits<{ 'update:modelValue': [value: boolean] }>();
const id = useId('sw');
const descId = `${id}-desc`;

function toggle(): void {
    if (props.disabled || props.busy) return;
    emit('update:modelValue', !props.modelValue);
}
</script>

<template>
    <span
        class="inline-flex min-w-0 items-center gap-3"
        :class="[
            labelPosition === 'left' ? 'flex-row-reverse justify-end' : '',
            disabled ? 'opacity-55' : '',
        ]"
    >
        <button
            :id="id"
            type="button"
            role="switch"
            :aria-checked="modelValue"
            :aria-label="ariaLabel || undefined"
            :aria-describedby="description ? descId : undefined"
            :aria-busy="busy || undefined"
            :disabled="disabled || busy"
            class="relative inline-flex shrink-0 cursor-pointer items-center rounded-full border
                   transition-colors duration-(--dur-fast)
                   focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring-brand
                   disabled:cursor-not-allowed"
            :class="[
                size === 'sm' ? 'h-5 w-9' : 'h-6 w-11',
                modelValue
                    ? variant === 'danger'
                        ? 'border-danger-border bg-danger'
                        : 'border-primary bg-primary'
                    : 'border-strong bg-inset',
            ]"
            @click="toggle"
        >
            <span
                aria-hidden="true"
                class="pointer-events-none absolute rounded-full bg-white shadow-sm
                       transition-transform duration-(--dur-fast)"
                :class="[
                    size === 'sm' ? 'size-3.5' : 'size-4.5',
                    size === 'sm'
                        ? modelValue ? 'translate-x-4.5' : 'translate-x-0.5'
                        : modelValue ? 'translate-x-5.5' : 'translate-x-0.5',
                ]"
            />
        </button>

        <label v-if="label" :for="id" class="flex min-w-0 cursor-pointer flex-col gap-0.5 select-none" :class="disabled ? 'cursor-not-allowed' : ''">
            <span class="text-sm font-medium text-body">{{ label }}</span>
            <span v-if="description" :id="descId" class="text-xs text-muted">{{ description }}</span>
        </label>
    </span>
</template>
