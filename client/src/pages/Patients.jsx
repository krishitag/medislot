import { useState } from "react";
import { api, money } from "../api.js";
import { useData } from "../useData.js";
import { useFlash } from "../App.jsx";

const EMPTY = { name: "", dob: "", gender: "M", phone: "", email: "" };

export default function Patients() {
  const [rows, reload] = useData("/api/patients");
  const [form, setForm] = useState(EMPTY);
  const flash = useFlash();
  const set = (k) => (e) => setForm({ ...form, [k]: e.target.value });

  async function submit(e) {
    e.preventDefault();
    try {
      const r = await api.post("/api/patients", form);
      flash("ok", r.message);
      setForm(EMPTY);
      reload();
    } catch (err) {
      flash("err", err.message);
    }
  }

  return (
    <>
      <h2>Patients</h2>
      <div className="card">
        <h3>Register patient</h3>
        <form onSubmit={submit}>
          <div className="grid">
            <div><label>Full name</label><input value={form.name} onChange={set("name")} required maxLength={50} /></div>
            <div><label>Date of birth</label><input type="date" value={form.dob} onChange={set("dob")} required /></div>
            <div><label>Gender</label>
              <select value={form.gender} onChange={set("gender")}>
                <option value="M">Male</option><option value="F">Female</option><option value="O">Other</option>
              </select></div>
            <div><label>Phone</label><input value={form.phone} onChange={set("phone")} required maxLength={15} /></div>
            <div><label>Email (optional)</label><input type="email" value={form.email} onChange={set("email")} maxLength={80} /></div>
          </div>
          <button>Register</button>
        </form>
      </div>
      <div className="card">
        <table>
          <thead><tr><th>ID</th><th>Name</th><th>DOB</th><th>Age</th><th>Gender</th><th>Phone</th><th>Email</th><th className="right">Outstanding</th></tr></thead>
          <tbody>
            {rows?.map((p) => (
              <tr key={p.patient_id}>
                <td>{p.patient_id}</td><td>{p.patient_name}</td><td>{p.dob}</td><td>{p.age}</td><td>{p.gender}</td>
                <td>{p.phone}</td><td>{p.email || "-"}</td><td className="right">{money(p.outstanding)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </>
  );
}
