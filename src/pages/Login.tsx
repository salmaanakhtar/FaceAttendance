import { ArrowRight, Clock3, Loader2 } from 'lucide-react';
import { useState } from 'react';
import { Navigate } from 'react-router-dom';
import { DEFAULT_SERVER } from '../lib/api';
import { useAuth } from '../lib/auth';
import { Button, Card, Input } from '../components/ui';

export function Login() {
  const { authenticated, login } = useAuth();
  const [server, setServer] = useState(localStorage.getItem('yt_server_input') || DEFAULT_SERVER);
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);

  if (authenticated) return <Navigate to="/" replace />;

  async function submit(event: React.FormEvent) {
    event.preventDefault();
    setPending(true);
    setError(null);
    try {
      localStorage.setItem('yt_server_input', server.trim());
      await login(server.trim(), username.trim(), password);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Sign-in failed');
    } finally {
      setPending(false);
    }
  }

  return (
    <div className="flex min-h-screen items-center justify-center px-5 py-10">
      <Card className="w-full max-w-sm p-6 sm:p-8">
        <div className="flex items-center gap-2.5">
          <div className="relative grid h-10 w-10 place-items-center rounded-xl bg-primary text-white">
            <Clock3 className="h-5 w-5" />
            <span className="absolute -right-0.5 -top-0.5 h-2.5 w-2.5 rounded-full bg-accent ring-2 ring-white" />
          </div>
          <div>
            <p className="text-[17px] font-extrabold leading-none tracking-[-0.03em] text-ink">Yabil</p>
            <p className="mt-0.5 text-[9px] font-semibold uppercase tracking-[0.15em] text-muted">Timekeep admin</p>
          </div>
        </div>

        <h1 className="mt-7 text-[24px] font-extrabold tracking-[-0.04em] text-ink">Sign in</h1>

        <form className="mt-5 space-y-4" onSubmit={submit}>
          <Input
            label="Server"
            type="url"
            value={server}
            onChange={(event) => setServer(event.target.value)}
            required
          />
          <Input
            label="Username"
            autoComplete="username"
            value={username}
            onChange={(event) => setUsername(event.target.value)}
            required
          />
          <Input
            label="Password"
            type="password"
            autoComplete="current-password"
            value={password}
            onChange={(event) => setPassword(event.target.value)}
            required
          />
          {error ? (
            <p className="rounded-xl border border-danger/20 bg-danger-soft px-3 py-2 text-[11px] text-danger">
              {error}
            </p>
          ) : null}
          <Button type="submit" size="lg" className="w-full" disabled={pending}>
            {pending ? <Loader2 className="h-4 w-4 animate-spin" /> : null}
            Sign in
            {!pending ? <ArrowRight className="h-4 w-4" /> : null}
          </Button>
        </form>
      </Card>
    </div>
  );
}
