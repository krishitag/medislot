import { useData } from "../useData.js";
import { money } from "../api.js";

export default function Dashboard() {
  const [data] = useData("/api/dashboard");
  if (!data) return <p className="muted">Loading…</p>;
  const { stats: s, doctors } = data;
  return (
    <>
      <h2>Dashboard</h2>
      <div className="stats">
        <div className="stat"><b>{s.today_appts}</b><span>Appointments today</span></div>
        <div className="stat"><b>{s.patients}</b><span>Registered patients</span></div>
        <div className="stat"><b>{s.low_stock}</b><span>Medicines below reorder level</span></div>
        <div className="stat"><b>{money(s.outstanding)}</b><span>Unpaid bills</span></div>
      </div>
      <div className="card">
        <h3>Doctor availability today <span className="hint">(fn_available_slots)</span></h3>
        <table>
          <thead><tr><th>ID</th><th>Doctor</th><th>Department</th><th className="right">Daily slots</th><th className="right">Free today</th></tr></thead>
          <tbody>
            {doctors.map((d) => (
              <tr key={d.doctor_id}>
                <td>{d.doctor_id}</td><td>{d.doctor_name}</td><td>{d.dept_name}</td>
                <td className="right">{d.max_daily_slots}</td><td className="right"><b>{d.free_today}</b></td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </>
  );
}
