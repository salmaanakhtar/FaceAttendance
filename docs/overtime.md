# Overtime rules and schedule advice

## Limits

- Default: **46 hours per week** and **184 hours per month**, per employee.
- Both are total recorded hours (all closed sessions), not just hours beyond a
  daily shift.
- The limits are editable in the web admin **Overtime** page and the mobile
  admin dashboard. They are stored in `orgs.settings.overtime`.
- Alerts can be disabled without changing the limits.

## Week and month boundaries

- The week starts on **Monday** in the organization timezone.
- The month is the calendar month in the organization timezone.
- All date calculations use calendar dates (`YYYY-MM-DD`), never server-local
  timestamps.

## Alert states

| State | Meaning |
| --- | --- |
| `ok` | Worked time is below the limit and the pace projects below it. |
| `projected` | The employee has not crossed the limit yet, but the current pace projects a crossing before the period ends. |
| `exceeded` | Recorded time is already at or above the limit. |

Projection uses the employee's **scheduled workdays** and the average minutes
per elapsed scheduled day:

```
projected = worked + (worked / elapsed scheduled days) * remaining scheduled days
```

If no time has been recorded yet, the projection is zero rather than inventing
a schedule.

## Schedule advice

When an alert exists, the API returns:

- `currentWeeklyHours` — the employee's saved `schedule.hoursPerWeek`
- `suggestedWeeklyHours` — current weekly hours minus the projected overage
- `suggestedPerDayHours` — suggested weekly hours divided by scheduled workdays

The suggestion is advisory. The web admin and mobile admin show an **Apply**
action that writes `hoursPerWeek` back to the employee schedule and audit-logs
the change. Workdays are not removed automatically because the current schedule
model does not define per-day shift times.

## API

| Method | Path | Purpose |
| --- | --- | --- |
| `GET` | `/api/v1/admin/overtime` | Settings, all worker progress, and alerts. |
| `PUT` | `/api/v1/admin/overtime/settings` | Update `enabled`, `weeklyHours`, `monthlyHours`. |
| `POST` | `/api/v1/admin/overtime/:employeeId/apply-suggestion` | Set `schedule.hoursPerWeek` to the suggested value. |

Every settings change and applied suggestion creates an `audit_events` row.
