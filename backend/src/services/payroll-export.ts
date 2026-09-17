import ExcelJS from 'exceljs';
import type { PayrollReport } from './payroll.js';

const navy = 'FF17324D';
const pale = 'FFEAF1F7';
const currency = '"R" #,##0.00;[Red]("R" #,##0.00)';

export async function payrollExcel(report: PayrollReport): Promise<Buffer> {
  const book = new ExcelJS.Workbook();
  book.creator = 'FaceAttendance';
  const sheet = book.addWorksheet('Monthly payroll', {
    views: [{ state: 'frozen', ySplit: 5 }],
    pageSetup: { paperSize: 9, orientation: 'landscape', fitToPage: true, fitToWidth: 1, fitToHeight: 0 },
  });
  sheet.columns = [{ width: 14 }, { width: 30 }, ...Array.from({ length: 6 }, () => ({ width: 17 }))];
  const band = (row: number, text: string) => {
    sheet.mergeCells(row, 1, row, 8);
    const cell = sheet.getCell(row, 1);
    cell.value = text;
    cell.fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: navy } };
    cell.font = { name: 'Calibri', size: 14, bold: true, color: { argb: 'FFFFFFFF' } };
    sheet.getRow(row).height = 30;
  };
  band(1, `${report.organization} | Monthly hours and payslips`);
  sheet.mergeCells('A2:H2');
  sheet.getCell('A2').value = `Period: ${report.from} to ${report.to} | Timezone: ${report.timezone}`;
  sheet.mergeCells('A3:H3');
  sheet.getCell('A3').value = 'Closed shifts only. Review unresolved shifts and entered pay adjustments before payment.';
  sheet.getRow(3).height = 28;
  sheet.getCell('A3').alignment = { wrapText: true };
  sheet.getRow(5).values = ['Code', 'Worker', 'Normal hours', 'Overtime hours', 'Total hours', 'Gross pay', 'Net pay', 'Unresolved shifts'];
  let row = 6;
  for (const worker of report.workers) {
    sheet.getRow(row).values = [worker.code, worker.name, worker.regularMinutes / 60,
      worker.overtimeMinutes / 60, worker.workedMinutes / 60, worker.gross, worker.net, worker.unresolvedShifts];
    for (let col = 3; col <= 5; col++) sheet.getCell(row, col).numFmt = '0.00';
    for (const col of [6, 7]) sheet.getCell(row, col).numFmt = currency;
    row++;
  }
  const totalRow = row;
  sheet.getCell(row, 2).value = 'TOTAL';
  for (let col = 3; col <= 8; col++) {
    const letter = sheet.getColumn(col).letter;
    sheet.getCell(row, col).value = report.workers.length ? { formula: `SUM(${letter}6:${letter}${row - 1})` } : 0;
    sheet.getCell(row, col).numFmt = col === 6 || col === 7 ? currency : col === 8 ? '0' : '0.00';
  }
  if (report.workers.some(w => w.gross === null)) {
    sheet.getCell(row, 6).value = 'Rates missing';
    sheet.getCell(row, 7).value = 'Rates missing';
  }
  sheet.autoFilter = { from: 'A5', to: `H${Math.max(5, row - 1)}` };
  row += 3;
  for (const worker of report.workers) {
    sheet.getRow(row - 1).addPageBreak();
    band(row++, `PAYSLIP | ${worker.name}`);
    const info = [
      ['Employee code', worker.code, 'Pay period', `${report.from} to ${report.to}`],
      ['Full name', worker.name, 'Identity number', String(worker.schedule.identityNumber ?? '')],
      ['Occupation', String(worker.schedule.occupation ?? worker.schedule.department ?? ''), 'Date engaged', String(worker.schedule.startDate ?? '')],
      ['Payment method', String(worker.schedule.paymentMethod ?? ''), 'Hourly rate', worker.rate ?? 'Not configured'],
    ];
    for (const fields of info) {
      sheet.getCell(row, 1).value = fields[0];
      sheet.mergeCells(row, 2, row, 4);
      sheet.getCell(row, 2).value = fields[1];
      sheet.getCell(row, 5).value = fields[2];
      sheet.mergeCells(row, 6, row, 8);
      sheet.getCell(row, 6).value = fields[3];
      sheet.getRow(row).height = 28;
      row++;
    }
    row++;
    const heading = row;
    sheet.getRow(row++).values = ['Earnings', '', 'Hours', 'Amount', 'Deductions', '', '', 'Amount'];
    const lines = [
      ['Normal hours worked', worker.regularMinutes / 60, worker.regularPay, 'UIF', worker.uif],
      [`Overtime (${worker.multiplier ?? 'rate missing'}x)`, worker.overtimeMinutes / 60, worker.overtimePay, 'Other deductions', worker.otherDeductions],
      ['Holiday pay', null, worker.holidayPay, '', null],
      ['Other earnings', null, worker.otherPay, '', null],
    ] as const;
    for (const line of lines) {
      sheet.mergeCells(row, 1, row, 2);
      sheet.getCell(row, 1).value = line[0];
      sheet.getCell(row, 3).value = line[1];
      sheet.getCell(row, 3).numFmt = '0.00';
      sheet.getCell(row, 4).value = line[2];
      sheet.getCell(row, 4).numFmt = currency;
      sheet.mergeCells(row, 5, row, 7);
      sheet.getCell(row, 5).value = line[3];
      sheet.getCell(row, 8).value = line[4];
      sheet.getCell(row, 8).numFmt = currency;
      sheet.getRow(row).height = 26;
      row++;
    }
    row += 2;
    sheet.mergeCells(row, 1, row, 3);
    sheet.getCell(row, 1).value = 'Gross earnings';
    sheet.getCell(row, 4).value = worker.gross;
    sheet.getCell(row, 4).numFmt = currency;
    sheet.mergeCells(row, 5, row, 7);
    sheet.getCell(row, 5).value = 'Total deductions';
    sheet.getCell(row, 8).value = worker.deductions;
    sheet.getCell(row++, 8).numFmt = currency;
    sheet.mergeCells(row, 5, row, 7);
    sheet.getCell(row, 5).value = 'NET SALARY';
    sheet.getCell(row, 8).value = worker.net;
    sheet.getCell(row, 8).numFmt = currency;
    sheet.getRow(row++).font = { bold: true, size: 13 };
    sheet.mergeCells(row, 1, row, 8);
    sheet.getCell(row++, 1).value = worker.gross === null ? 'DRAFT: pay rates are missing.'
      : worker.unresolvedShifts > 0 ? `DRAFT: ${worker.unresolvedShifts} unresolved shift(s) excluded.`
      : 'Pay adjustments entered by administrator for this period.';
    sheet.mergeCells(row, 1, row, 8);
    sheet.getCell(row++, 1).value = 'Received by / signature: __________________________________    Date: __________________';
    sheet.getRow(heading).fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: pale } };
    sheet.getRow(heading).font = { bold: true };
    row += 3;
  }
  for (const r of [5, totalRow]) {
    sheet.getRow(r).font = { bold: true };
    sheet.getRow(r).fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: pale } };
    sheet.getRow(r).height = 30;
  }
  sheet.eachRow(r => r.eachCell(cell => {
    cell.alignment = { ...cell.alignment, vertical: 'middle', wrapText: true };
  }));
  sheet.pageSetup.printArea = `A1:H${row}`;

  const detail = book.addWorksheet('All times', { views: [{ state: 'frozen', ySplit: 1 }] });
  detail.columns = ['Worker code', 'Worker', 'Work date', 'Clock in', 'Clock out', 'Break minutes', 'Normal hours', 'Overtime hours', 'Total hours', 'Status'].map(header => ({ header, width: header === 'Worker' ? 30 : 22 }));
  const timestamp = (value: string | null) => value ? new Intl.DateTimeFormat('en-GB', {
    timeZone: report.timezone, dateStyle: 'short', timeStyle: 'short', hour12: false,
  }).format(new Date(value)) : '';
  for (const w of report.workers) for (const s of w.shifts) {
    const closed = s.status === 'closed' && s.inAt && s.outAt;
    detail.addRow([w.code, w.name, s.date, timestamp(s.inAt), timestamp(s.outAt), s.breakMinutes,
      closed ? Math.max(0, s.workedMinutes - s.overtimeMinutes) / 60 : null,
      closed ? Math.max(0, Math.min(s.workedMinutes, s.overtimeMinutes)) / 60 : null,
      closed ? s.workedMinutes / 60 : null, s.status]);
  }
  for (const col of [7, 8, 9]) detail.getColumn(col).numFmt = '0.00';
  detail.getRow(1).font = { bold: true };
  detail.autoFilter = 'A1:J1';
  return Buffer.from(await book.xlsx.writeBuffer());
}
