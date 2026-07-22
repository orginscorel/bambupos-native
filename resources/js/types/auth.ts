/** Inertia paylaşılan `auth` prop'unun şekli (HandleInertiaRequests). */

export interface AuthUser {
    id: number;
    name: string;
    first_name: string | null;
    last_name: string | null;
    email: string;
    staff_code: string | null;
    position: string | null;
    theme: string | null;
    last_login_at: string | null;
    two_factor_enabled: boolean;
    has_pin: boolean;
    roles: string[];
}

export interface BranchOption {
    id: number;
    name: string;
    code: string | null;
}

export interface AuthProps {
    user: AuthUser;
    permissions: string[];
    tenant: { name: string; slug: string } | null;
    branches: BranchOption[];
    activeBranchId: number | null;
}

/** usePage().props içinden güvenli okuma. */
export function authFromPage(props: Record<string, unknown>): AuthProps | null {
    return (props.auth as AuthProps | null) ?? null;
}
