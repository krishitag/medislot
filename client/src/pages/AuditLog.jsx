import { Link } from "react-router-dom";
import { useData } from "../useData.js";

export default function AuditLog() {
  const [rows] = useData("/api/audit");
  return (
    <>
      <h2>Appointment audit log <span className="hint">(trigger trg_appt_audit)</span></h2>
      <div className="card">
        <table>
          <thead><tr><th>#</th><th>Appointment</th><th>From</th><th>To</th><th>When</th><th>DB user</th></tr></thead>
          <tbody>
            {rows?.map((r) => (
              <tr key={r.audit_id}>
                <td>{r.audit_id}</td><td><Link to={`/appointments/${r.appt_id}`}>{r.appt_id}</Link></td>
                <td>{r.old_status}</td><td><span className={`pill ${r.new_status}`}>{r.new_status}</span></td>
                <td>{r.changed_on}</td><td>{r.changed_by}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </>
  );
}
