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
      null, worker.workedMinutes / 60, worker.gross, worker.net, worker.unresolvedShifts];
    for (let col = 3; col <= 5; col++) sheet.getCell(row, col).numFmt = '0.00';
    for (const col of [6, 7]) sheet.getCell(row, col).numFmt = currency;
    row++;
  }
  const totalRow = row;
  sheet.getCell(row, 2).value = 'TOTAL';
  for (let col = 3; col <= 8; col++) {
    if (col === 4) continue; // Overtime is intentionally blank, including totals.
    const letter = sheet.getColumn(col).letter;
    sheet.getCell(row, col).value = report.workers.length ? { formula: `SUM(${letter}6:${letter}${row - 1})` } : 0;
    sheet.getCell(row, col).numFmt = col === 6 || col === 7 ? currency : col === 8 ? '0' : '0.00';
  }
  if (report.workers.some(w => w.gross === null)) {
    sheet.getCell(row, 6).value = 'Rates missing';
    sheet.getCell(row, 7).value = 'Rates missing';
  }
  sheet.autoFilter = { from: 'A5', to: `H${Math.max(5, row - 1)}` };
  for (const r of [5, totalRow]) {
    sheet.getRow(r).font = { bold: true };
    sheet.getRow(r).fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: pale } };
    sheet.getRow(r).height = 30;
  }
  sheet.eachRow(r => r.eachCell(cell => {
    cell.alignment = { ...cell.alignment, vertical: 'middle', wrapText: true };
  }));
  sheet.pageSetup.printArea = `A1:H${row}`;

  addPayslips(book, report);

  const detail = book.addWorksheet('All times', { views: [{ state: 'frozen', ySplit: 1 }] });
  detail.columns = ['Worker code', 'Worker', 'Work date', 'Clock in', 'Clock out', 'Break minutes', 'Normal hours', 'Overtime hours', 'Total hours', 'Status'].map(header => ({ header, width: header === 'Worker' ? 30 : 22 }));
  const timestamp = (value: string | null) => value ? new Intl.DateTimeFormat('en-GB', {
    timeZone: report.timezone, dateStyle: 'short', timeStyle: 'short', hour12: false,
  }).format(new Date(value)) : '';
  for (const w of report.workers) for (const s of w.shifts) {
    const closed = s.status === 'closed' && s.inAt && s.outAt;
    detail.addRow([w.code, w.name, s.date, timestamp(s.inAt), timestamp(s.outAt), s.breakMinutes,
      closed ? Math.max(0, s.workedMinutes) / 60 : null,
      null,
      closed ? s.workedMinutes / 60 : null, s.status]);
  }
  for (const col of [7, 8, 9]) detail.getColumn(col).numFmt = '0.00';
  detail.getRow(1).font = { bold: true };
  detail.autoFilter = 'A1:J1';
  return Buffer.from(await book.xlsx.writeBuffer());
}


