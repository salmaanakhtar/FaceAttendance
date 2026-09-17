import { describe, expect, it } from 'vitest';
import ExcelJS from 'exceljs';
import { calculatePayroll, type PayrollSession } from './payroll.js';
import { payrollExcel } from './payroll-export.js';

const worker = { id: 'w1', code: '001', name: 'Example Worker',
  schedule: { hourlyRate: 30.23, overtimeMultiplier: 1.5 } };
const session: PayrollSession = { employeeId: 'w1', date: '2026-09-01',
  inAt: '2026-09-01T06:00:00Z', outAt: '2026-09-01T15:00:00Z',
  status: 'closed', workedMinutes: 480, overtimeMinutes: 60, breakMinutes: 60 };

describe('monthly payroll', () => {
  it('matches the supplied 44-hour example with a manually entered UIF deduction', () => {
    const [row] = calculatePayroll([worker], [{ ...session, workedMinutes: 2640, overtimeMinutes: 0 }],
      [{ employeeId: 'w1', holidayPay: 0, otherPay: 0, uif: 13.30, otherDeductions: 0 }]);
    expect(row?.gross).toBe(1330.12);
    expect(row?.net).toBe(1316.82);
  });

  it('splits overtime from normal hours and excludes unfinished shifts', () => {
    const [row] = calculatePayroll([worker], [session, { ...session, status: 'open', outAt: null }]);
    expect(row?.regularMinutes).toBe(420);
    expect(row?.overtimeMinutes).toBe(60);
    expect(row?.gross).toBe(256.96);
    expect(row?.unresolvedShifts).toBe(1);
  });

  it('does not invent pay rates and includes workers with no shifts', () => {
    const rows = calculatePayroll([{ ...worker, schedule: {} }, { ...worker, id: 'w2' }], [session]);
    expect(rows[0]?.gross).toBeNull();
    expect(rows[1]?.workedMinutes).toBe(0);
    expect(rows[1]?.gross).toBe(0);
  });

  it('generates numeric Excel hours, payslips below summary and local detailed times', async () => {
    const workers = calculatePayroll([{ ...worker, name: '=Example Worker' }], [session]);
    const bytes = await payrollExcel({ organization: 'Example Company', timezone: 'Africa/Johannesburg',
      from: '2026-09-01', to: '2026-09-30', workers });
    const book = new ExcelJS.Workbook();
    await book.xlsx.load(bytes as unknown as ExcelJS.Buffer);
    expect(book.worksheets.map(s => s.name)).toEqual(['Monthly payroll', 'All times']);
    const sheet = book.getWorksheet('Monthly payroll')!;
    expect(sheet.getCell('B6').value).toBe('=Example Worker');
    expect(sheet.getCell('E6').value).toBe(8);
    expect(sheet.getCell('A10').value).toBe('PAYSLIP | =Example Worker');
    expect(book.getWorksheet('All times')!.getCell('D2').value).toContain('08:00');
  });

  it('exports a valid empty report without invalid sum ranges', async () => {
    const bytes = await payrollExcel({ organization: 'Empty', timezone: 'UTC',
      from: '2026-09-01', to: '2026-09-30', workers: [] });
    expect(bytes.subarray(0, 2).toString()).toBe('PK');
  });
});
