import { describe, expect, it } from 'vitest';
import ExcelJS from 'exceljs';
import { calculatePayroll, type PayrollSession } from './payroll.js';
import { payrollExcel } from './payroll-export.js';

const worker = { id: 'w1', code: '001', name: 'Example Worker',
  schedule: { hourlyRate: 30.23, overtimeMultiplier: 1.5, identityNumber: '0012345678901', firstName: 'Example', surname: 'Worker' } };
const session: PayrollSession = { employeeId: 'w1', date: '2026-09-01',
  inAt: '2026-09-01T06:00:00Z', outAt: '2026-09-01T15:00:00Z',
  status: 'closed', workedMinutes: 480, overtimeMinutes: 60, breakMinutes: 60 };

describe('monthly payroll', () => {
  it('calculates UIF as one percent of gross wages', () => {
    const [row] = calculatePayroll([worker], [{ ...session, workedMinutes: 2640, overtimeMinutes: 0 }],
      [{ employeeId: 'w1', holidayPay: 0, otherPay: 0, uif: 13.30, otherDeductions: 0 }]);
    expect(row?.gross).toBe(1330.12);
    expect(row?.net).toBe(1316.82);
  });

  it('counts all worked hours as normal hours and excludes unfinished shifts', () => {
    const [row] = calculatePayroll([worker], [session, { ...session, status: 'open', outAt: null }]);
    expect(row?.regularMinutes).toBe(480);
    expect(row?.overtimeMinutes).toBe(0);
    expect(row?.gross).toBe(241.84);
    expect(row?.unresolvedShifts).toBe(1);
  });

  it('defaults missing rates to 30.23 and includes workers with no shifts', () => {
    const rows = calculatePayroll([{ ...worker, schedule: {} }, { ...worker, id: 'w2' }], [session]);
    expect(rows[0]?.rate).toBe(30.23);
    expect(rows[0]?.gross).toBe(241.84);
    expect(rows[0]?.uif).toBe(2.42);
    expect(rows[1]?.workedMinutes).toBe(0);
    expect(rows[1]?.gross).toBe(0);
  });

  it('matches 43 hours at 30.23 and ignores manual UIF from older clients', () => {
    const [row] = calculatePayroll([worker], [{ ...session, workedMinutes: 2580, overtimeMinutes: 120 }],
      [{ employeeId: 'w1', holidayPay: 0, otherPay: 0, uif: 15, otherDeductions: 0 }]);
    expect(row?.gross).toBe(1299.89);
    expect(row?.uif).toBe(13);
    expect(row?.net).toBe(1286.89);
  });

  it('uses custom rates and calculates UIF on gross including extra earnings', () => {
    const [row] = calculatePayroll([{ ...worker, schedule: { hourlyRate: 40 } }], [session],
      [{ employeeId: 'w1', holidayPay: 50, otherPay: 30, otherDeductions: 10 }]);
    expect(row?.gross).toBe(400);
    expect(row?.uif).toBe(4);
    expect(row?.net).toBe(386);
  });

  it('generates numeric Excel hours, duplicate payslips and local detailed times', async () => {
    const workers = calculatePayroll([{ ...worker, name: '=Example Worker' }], [session]);
    const bytes = await payrollExcel({ organization: 'Example Company', timezone: 'Africa/Johannesburg',
      from: '2026-09-01', to: '2026-09-30', workers });
    const book = new ExcelJS.Workbook();
    await book.xlsx.load(bytes as unknown as ExcelJS.Buffer);
    expect(book.worksheets.map(s => s.name)).toEqual(['Monthly payroll', 'Payslips', 'All times']);
    const sheet = book.getWorksheet('Monthly payroll')!;
    expect(sheet.getCell('B6').value).toBe('=Example Worker');
    expect(sheet.getCell('E6').value).toBe(8);
    expect(sheet.getCell('C6').value).toBe(8);
    expect(sheet.getCell('D6').value).toBeNull();
    const slips = book.getWorksheet('Payslips')!;
    expect(slips.getCell('A5').value).toBe('PAYSLIP');
    expect(slips.getCell('G5').value).toBe('PAYSLIP');
    expect(slips.getCell('B19').value).toBe(8);
    expect(slips.getCell('H19').value).toBe(8);
    expect(slips.getCell('B20').value).toBeNull();
    expect(slips.getCell('C20').value).toBeNull();
    expect(slips.getCell('H20').value).toBeNull();
    expect(slips.getCell('I20').value).toBeNull();
    expect(slips.getCell('C19').value).toBe(241.84);
    expect(slips.getCell('C11').value).toBe('0012345678901');
    expect(slips.getCell('I11').value).toBe('0012345678901');
    expect(slips.getCell('C9').value).toBe('Example');
    expect(slips.getCell('C10').value).toBe('Worker');
    expect(slips.getCell('E19').value).toBe(2.42);
    expect(slips.getCell('E35').value).toBe(239.42);
    expect(slips.pageSetup.orientation).toBe('landscape');
    expect(book.getWorksheet('All times')!.getCell('D2').value).toContain('08:00');
  });

  it('exports a valid empty report without invalid sum ranges', async () => {
    const bytes = await payrollExcel({ organization: 'Empty', timezone: 'UTC',
      from: '2026-09-01', to: '2026-09-30', workers: [] });
    expect(bytes.subarray(0, 2).toString()).toBe('PK');
  });
});
