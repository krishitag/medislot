// MediSlot API - every business rule lives in Oracle (procedures, package,
// triggers, constraints). This server only calls them and returns JSON.
import "dotenv/config";
import express from "express";
import { initPool, closePool, query, exec, oracledb } from "./db.js";

const app = express();
app.use(express.json());

const OUT_NUM = { dir: oracledb.BIND_OUT, type: oracledb.NUMBER };

// ---------------------------------------------------------------- errors
const FRIENDLY = {
  1: "Duplicate value - a record with this unique value already exists.",
  1400: "A required field is missing.",
  2290: "A value violates a CHECK constraint.",
  2291: "Referenced record does not exist (foreign key).",
  2292: "Record is referenced by other records and cannot be removed.",
};

/** 'ORA-20011: Slot 5 is already booked...\nORA-06512: ...' -> clean message */
export function oraMessage(err) {
  const first = String(err.message || err).split("\n")[0];
  const m = first.match(/ORA-(\d+):\s*(.*)/);
  if (!m) return first;
  const code = Number(m[1]);
  if (code >= 20000 && code <= 20999) return `${m[2]} (ORA-${m[1]})`; // our RAISE_APPLICATION_ERROR
  return FRIENDLY[code] ?? m[2];
}

const wrap = (fn) => (req, res) =>
  fn(req, res).catch((err) => {
    console.error(err.message);
    res.status(400).json({ error: oraMessage(err) });
  });

// ---------------------------------------------------------------- read endpoints
app.get("/api/dashboard", wrap(async (_req, res) => {
  const [stats] = await query(`
    SELECT (SELECT COUNT(*) FROM appointment
             WHERE appt_date = TRUNC(SYSDATE) AND status <> 'CANCELLED')        AS today_appts,
           (SELECT COUNT(*) FROM patient)                                       AS patients,
           (SELECT COUNT(*) FROM medicine WHERE stock_qty <= reorder_level)     AS low_stock,
           (SELECT NVL(SUM(pkg_billing.bill_total(bill_id)), 0)
              FROM bill WHERE payment_status = 'UNPAID')                        AS outstanding
    FROM dual`);
  const doctors = await query(`
    SELECT d.doctor_id, d.doctor_name, dp.dept_name, d.max_daily_slots,
           fn_available_slots(d.doctor_id, SYSDATE) AS free_today
    FROM doctor d JOIN department dp ON dp.dept_id = d.dept_id
    ORDER BY d.doctor_id`);
  res.json({ stats, doctors });
}));

app.get("/api/doctors", wrap(async (_req, res) => {
  res.json(await query(`
    SELECT d.doctor_id, d.doctor_name, d.specialization, d.consult_fee, d.max_daily_slots, dp.dept_name
    FROM doctor d JOIN department dp ON dp.dept_id = d.dept_id
    ORDER BY d.doctor_name`));
}));

app.get("/api/patients", wrap(async (_req, res) => {
  res.json(await query(`
    SELECT patient_id, patient_name, TO_CHAR(dob, 'DD-Mon-YYYY') AS dob, gender, phone, email,
           TRUNC(MONTHS_BETWEEN(SYSDATE, dob) / 12)       AS age,
           pkg_billing.patient_outstanding(patient_id)     AS outstanding
    FROM patient ORDER BY patient_id`));
}));

app.get("/api/appointments", wrap(async (req, res) => {
  const binds = {};
  let where = "";
  if (req.query.status) {
    where = "WHERE status = :status";
    binds.status = req.query.status;
  }
  res.json(await query(`
    SELECT appt_id, TO_CHAR(appt_date, 'DD-Mon-YYYY (Dy)') AS date_txt, slot_no, status,
           patient_name, doctor_name, dept_name, bill_id, payment_status
    FROM v_appointment_details ${where}
    ORDER BY appt_date DESC, slot_no`, binds));
}));

app.get("/api/appointments/:id", wrap(async (req, res) => {
  const id = Number(req.params.id);
  const [appt] = await query(`
    SELECT v.appt_id, v.slot_no, v.status, v.patient_id, v.patient_name, v.patient_phone,
           v.doctor_name, v.specialization, v.consult_fee, v.dept_name,
           TO_CHAR(v.appt_date, 'DD-Mon-YYYY (Dy)') AS date_txt
    FROM v_appointment_details v WHERE v.appt_id = :id`, { id });
  if (!appt) return res.status(404).json({ error: `Appointment ${id} not found` });

  const meds = await query(`
    SELECT m.med_name, pr.quantity, pr.dosage, m.unit_price, pr.quantity * m.unit_price AS amount
    FROM prescription pr JOIN medicine m ON m.med_id = pr.med_id
    WHERE pr.appt_id = :id ORDER BY m.med_name`, { id });
  const [bill] = await query(`
    SELECT bill_id, consult_amt, med_amt, gst_rate, payment_status,
           TO_CHAR(generated_on, 'DD-Mon-YYYY') AS generated_on,
           TO_CHAR(paid_on, 'DD-Mon-YYYY')      AS paid_on,
           pkg_billing.bill_total(bill_id)       AS total
    FROM bill WHERE appt_id = :id`, { id });
  const history = await query(`
    SELECT NVL(old_status, '-') AS old_status, new_status,
           TO_CHAR(changed_on, 'DD-Mon-YYYY HH24:MI:SS') AS changed_on, changed_by
    FROM appt_audit WHERE appt_id = :id ORDER BY audit_id`, { id });
  const [{ med_cost }] = await query(`SELECT fn_medicine_cost(:id) AS med_cost FROM dual`, { id });

  res.json({ appt, meds, bill: bill ?? null, history, med_cost });
}));

