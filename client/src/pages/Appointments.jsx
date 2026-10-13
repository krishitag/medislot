import { useState } from "react";
import { Link } from "react-router-dom";
import { api } from "../api.js";
import { useData } from "../useData.js";
import { useFlash } from "../App.jsx";

const STATUSES = ["BOOKED", "COMPLETED", "CANCELLED", "NO_SHOW"];

export default function Appointments() {
  const [status, setStatus] = useState("");
  const [rows, reload] = useData(`/api/appointments${status ? `?status=${status}` : ""}`);
  const flash = useFlash();

  async function act(id, action) {
    try {
      const r = await api.post(`/api/appointments/${id}/${action}`);
      flash("ok", r.message);
      reload();
    } catch (err) {
      flash("err", err.message);
    }
  }

  return (
    <>
      <h2>Appointments</h2>
      <select className="filter" value={status} onChange={(e) => setStatus(e.target.value)}>
        <option value="">All statuses</option>
        {STATUSES.map((s) => <option key={s}>{s}</option>)}
      </select>
      <div className="card">
        <table>
          <thead><tr><th>ID</th><th>Date</th><th>Slot</th><th>Patient</th><th>Doctor</th><th>Status</th><th>Bill</th><th>Actions</th></tr></thead>
          <tbody>
            {rows?.map((a) => (
              <tr key={a.appt_id}>
                <td><Link to={`/appointments/${a.appt_id}`}>{a.appt_id}</Link></td>
                <td>{a.date_txt}</td><td>{a.slot_no}</td><td>{a.patient_name}</td>
                <td>{a.doctor_name}<br /><span className="muted">{a.dept_name}</span></td>
                <td><span className={`pill ${a.status}`}>{a.status}</span></td>
                <td>{a.bill_id ? <>#{a.bill_id} <span className={`pill ${a.payment_status}`}>{a.payment_status}</span></> : "-"}</td>
                <td>
                  {a.status === "BOOKED" ? (
                    <>
                      <button className="small" onClick={() => act(a.appt_id, "complete")}>Complete</button>
                      <button className="small red" onClick={() => act(a.appt_id, "cancel")}>Cancel</button>
                    </>
                  ) : <Link to={`/appointments/${a.appt_id}`}>Open</Link>}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </>
  );
}
