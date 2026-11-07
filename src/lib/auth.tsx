import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from 'react';
import { api, type Admin, type Org } from './api';

type AuthContextValue = {
  ready: boolean;
  authenticated: boolean;
  admin: Admin | null;
  org: Org | null;
  login: (server: string, username: string, password: string) => Promise<void>;
  logout: () => Promise<void>;
  reload: () => Promise<void>;
};

const AuthContext = createContext<AuthContextValue | null>(null);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [ready, setReady] = useState(false);
  const [authenticated, setAuthenticated] = useState(false);
  const [admin, setAdmin] = useState<Admin | null>(api.admin);
  const [org, setOrg] = useState<Org | null>(api.org);

  useEffect(() => {
    let cancelled = false;
    void api.restore().then((ok) => {
      if (cancelled) return;
      setAuthenticated(ok);
      setAdmin(api.admin);
      setOrg(api.org);
      setReady(true);
    });
    return () => {
      cancelled = true;
    };
  }, []);

  const login = useCallback(async (server: string, username: string, password: string) => {
    await api.login(server, username, password);
    setAuthenticated(true);
    setAdmin(api.admin);
    setOrg(api.org);
  }, []);

  const logout = useCallback(async () => {
    await api.logout();
    setAuthenticated(false);
    setAdmin(null);
    setOrg(null);
  }, []);

  const reload = useCallback(async () => {
    const ok = await api.restore();
    setAuthenticated(ok);
    setAdmin(api.admin);
    setOrg(api.org);
  }, []);

  const value = useMemo(
    () => ({ ready, authenticated, admin, org, login, logout, reload }),
    [ready, authenticated, admin, org, login, logout, reload],
  );

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth(): AuthContextValue {
  const context = useContext(AuthContext);
  if (!context) throw new Error('useAuth must be used inside AuthProvider');
  return context;
}
