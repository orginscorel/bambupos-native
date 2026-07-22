import { inject, type InjectionKey, type Ref } from 'vue';

/** FormField → form kontrolü aria sözleşmesi (id, describedby, invalid). */
export interface FieldContext {
    id: string;
    describedBy: Ref<string | undefined>;
    invalid: Ref<boolean>;
    required: boolean;
}

export const FieldKey: InjectionKey<FieldContext> = Symbol('FormField');

export function useFieldContext(): FieldContext | null {
    return inject(FieldKey, null);
}
