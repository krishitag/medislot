# MediSlot: Clinic Appointment & Billing Management System

BCSE302P Database Systems Lab mini project. An Oracle-backed clinic system where patients book doctor slots, doctors complete visits and prescribe medicines, and the system bills the visit. **All business rules live in the database** (constraints, PL/SQL procedures, a package, triggers and cursors). The web app only calls them.

**Stack:** Oracle Database 21c XE · Node.js + Express (`oracledb`, thin mode) · React (Vite)

```
database/   01_schema.sql   tables, constraints, function-based unique index
            02_plsql.sql    view, 2 functions, 3 procedures, pkg_billing, 4 triggers, 3 cursor procedures
            03_seed.sql     sample data (dates relative to SYSDATE)
            04_tests.sql    22 test cases (TC01–TC22) with PASS/FAIL output
server/     Express API → calls the procedures / package
client/     React UI: dashboard, booking, appointments, prescriptions & billing, pharmacy, audit log
docs/       ER diagram
```

## 1. Database

Prerequisite: Oracle XE running (Docker) with a `MEDISLOT` user in the `XEPDB1` pluggable database.

In VS Code (Oracle SQL Developer extension), open a worksheet on the **medislot** connection and run each file **as a script** in order:

1. `database/01_schema.sql`
2. `database/02_plsql.sql` (the final query must return **no rows**, meaning everything compiled)
3. `database/03_seed.sql`
4. `database/04_tests.sql` (every test prints `PASS`)

To reset the data, run 01 → 02 → 03 again (`01_schema.sql` drops the old tables first).

## 2. API server

```bash
cd server
cp .env.example .env      # edit if your user / password / service differ
npm install
npm run dev               # http://localhost:4000
```

## 3. Frontend

```bash
cd client
npm install
npm run dev               # http://localhost:5173  (proxies /api to :4000)
```

## Database objects

| Type | Name | Purpose |
|---|---|---|
| Function | `fn_available_slots` | free slots for a doctor on a date |
| Function | `fn_medicine_cost` | cost of medicines prescribed in a visit |
| Procedure | `pr_book_appointment` | validates and books a slot (OUT: appt_id) |
| Procedure | `pr_cancel_appointment`, `pr_complete_appointment` | status changes |
| Package | `pkg_billing` | `generate_bill`, `mark_paid`, `bill_total`, `patient_outstanding` |
| Trigger | `trg_appt_validate` | no past dates, no Sundays |
| Trigger | `trg_appt_status_guard` | final states are locked; future visits can't be completed |
| Trigger | `trg_appt_audit` | logs every status change to `appt_audit` |
| Trigger | `trg_prescription_stock` | stock check + auto-decrement; billed visits are locked |
| Cursor | `pr_doctor_schedule` | parameterized explicit cursor |
| Cursor | `pr_low_stock_report` | explicit cursor (OPEN / FETCH / CLOSE) |
| Cursor | `pr_mark_no_shows` | implicit cursor (`SQL%ROWCOUNT`) |

## Helper scripts (`tools/`)

```bash
tools/db.sh reset          # fresh load: 01 -> 02 -> 03 (sqlplus in the oracle-xe container)
tools/db.sh tests          # reset + 04_tests.sql; output saved to screenshots/tests_output.txt
cd tools && npm install && npx playwright install chromium && node capture_ui.mjs   # UI screenshots
python3 tools/build_report.py   # inserts screenshots + test results into a copy of the report
```
