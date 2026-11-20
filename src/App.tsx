import { Navigate, Outlet, Route, Routes } from 'react-router-dom';
import { AppShell } from './components/AppShell';
import { AuthProvider, useAuth } from './lib/auth';
import { Attendance } from './pages/Attendance';
import { Audit } from './pages/Audit';
import { Dashboard } from './pages/Dashboard';
import { LeavePage } from './pages/Leave';
import { Login } from './pages/Login';
import { Overtime } from './pages/Overtime';
import { Payroll } from './pages/Payroll';
import { Workers } from './pages/Workers';

function RequireAuth() {
  const { ready, authenticated } = useAuth();
  if (!ready) {
    return (
      <div className="flex min-h-screen items-center justify-center">
        <span className="h-6 w-6 animate-spin rounded-full border-2 border-primary/30 border-t-primary" />
      </div>
    );
  }
  if (!authenticated) return <Navigate to="/login" replace />;
  return <Outlet />;
}

export default function App() {
  return (
    <AuthProvider>
      <Routes>
        <Route path="/login" element={<Login />} />
        <Route element={<RequireAuth />}>
          <Route element={<AppShell><Outlet /></AppShell>}>
            <Route index element={<Dashboard />} />
            <Route path="workers" element={<Workers />} />
            <Route path="attendance" element={<Attendance />} />
            <Route path="leave" element={<LeavePage />} />
            <Route path="payroll" element={<Payroll />} />
            <Route path="overtime" element={<Overtime />} />
            <Route path="audit" element={<Audit />} />
          </Route>
        </Route>
        <Route path="*" element={<Navigate to="/" replace />} />
      </Routes>
    </AuthProvider>
  );
}
