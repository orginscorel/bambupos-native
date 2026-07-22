/** Personel-Yetki ekran tipleri (/panel/personel). */

export interface StaffRoleRef {
    id: number;
    name: string;
    is_system?: boolean;
}

export interface StaffRow {
    id: number;
    name: string;
    first_name: string | null;
    last_name: string | null;
    email: string;
    phone: string | null;
    staff_code: string | null;
    department: string | null;
    position: string | null;
    hired_at: string | null;
    is_active: boolean;
    default_screen: string | null;
    last_login_at: string | null;
    has_pin?: boolean;
    personal_overrides_count?: number;
    branch?: { id: number; name: string } | null;
    branch_id?: number | null;
    roles: StaffRoleRef[];
}

export interface Paginated<T> {
    data: T[];
    current_page: number;
    last_page: number;
    total: number;
}

export interface PermissionCell {
    id: number | null;
    key: string;
    action: string;
    label: string;
    dangerous: boolean;
    warning: string | null;
}

export interface CatalogModule {
    module: string;
    label: string;
    permissions: PermissionCell[];
}

export interface RoleSummary {
    id: number;
    name: string;
    description: string | null;
    is_system: boolean;
    users_count: number;
    permission_keys: string[];
}

export interface RoleTemplate {
    key: string;
    name: string;
    description: string;
    permissions: string[];
}

export interface ScreenOption {
    key: string;
    label: string;
    permission: string | null;
}

export interface StaffMeta {
    catalog: CatalogModule[];
    roles: RoleSummary[];
    templates: RoleTemplate[];
    branches: { id: number; name: string; code: string | null }[];
    screens: ScreenOption[];
    actor: {
        id: number;
        permissions: string[];
        can_manage_staff: boolean;
        can_manage_roles: boolean;
    };
}

export interface OverrideSets {
    grant: string[];
    revoke: string[];
}
