import { useData } from "../useData.js";
import { money } from "../api.js";

export default function Pharmacy() {
  const [rows] = useData("/api/medicines");
  return (
    <>
      <h2>Pharmacy stock</h2>
      <div className="card">
        <table>
          <thead><tr><th>ID</th><th>Medicine</th><th className="right">Unit price</th><th className="right">In stock</th><th className="right">Reorder level</th><th></th></tr></thead>
          <tbody>
            {rows?.map((m) => (
              <tr key={m.med_id} className={m.low ? "low" : ""}>
                <td>{m.med_id}</td><td>{m.med_name}</td><td className="right">{money(m.unit_price)}</td>
                <td className="right">{m.stock_qty}</td><td className="right">{m.reorder_level}</td>
                <td>{m.low ? <span className="pill REORDER">REORDER</span> : null}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </>
  );
}
