import { useState } from "react";
import { useParams } from "react-router-dom";
import { api, money } from "../api.js";
import { useData } from "../useData.js";
import { useFlash } from "../App.jsx";

export default function AppointmentDetail() {
  const { id } = useParams();
  const [data, reload] = useData(`/api/appointments/${id}`);
  const [stock, reloadStock] = useData("/api/medicines");
  const [rx, setRx] = useState({ med_id: "", quantity: 1, dosage: "" });
  const flash = useFlash();

  async function run(url, body) {
    try {
      const r = await api.post(url, body);
      flash("ok", r.message);
      reload();
      reloadStock();
      return true;
    } catch (err) {
      flash("err", err.message);
      return false;
    }
  }

  async function addMedicine(e) {
    e.preventDefault();
    const medId = rx.med_id || stock?.[0]?.med_id;
    if (await run(`/api/appointments/${id}/prescriptions`, { ...rx, med_id: medId }))
      setRx({ med_id: medId, quantity: 1, dosage: "" });
  }

  if (!data) return <p className="muted">Loading…</p>;
  const { appt: a, meds, bill, history, med_cost } = data;
  const sortedStock = stock ? [...stock].sort((x, y) => x.med_name.localeCompare(y.med_name)) : [];

  return (
    <>
      <h2>Appointment #{a.appt_id} <span className={`pill ${a.status}`}>{a.status}</span></h2>

      <div className="card">
        <div className="grid">
          <div><label>Patient</label>{a.patient_name} (#{a.patient_id}, {a.patient_phone})</div>
          <div><label>Doctor</label>{a.doctor_name} - {a.specialization}</div>
          <div><label>Date / slot</label>{a.date_txt}, slot {a.slot_no}</div>
          <div><label>Consultation fee</label>{money(a.consult_fee)}</div>
        </div>
        {a.status === "BOOKED" && (
          <>
            <button onClick={() => run(`/api/appointments/${id}/complete`)}>Mark visit completed</button>{" "}
            <button className="red" onClick={() => run(`/api/appointments/${id}/cancel`)}>Cancel</button>
          </>
        )}
      </div>

      <div className="card">
        <h3>Prescription</h3>
        <table>
          <thead><tr><th>Medicine</th><th>Qty</th><th>Dosage</th><th className="right">Unit</th><th className="right">Amount</th></tr></thead>
          <tbody>
            {meds.length === 0 && <tr><td colSpan={5} className="muted">No medicines prescribed.</td></tr>}
            {meds.map((m) => (
              <tr key={m.med_name}>
                <td>{m.med_name}</td><td>{m.quantity}</td><td>{m.dosage}</td>
                <td className="right">{money(m.unit_price)}</td><td className="right">{money(m.amount)}</td>
              </tr>
            ))}
          </tbody>
        </table>
        {!bill && (
          <form onSubmit={addMedicine}>
            <div className="grid">
              <div><label>Medicine</label>
                <select value={rx.med_id} onChange={(e) => setRx({ ...rx, med_id: e.target.value })}>
                  {sortedStock.map((s) => <option key={s.med_id} value={s.med_id}>{s.med_name} (in stock: {s.stock_qty})</option>)}
                </select></div>
              <div><label>Quantity</label>
                <input type="number" min="1" value={rx.quantity} onChange={(e) => setRx({ ...rx, quantity: e.target.value })} required /></div>
              <div><label>Dosage</label>
                <input value={rx.dosage} placeholder="1-0-1 after food, 5 days" onChange={(e) => setRx({ ...rx, dosage: e.target.value })} required /></div>
            </div>
            <button>Add medicine</button>
          </form>
        )}
      </div>

      <div className="card">
        <h3>Bill</h3>
        {bill ? (
          <>
            <table>
              <tbody>
                <tr><td>Bill number</td><td className="right">#{bill.bill_id} ({bill.generated_on})</td></tr>
                <tr><td>Consultation</td><td className="right">{money(bill.consult_amt)}</td></tr>
                <tr><td>Medicines</td><td className="right">{money(bill.med_amt)}</td></tr>
                <tr><td>GST on medicines ({bill.gst_rate}%)</td><td className="right">{money(bill.med_amt * bill.gst_rate / 100)}</td></tr>
                <tr><th>Total (pkg_billing.bill_total)</th><th className="right">{money(bill.total)}</th></tr>
                <tr><td>Status</td><td className="right"><span className={`pill ${bill.payment_status}`}>{bill.payment_status}</span> {bill.paid_on || ""}</td></tr>
              </tbody>
            </table>
            {bill.payment_status === "UNPAID" && (
              <button onClick={() => run(`/api/bills/${bill.bill_id}/pay`)}>Record payment</button>
            )}
          </>
        ) : (
          <>
            <p className="muted">No bill yet (medicines so far: {money(med_cost)}, from fn_medicine_cost).</p>
            <button onClick={() => run(`/api/appointments/${id}/bill`)}>Generate bill (pkg_billing.generate_bill)</button>
          </>
        )}
      </div>

      <div className="card">
        <h3>Status history <span className="hint">(written by trigger trg_appt_audit)</span></h3>
        <table>
          <thead><tr><th>From</th><th>To</th><th>When</th><th>By</th></tr></thead>
          <tbody>
            {history.map((h, i) => (
              <tr key={i}><td>{h.old_status}</td><td>{h.new_status}</td><td>{h.changed_on}</td><td>{h.changed_by}</td></tr>
            ))}
          </tbody>
        </table>
      </div>
    </>
  );
}
