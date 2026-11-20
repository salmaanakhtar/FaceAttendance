import { X } from 'lucide-react';
import { useEffect, type ReactNode } from 'react';
import { cn } from '../lib/cn';

type Variant = 'primary' | 'secondary' | 'ghost' | 'danger';
type Size = 'sm' | 'md' | 'lg' | 'icon';

const variants: Record<Variant, string> = {
  primary: 'btn-primary',
  secondary: 'btn-secondary',
  ghost: 'btn-ghost',
  danger: 'btn-danger',
};

const sizes: Record<Size, string> = {
  sm: 'h-8 px-3 text-[12px]',
  md: 'h-10 px-4',
  lg: 'h-11 px-5',
  icon: 'h-9 w-9',
};

export function Button({
  variant = 'primary',
  size = 'md',
  className,
  type = 'button',
  ...props
}: React.ButtonHTMLAttributes<HTMLButtonElement> & { variant?: Variant; size?: Size }) {
  return (
    <button
      type={type}
      className={cn('btn', variants[variant], sizes[size], className)}
      {...props}
    />
  );
}

export function Field({
  label,
  error,
  hint,
  className,
  children,
}: {
  label?: string;
  error?: string;
  hint?: string;
  className?: string;
  children: ReactNode;
}) {
  return (
    <label className={cn('block space-y-1.5', className)}>
      {label ? <span className="label">{label}</span> : null}
      {children}
      {error ? <span className="block text-[11px] text-danger">{error}</span> : null}
      {!error && hint ? <span className="block text-[10px] text-muted">{hint}</span> : null}
    </label>
  );
}

export function Input({
  label,
  error,
  hint,
  className,
  ...props
}: React.InputHTMLAttributes<HTMLInputElement> & { label?: string; error?: string; hint?: string }) {
  return (
    <Field label={label} error={error} hint={hint}>
      <input className={cn('field', className)} {...props} />
    </Field>
  );
}

export function Select({
  label,
  error,
  hint,
  className,
  children,
  ...props
}: React.SelectHTMLAttributes<HTMLSelectElement> & {
  label?: string;
  error?: string;
  hint?: string;
}) {
  return (
    <Field label={label} error={error} hint={hint}>
      <select className={cn('field appearance-none pr-9', className)} {...props}>
        {children}
      </select>
    </Field>
  );
}

export function Textarea({
  label,
  error,
  hint,
  className,
  ...props
}: React.TextareaHTMLAttributes<HTMLTextAreaElement> & {
  label?: string;
  error?: string;
  hint?: string;
}) {
  return (
    <Field label={label} error={error} hint={hint}>
      <textarea className={cn('field min-h-20 resize-y', className)} {...props} />
    </Field>
  );
}

export function Card({ className, children }: { className?: string; children: ReactNode }) {
  return <section className={cn('card', className)}>{children}</section>;
}

export function Badge({
  children,
  tone = 'neutral',
}: {
  children: ReactNode;
  tone?: 'neutral' | 'blue' | 'green' | 'amber' | 'red' | 'violet';
}) {
  const tones = {
    neutral: 'bg-canvas text-muted border-line',
    blue: 'bg-primary-soft text-primary-dark border-primary/15',
    green: 'bg-emerald-50 text-emerald-700 border-emerald-200',
    amber: 'bg-amber-50 text-amber-700 border-amber-200',
    red: 'bg-red-50 text-red-700 border-red-200',
    violet: 'bg-violet-50 text-violet-700 border-violet-200',
  };
  return <span className={cn('chip', tones[tone])}>{children}</span>;
}

export function Modal({
  open,
  onClose,
  title,
  children,
  footer,
  wide = false,
}: {
  open: boolean;
  onClose: () => void;
  title: string;
  children: ReactNode;
  footer?: ReactNode;
  wide?: boolean;
}) {
  useEffect(() => {
    if (!open) return;
    const listener = (event: KeyboardEvent) => {
      if (event.key === 'Escape') onClose();
    };
    window.addEventListener('keydown', listener);
    return () => window.removeEventListener('keydown', listener);
  }, [open, onClose]);

  if (!open) return null;
  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4">
      <button
        type="button"
        className="absolute inset-0 bg-ink/40 backdrop-blur-[2px]"
        aria-label="Close dialog"
        onClick={onClose}
      />
      <div
        role="dialog"
        aria-modal="true"
        aria-label={title}
        className={cn(
          'relative flex max-h-[90vh] w-full flex-col overflow-hidden rounded-2xl border border-line bg-surface shadow-[0_30px_90px_rgba(11,18,32,0.25)]',
          wide ? 'max-w-3xl' : 'max-w-lg',
        )}
      >
        <div className="flex items-center justify-between border-b border-line px-5 py-4">
          <h2 className="text-[16px] font-bold text-ink">{title}</h2>
          <button
            type="button"
            onClick={onClose}
            className="grid h-8 w-8 place-items-center rounded-lg text-muted hover:bg-canvas hover:text-ink"
            aria-label="Close"
          >
            <X className="h-4 w-4" />
          </button>
        </div>
        <div className="min-h-0 flex-1 overflow-y-auto px-5 py-5">{children}</div>
        {footer ? (
          <div className="flex justify-end gap-2 border-t border-line bg-canvas/50 px-5 py-4">
            {footer}
          </div>
        ) : null}
      </div>
    </div>
  );
}

export function PageHeader({
  title,
  actions,
  subtitle,
}: {
  title: string;
  actions?: ReactNode;
  subtitle?: string;
}) {
  return (
    <div className="flex flex-col gap-3 pb-5 sm:flex-row sm:items-center sm:justify-between">
      <div>
        <h1 className="text-[26px] font-extrabold tracking-[-0.04em] text-ink">{title}</h1>
        {subtitle ? <p className="mt-1 text-[12px] text-muted">{subtitle}</p> : null}
      </div>
      {actions ? <div className="flex flex-wrap gap-2">{actions}</div> : null}
    </div>
  );
}

export function StatCard({
  label,
  value,
  tone = 'blue',
  icon,
}: {
  label: string;
  value: string | number;
  tone?: 'blue' | 'green' | 'amber' | 'red' | 'violet';
  icon?: ReactNode;
}) {
  const tones = {
    blue: 'bg-primary-soft text-primary',
    green: 'bg-emerald-50 text-emerald-700',
    amber: 'bg-amber-50 text-amber-700',
    red: 'bg-red-50 text-red-700',
    violet: 'bg-violet-50 text-violet-700',
  };
  return (
    <div className="card p-4">
      <div className="flex items-center justify-between gap-2">
        <p className="text-[11px] font-semibold text-muted">{label}</p>
        {icon ? <span className={cn('grid h-8 w-8 place-items-center rounded-xl', tones[tone])}>{icon}</span> : null}
      </div>
      <p className="mt-2 text-[26px] font-extrabold leading-none tracking-[-0.04em] text-ink">
        {String(value).padStart(2, '0')}
      </p>
    </div>
  );
}

export function Empty({ children }: { children: ReactNode }) {
  return <div className="py-12 text-center text-[12px] text-muted">{children}</div>;
}

export function Spinner() {
  return (
    <span className="inline-block h-4 w-4 animate-spin rounded-full border-2 border-primary/30 border-t-primary" />
  );
}

export function TableWrap({ children }: { children: ReactNode }) {
  return <div className="overflow-x-auto">{children}</div>;
}
