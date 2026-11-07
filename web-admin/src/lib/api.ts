export const DEFAULT_SERVER = 'https://faceattendance-api.yabildistributors.com';
const SERVER_KEY = 'yt_server';
const ACCESS_KEY = 'yt_access';
const REFRESH_KEY = 'yt_refresh';
const ADMIN_KEY = 'yt_admin';
const ORG_KEY = 'yt_org';

export type Admin = { id: string; name: string; role: string; orgId: string };
export type Org = {
  id: string;
  name: string;
  timezone: string;
  settings: Record<string, unknown>;
};

export class ApiError extends Error {
  status: number;
  constructor(status: number, message: string) {
    super(message);
    this.status = status;
  }
}

function errorMessage(data: unknown, status: number): string {
  if (data && typeof data === 'object') {
    const error = (data as { error?: unknown }).error;
    if (error && typeof error === 'object' && 'message' in error) {
      return String((error as { message: unknown }).message);
    }
    if (typeof error === 'string') return error;
    if ('message' in data) return String((data as { message: unknown }).message);
  }
  return `Request failed (${status})`;
}

class ApiClient {
  server = sessionStorage.getItem(SERVER_KEY) || DEFAULT_SERVER;
  access: string | null = sessionStorage.getItem(ACCESS_KEY);
  refresh: string | null = sessionStorage.getItem(REFRESH_KEY);
  admin: Admin | null = JSON.parse(sessionStorage.getItem(ADMIN_KEY) || 'null');
  org: Org | null = JSON.parse(sessionStorage.getItem(ORG_KEY) || 'null');

  get signedIn() {
    return Boolean(this.access && this.refresh && this.admin);
  }

  async login(server: string, username: string, password: string): Promise<void> {
    this.server = server.replace(/\/+$/, '');
    const response = await fetch(`${this.server}/api/v1/admin/login`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ username, password }),
    });
    const data = await response.json().catch(() => null);
    if (!response.ok) throw new ApiError(response.status, errorMessage(data, response.status));
    this.access = data.accessToken;
    this.refresh = data.refreshToken;
    this.admin = data.admin;
    this.org = data.org ?? null;
    this.save();
  }

  async restore(): Promise<boolean> {
    if (!this.signedIn) return false;
    try {
      const me = await this.request<Admin & { org?: Org }>('/api/v1/admin/me');
      this.org = me.org ?? this.org;
      this.save();
      return true;
    } catch {
      this.clear();
      return false;
    }
  }

  async logout(): Promise<void> {
    try {
      if (this.refresh) {
        await fetch(`${this.server}/api/v1/admin/logout`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ refreshToken: this.refresh }),
        });
      }
    } catch {
      // ignore
    }
    this.clear();
  }

  private save() {
    if (this.access) sessionStorage.setItem(ACCESS_KEY, this.access);
    if (this.refresh) sessionStorage.setItem(REFRESH_KEY, this.refresh);
    if (this.admin) sessionStorage.setItem(ADMIN_KEY, JSON.stringify(this.admin));
    if (this.org) sessionStorage.setItem(ORG_KEY, JSON.stringify(this.org));
    sessionStorage.setItem(SERVER_KEY, this.server);
  }

  private clear() {
    this.access = null;
    this.refresh = null;
    this.admin = null;
    this.org = null;
    [ACCESS_KEY, REFRESH_KEY, ADMIN_KEY, ORG_KEY].forEach((key) => sessionStorage.removeItem(key));
  }

  private async refreshAccess(): Promise<boolean> {
    if (!this.refresh) return false;
    const response = await fetch(`${this.server}/api/v1/admin/refresh`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ refreshToken: this.refresh }),
    });
    if (!response.ok) return false;
    const data = await response.json();
    this.access = data.accessToken;
    sessionStorage.setItem(ACCESS_KEY, this.access!);
    return true;
  }

  async request<T>(path: string, options: { method?: string; body?: unknown; retry?: boolean } = {}): Promise<T> {
    const { method = 'GET', body, retry = true } = options;
    const response = await fetch(`${this.server}${path}`, {
      method,
      headers: {
        Authorization: `Bearer ${this.access}`,
        ...(body !== undefined ? { 'Content-Type': 'application/json' } : {}),
      },
      body: body !== undefined ? JSON.stringify(body) : undefined,
    });
    if (response.status === 401 && retry && (await this.refreshAccess())) {
      return this.request<T>(path, { method, body, retry: false });
    }
    if (!response.ok) {
      const data = await response.json().catch(() => null);
      throw new ApiError(response.status, errorMessage(data, response.status));
    }
    if (response.status === 204) return undefined as T;
    return (await response.json()) as T;
  }

  async download(path: string, body: unknown, filename: string): Promise<void> {
    const response = await fetch(`${this.server}${path}`, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${this.access}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(body),
    });
    if (!response.ok) {
      const data = await response.json().catch(() => null);
      throw new ApiError(response.status, errorMessage(data, response.status));
    }
    const blob = await response.blob();
    const url = URL.createObjectURL(blob);
    const anchor = document.createElement('a');
    anchor.href = url;
    anchor.download = filename;
    anchor.click();
    URL.revokeObjectURL(url);
  }

  async downloadGet(path: string, filename: string): Promise<void> {
    const response = await fetch(`${this.server}${path}`, {
      headers: { Authorization: `Bearer ${this.access}` },
    });
    if (!response.ok) {
      const data = await response.json().catch(() => null);
      throw new ApiError(response.status, errorMessage(data, response.status));
    }
    const blob = await response.blob();
    const url = URL.createObjectURL(blob);
    const anchor = document.createElement('a');
    anchor.href = url;
    anchor.download = filename;
    anchor.click();
    URL.revokeObjectURL(url);
  }
}

export const api = new ApiClient();
