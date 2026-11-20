import { mkdir, writeFile } from 'node:fs/promises';
import { calculatePayroll } from '../src/services/payroll.js';
import { payrollExcel } from '../src/services/payroll-export.js';

// Synthetic data only: creates a reviewable workbook without database access.
const workers = calculatePayroll([
  { id: 'example', name: 'Example Worker', code: '001', schedule: {
    hourlyRate: 30.23, overtimeMultiplier: 1.5, occupation: 'Merchandiser',
    paymentMethod: 'EFT', startDate: '2026-08-03',
  } },
  { id: 'second', name: 'Second Example Worker', code: '002', schedule: { hourlyRate: 35, overtimeMultiplier: 1.5 } },
], Array.from({ length: 5 }, (_, index) => ({
  employeeId: 'example', date: `2026-09-${String(index + 7).padStart(2, '0')}`,
  inAt: `2026-09-${String(index + 7).padStart(2, '0')}T06:00:00Z`,
  outAt: `2026-09-${String(index + 7).padStart(2, '0')}T15:18:00Z`,
  status: 'closed', workedMinutes: 528, overtimeMinutes: 0, breakMinutes: 30,
})), [{ employeeId: 'example', holidayPay: 0, otherPay: 0, uif: 13.30, otherDeductions: 0 }]);
await mkdir('../artifacts', { recursive: true });
await writeFile('../artifacts/monthly-payroll-example.xlsx', await payrollExcel({
  organization: 'Example Company', timezone: 'Africa/Johannesburg',
  from: '2026-09-01', to: '2026-09-30', workers,
}));
console.log('Created artifacts/monthly-payroll-example.xlsx using synthetic workers.');
