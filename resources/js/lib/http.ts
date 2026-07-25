/**
 * Oturum-çerezli JSON istemcisi (/api/v1 uçları için).
 * CSRF: Laravel'in XSRF-TOKEN çerezi X-XSRF-TOKEN başlığına taşınır.
 * Hatalar ApiError olarak fırlar: status + message + alan hataları.
 */

export interface FieldErrors {
    [field: string]: string[];
}

export class ApiError extends Error {
    constructor(
        public readonly status: number,
        message: string,
        public readonly errors: FieldErrors = {},
        /** Ham yanıt gövdesi (ör. rezervasyon çakışma onayı: requires_confirmation). */
        public readonly data: Record<string, unknown> = {},
    ) {
        super(message);
    }

    /** Bir alanın ilk hata mesajı (yoksa boş dize). */
    first(field: string): string {
        return this.errors[field]?.[0] ?? '';
    }

    /** Alanlardan bağımsız, kullanıcıya gösterilebilir tek mesaj. */
    get displayMessage(): string {
        const firstField = Object.values(this.errors)[0]?.[0];
        return firstField || this.message || 'Beklenmeyen bir hata oluştu.';
    }
}

function xsrfToken(): string {
    const match = document.cookie.match(/(?:^|;\s*)XSRF-TOKEN=([^;]+)/);
    return match ? decodeURIComponent(match[1]) : '';
}

export async function api<T = unknown>(
    path: string,
    options: { method?: string; body?: unknown } = {},
): Promise<T> {
    const method = options.method ?? 'GET';

    let response: Response;
    try {
        response = await fetch(path, {
            method,
            credentials: 'same-origin',
            headers: {
                Accept: 'application/json',
                'X-Requested-With': 'XMLHttpRequest',
                ...(method !== 'GET' ? { 'Content-Type': 'application/json', 'X-XSRF-TOKEN': xsrfToken() } : {}),
            },
            body: options.body !== undefined ? JSON.stringify(options.body) : undefined,
        });
    } catch {
        throw new ApiError(0, 'Sunucuya ulaşılamadı. Bağlantınızı kontrol edin.');
    }

    if (response.status === 204) {
        return undefined as T;
    }

    let payload: Record<string, unknown> = {};
    try {
        payload = (await response.json()) as Record<string, unknown>;
    } catch {
        /* gövdesiz yanıt */
    }

    if (!response.ok) {
        if (response.status === 401) {
            throw new ApiError(401, 'Oturumunuz sona erdi. Lütfen yeniden giriş yapın.');
        }
        if (response.status === 419) {
            throw new ApiError(419, 'Oturum doğrulaması süresi doldu. Sayfayı yenileyip tekrar deneyin.');
        }

        throw new ApiError(
            response.status,
            typeof payload.message === 'string' ? payload.message : 'İşlem tamamlanamadı.',
            (payload.errors as FieldErrors | undefined) ?? {},
            payload,
        );
    }

    return payload as T;
}
