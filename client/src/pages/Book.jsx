import { useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";
import { api } from "../api.js";
import { useData } from "../useData.js";
import { useFlash } from "../App.jsx";

const today = () => new Date().toLocaleDateString("en-CA"); // YYYY-MM-DD in local time

export default function Book() {
  const [patients] = useData("/api/patients");
  const [doctors] = useData("/api/doctors");
  const [form, setForm] = useState({ patient_id: "", doctor_id: "", appt_date: today(), slot_no: 1 });
  const [busy, setBusy] = useState(false);
  const flash = useFlash();
  const navigate = useNavigate();
  const set = (k) => (e) => setForm({ ...form, [k]: e.target.value });

  // default the dropdowns to the first option once data arrives
  useEffect(() => {
    if (patients?.length && doctors?.length && !form.patient_id)
      setForm((f) => ({ ...f, patient_id: patients[0].patient_id, doctor_id: doctors[0].doctor_id }));
  }, [patients, doctors, form.patient_id]);

  async function submit(e) {
    e.preventDefault();
    setBusy(true);
    try {
      const r = await api.post("/api/appointments", form);
      flash("ok", r.message);
      navigate(`/appointments/${r.appt_id}`);
    } catch (err) {
      flash("err", err.message); // e.g. "Clinic is closed on Sundays (ORA-20002)"
    } finally {
      setBusy(false);
    }
  }

  return (
    <>
      <h2>Book appointment</h2>
      <div className="card">
        <form onSubmit={submit}>
          <div className="grid">
            <div><label>Patient</label>
              <select value={form.patient_id} onChange={set("patient_id")} required>
                {patients?.map((p) => <option key={p.patient_id} value={p.patient_id}>{p.patient_name} (#{p.patient_id})</option>)}
              </select></div>
            <div><label>Doctor</label>
              <select value={form.doctor_id} onChange={set("doctor_id")} required>
                {doctors?.map((d) => (
                  <option key={d.doctor_id} value={d.doctor_id}>
                    {d.doctor_name} - {d.specialization} (₹{d.consult_fee}, {d.max_daily_slots} slots)
                  </option>))}
              </select></div>
            <div><label>Date</label><input type="date" value={form.appt_date} onChange={set("appt_date")} required /></div>
            <div><label>Slot (1-16, 30 min each from 9:00)</label>
              <input type="number" min="1" max="16" value={form.slot_no} onChange={set("slot_no")} required /></div>
          </div>
          <button disabled={busy}>Book (calls pr_book_appointment)</button>
        </form>
        <p className="muted" style={{ marginBottom: 0 }}>
          Past dates, Sundays, occupied slots and patient clashes are rejected by the database itself.
        </p>
      </div>
    </>
  );
}
