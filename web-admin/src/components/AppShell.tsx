import {
  Activity,
  CalendarDays,
  ClipboardList,
  Clock3,
  LayoutDashboard,
  LogOut,
  Menu,
  Users,
  Wallet,
  X,
} from 'lucide-react';
import { useState, type ReactNode } from 'react';
import { NavLink, useNavigate } from 'react-router-dom';
import { useAuth } from '../lib/auth';
import { cn } from '../lib/cn';
import { Button } from './ui';

const nav = [
  { to: '/', label: 'Overview', icon: LayoutDashboard, end: true },
  { to: '/workers', label: 'Workers', icon: Users },
  { to: '/attendance', label: 'Attendance', icon: Clock3 },
  { to: '/leave', label: 'Leave', icon: CalendarDays },
  { to: '/payroll', label: 'Payroll', icon: Wallet },
  { to: '/overtime', label: 'Overtime', icon: Activity },
  { to: '/audit', label: 'Audit', icon: ClipboardList },
];

export function AppShell({ children }: { children: ReactNode }) {
  const { admin, org, logout } = useAuth();
  const navigate = useNavigate();
  const [menuOpen, setMenuOpen] = useState(false);

  async function signOut() {
    await logout();
    navigate('/login', { replace: true });
  }

  return (
    <div className="min-h-screen">
      <aside className="fixed inset-y-0 left-0 z-30 hidden w-60 flex-col border-r border-line bg-surface px-3 py-5 lg:flex">
        <Brand />
        <nav className="mt-7 space-y-1">
          {nav.map((item) => (
            <NavLink
              key={item.to}
              to={item.to}
              end={item.end}
              className={({ isActive }) =>
                cn(
                  'flex items-center gap-2.5 rounded-xl px-3 py-2.5 text-[12px] font-semibold transition-colors',
                  isActive ? 'bg-primary-soft/70 text-primary-dark' : 'text-muted hover:bg-canvas hover:text-ink',
                )
              }
            >
              <item.icon className="h-4 w-4" />
              {item.label}
            </NavLink>
          ))}
        </nav>
        <div className="mt-auto border-t border-line pt-3">
          <p className="truncate px-2 text-[11px] font-semibold text-ink">{admin?.name ?? 'Administrator'}</p>
          <p className="px-2 text-[10px] text-muted">{org?.name ?? 'Organization'}</p>
          <Button variant="ghost" size="sm" className="mt-2 w-full justify-start" onClick={() => void signOut()}>
            <LogOut className="h-3.5 w-3.5" />
            Sign out
          </Button>
        </div>
      </aside>

      <header className="sticky top-0 z-20 flex h-14 items-center justify-between border-b border-line bg-surface/90 px-4 backdrop-blur lg:hidden">
        <Brand compact />
        <Button variant="ghost" size="icon" onClick={() => setMenuOpen(true)} aria-label="Open menu">
          <Menu className="h-5 w-5" />
        </Button>
      </header>

      {menuOpen ? (
        <div className="fixed inset-0 z-40 lg:hidden">
          <button
            type="button"
            className="absolute inset-0 bg-ink/40"
            aria-label="Close menu"
            onClick={() => setMenuOpen(false)}
          />
          <div className="relative h-full w-72 max-w-[85vw] bg-surface p-4 shadow-xl">
            <div className="flex items-center justify-between">
              <Brand compact />
              <Button variant="ghost" size="icon" onClick={() => setMenuOpen(false)} aria-label="Close">
                <X className="h-4 w-4" />
              </Button>
            </div>
            <nav className="mt-5 space-y-1" onClick={() => setMenuOpen(false)}>
              {nav.map((item) => (
                <NavLink
                  key={item.to}
                  to={item.to}
                  end={item.end}
                  className={({ isActive }) =>
                    cn(
                      'flex items-center gap-2.5 rounded-xl px-3 py-2.5 text-[13px] font-semibold',
                      isActive ? 'bg-primary-soft/70 text-primary-dark' : 'text-muted',
                    )
                  }
                >
                  <item.icon className="h-4 w-4" />
                  {item.label}
                </NavLink>
              ))}
            </nav>
            <Button variant="secondary" className="mt-5 w-full" onClick={() => void signOut()}>
              <LogOut className="h-4 w-4" />
              Sign out
            </Button>
          </div>
        </div>
      ) : null}

      <main className="lg:pl-60">
        <div className="mx-auto w-full max-w-[1500px] px-4 py-6 sm:px-6 lg:px-8">{children}</div>
      </main>
    </div>
  );
}

function Brand({ compact = false }: { compact?: boolean }) {
  return (
    <div className="flex items-center gap-2.5 px-1">
      <div className="relative grid h-9 w-9 place-items-center rounded-xl bg-primary text-white shadow-sm">
        <Clock3 className="h-[18px] w-[18px]" />
        <span className="absolute -right-0.5 -top-0.5 h-2.5 w-2.5 rounded-full bg-accent ring-2 ring-white" />
      </div>
      {!compact ? (
        <div>
          <p className="text-[16px] font-extrabold leading-none tracking-[-0.03em] text-ink">Yabil</p>
          <p className="mt-0.5 text-[9px] font-semibold uppercase tracking-[0.14em] text-muted">Timekeep</p>
        </div>
      ) : (
        <p className="text-[15px] font-extrabold tracking-[-0.03em] text-ink">Yabil Timekeep</p>
      )}
    </div>
  );
}