/** Two matching copies per worker on a landscape A4 page. */
function addPayslips(book: ExcelJS.Workbook, report: PayrollReport): void {
  const sheet = book.addWorksheet('Payslips', {
    pageSetup: {
      paperSize: 9, orientation: 'landscape', fitToPage: true,
      fitToWidth: 1, fitToHeight: 0,
      margins: { left: 0.25, right: 0.25, top: 0.25, bottom: 0.25, header: 0, footer: 0 },
    },
  });
  // Label, hours, earnings amount, deduction label, deduction amount, gutter.
  sheet.columns = [26, 9, 15, 23, 15, 3, 26, 9, 15, 23, 15].map(width => ({ width }));
  const date = (value: string) => /^\d{4}-\d{2}-\d{2}$/.test(value)
    ? `${value.slice(8, 10)}/${value.slice(5, 7)}/${value.slice(0, 4)}` : value;
  const border: ExcelJS.Border = { style: 'thin', color: { argb: 'FF000000' } };
  for (const [index, worker] of report.workers.entries()) {
    const top = index * 38 + 1;
    for (let r = top; r < top + 38; r++) sheet.getRow(r).height = 15;
    for (const offset of [0, 6]) {
      const cell = (r: number, c: number) => sheet.getCell(top + r, offset + c);
      const merge = (r: number, from: number, to: number, value: ExcelJS.CellValue) => {
        sheet.mergeCells(top + r, offset + from, top + r, offset + to);
        cell(r, from).value = value;
      };
      merge(0, 1, 5, report.organization.toUpperCase());
      cell(0, 1).font = { name: 'Arial', size: 12, bold: true, underline: true };
      cell(0, 1).alignment = { horizontal: 'center' };
      merge(1, 1, 2, 'Address of employer:');
      merge(1, 3, 5, String(worker.schedule.employerAddress || report.employerAddress || ''));
      sheet.getRow(top + 1).height = 32;
      merge(4, 1, 5, 'PAYSLIP');
      cell(4, 1).font = { name: 'Times New Roman', size: 24, bold: true };
      cell(4, 1).alignment = { horizontal: 'center' };
      sheet.getRow(top + 4).height = 34;
      merge(6, 1, 2, 'PAY PERIOD END:');
      merge(6, 3, 5, date(report.to));
      const info: [string, ExcelJS.CellValue][] = [
        ['Name Of Employee', String(worker.schedule.firstName || worker.name)],
        ['Surname Of Employee', String(worker.schedule.surname ?? '')],
        ['Identity Number', String(worker.schedule.identityNumber ?? '')],
        ['Date Engaged', date(String(worker.schedule.startDate ?? ''))],
        ['Occupation', String(worker.schedule.occupation ?? '')],
        ['Method Of Payment', String(worker.schedule.paymentMethod ?? '')],
        ['Rate Per Hour', worker.rate],
      ];
      for (const [i, [label, value]] of info.entries()) {
        merge(8 + i, 1, 2, label);
        merge(8 + i, 3, 5, value);
      }
      cell(14, 3).numFmt = '0.00';
      merge(17, 1, 2, 'Earnings');
      cell(17, 3).value = 'Amount';
      cell(17, 4).value = 'Deductions';
      cell(17, 5).value = 'Amount';
      const lines: [string, number | null, number | null, string, number | null][] = [
        ['Normal Hours Worked', worker.workedMinutes / 60, worker.regularPay, 'UIF', worker.uif],
        ['Overtime Hours Worked', null, null, 'Other deductions', worker.otherDeductions || null],
        ['Other:', null, worker.otherPay || null, '', null],
        ['Holiday pay', null, worker.holidayPay || null, '', null],
      ];
      for (const [i, line] of lines.entries()) {
        for (let c = 1; c <= 5; c++) cell(18 + i, c).value = line[c - 1]!;
        cell(18 + i, 2).numFmt = '0.00';
        for (const c of [3, 5]) cell(18 + i, c).numFmt = currency;
      }
      // Keep the tall earnings/deductions boxes from the supplied paper layout.
      for (let r = 17; r <= 31; r++) {
        for (let c = 1; c <= 5; c++) {
          cell(r, c).border = {
            top: r <= 21 || r === 31 ? border : undefined,
            bottom: r === 31 ? border : undefined,
            left: c === 1 || c >= 3 ? border : undefined,
            right: c === 5 ? border : undefined,
          };
        }
      }
      for (let c = 1; c <= 5; c++) {
        cell(17, c).fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: 'FFD9D9D9' } };
        cell(17, c).font = { bold: true, name: 'Times New Roman', size: 12 };
      }
      merge(31, 1, 2, 'Gross Earnings');
      cell(31, 3).value = worker.gross;
      cell(31, 4).value = 'Total Deductions';
      cell(31, 5).value = worker.deductions;
      merge(33, 1, 2, 'RECEIVED CASH');
      merge(34, 1, 3, 'SIGNATURE: __________________________');
      cell(34, 4).value = 'NETT SALARY';
      cell(34, 4).font = { bold: true, italic: true };
      cell(34, 5).value = worker.net;
      for (const [r, c] of [[31, 3], [31, 5], [34, 5]]) cell(r!, c!).numFmt = currency;
      merge(36, 1, 5, worker.gross === null ? 'DRAFT: hourly rate missing.'
        : worker.unresolvedShifts > 0 ? `DRAFT: ${worker.unresolvedShifts} unresolved shift(s) excluded.`
        : `Pay period: ${date(report.from)} - ${date(report.to)}`);
      cell(36, 1).font = { size: 9 };
    }
    if (index < report.workers.length - 1) sheet.getRow(top + 37).addPageBreak();
  }
  sheet.eachRow(row => row.eachCell(cell => {
    cell.font = { name: 'Arial', size: 10, ...cell.font };
    cell.alignment = { ...cell.alignment, vertical: 'middle', wrapText: true };
  }));
  sheet.pageSetup.printArea = `A1:K${Math.max(1, report.workers.length * 38)}`;
}