app.get("/api/medicines", wrap(async (_req, res) => {
  res.json(await query(`
    SELECT med_id, med_name, unit_price, stock_qty, reorder_level,
           CASE WHEN stock_qty <= reorder_level THEN 1 ELSE 0 END AS low
    FROM medicine ORDER BY low DESC, med_name`));
}));

app.get("/api/audit", wrap(async (_req, res) => {
  res.json(await query(`
    SELECT audit_id, appt_id, NVL(old_status, '-') AS old_status, new_status,
           TO_CHAR(changed_on, 'DD-Mon-YYYY HH24:MI:SS') AS changed_on, changed_by
    FROM appt_audit ORDER BY audit_id DESC FETCH FIRST 100 ROWS ONLY`));
}));

// ---------------------------------------------------------------- write endpoints
app.post("/api/patients", wrap(async (req, res) => {
  const { name, dob, gender, phone, email } = req.body;
  const r = await exec(`
    INSERT INTO patient (patient_name, dob, gender, phone, email)
    VALUES (:name, TO_DATE(:dob, 'YYYY-MM-DD'), :gender, :phone, :email)
    RETURNING patient_id INTO :id`,
    { name: name?.trim(), dob, gender, phone: phone?.trim(), email: email?.trim() || null, id: OUT_NUM });
  res.status(201).json({ patient_id: r.outBinds.id[0], message: `Patient registered with ID ${r.outBinds.id[0]}` });
}));

// Booking -> stored procedure pr_book_appointment (triggers fire inside it)
app.post("/api/appointments", wrap(async (req, res) => {
  const { patient_id, doctor_id, appt_date, slot_no } = req.body;
  const r = await exec(
    `BEGIN pr_book_appointment(:p, :d, TO_DATE(:dt, 'YYYY-MM-DD'), :s, :id); END;`,
    { p: Number(patient_id), d: Number(doctor_id), dt: appt_date, s: Number(slot_no), id: OUT_NUM });
  res.status(201).json({ appt_id: r.outBinds.id, message: `Appointment booked. ID: ${r.outBinds.id}` });
}));

app.post("/api/appointments/:id/complete", wrap(async (req, res) => {
  await exec(`BEGIN pr_complete_appointment(:id); END;`, { id: Number(req.params.id) });
  res.json({ message: `Appointment ${req.params.id} marked COMPLETED` });
}));

app.post("/api/appointments/:id/cancel", wrap(async (req, res) => {
  await exec(`BEGIN pr_cancel_appointment(:id); END;`, { id: Number(req.params.id) });
  res.json({ message: `Appointment ${req.params.id} cancelled` });
}));

// Prescription insert -> trigger trg_prescription_stock checks & reduces stock
app.post("/api/appointments/:id/prescriptions", wrap(async (req, res) => {
  const { med_id, quantity, dosage } = req.body;
  await exec(
    `INSERT INTO prescription (appt_id, med_id, quantity, dosage) VALUES (:a, :m, :q, :d)`,
    { a: Number(req.params.id), m: Number(med_id), q: Number(quantity), d: dosage?.trim() });
  res.status(201).json({ message: "Medicine added - stock updated by trigger" });
}));

// Billing -> package pkg_billing
app.post("/api/appointments/:id/bill", wrap(async (req, res) => {
  const r = await exec(`BEGIN pkg_billing.generate_bill(:a, :b); END;`,
    { a: Number(req.params.id), b: OUT_NUM });
  res.status(201).json({ bill_id: r.outBinds.b, message: `Bill ${r.outBinds.b} generated` });
}));

app.post("/api/bills/:id/pay", wrap(async (req, res) => {
  await exec(`BEGIN pkg_billing.mark_paid(:b); END;`, { b: Number(req.params.id) });
  res.json({ message: `Bill ${req.params.id} marked PAID` });
}));

// ---------------------------------------------------------------- start
const PORT = Number(process.env.PORT || 4000);

if (process.env.NODE_ENV !== "test") {
  initPool()
    .then(() => app.listen(PORT, () => console.log(`MediSlot API on http://localhost:${PORT}`)))
    .catch((err) => {
      console.error("Could not connect to Oracle:", err.message);
      console.error("Check server/.env (DB_USER, DB_PASSWORD, DB_CONNECT_STRING) and that the container is running.");
      process.exit(1);
    });
  process.on("SIGINT", async () => { await closePool(); process.exit(0); });
}

export default app;
