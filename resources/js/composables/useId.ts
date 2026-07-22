let counter = 0;

/** Bileşen örneği başına kararlı, benzersiz DOM id üretir (aria bağlantıları için). */
export function useId(prefix = 'ui'): string {
    counter += 1;
    return `${prefix}-${counter}`;
}
