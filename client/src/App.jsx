import { createContext, useCallback, useContext, useState } from "react";
import { NavLink, Route, Routes } from "react-router-dom";
import Dashboard from "./pages/Dashboard.jsx";
import Patients from "./pages/Patients.jsx";
import Book from "./pages/Book.jsx";
import Appointments from "./pages/Appointments.jsx";
import AppointmentDetail from "./pages/AppointmentDetail.jsx";
import Pharmacy from "./pages/Pharmacy.jsx";
import AuditLog from "./pages/AuditLog.jsx";

// Global flash message (success / Oracle error) shown under the nav bar
const FlashContext = createContext(() => {});
export const useFlash = () => useContext(FlashContext);

export default function App() {
  const [flash, setFlash] = useState(null);
  const show = useCallback((type, text) => {
    setFlash({ type, text });
    window.scrollTo({ top: 0, behavior: "smooth" });
  }, []);

  const links = [
    ["/", "Dashboard"],
    ["/book", "Book"],
    ["/appointments", "Appointments"],
    ["/patients", "Patients"],
    ["/pharmacy", "Pharmacy"],
    ["/audit", "Audit log"],
  ];

  return (
    <FlashContext.Provider value={show}>
      <header>
        <h1>MediSlot</h1>
        <nav>
          {links.map(([to, label]) => (
            <NavLink key={to} to={to} end={to === "/"} onClick={() => setFlash(null)}>
              {label}
            </NavLink>
          ))}
        </nav>
      </header>
      <main>
        {flash && (
          <div className={`flash ${flash.type}`} onClick={() => setFlash(null)}>
            {flash.text}
          </div>
        )}
        <Routes>
          <Route path="/" element={<Dashboard />} />
          <Route path="/book" element={<Book />} />
          <Route path="/appointments" element={<Appointments />} />
          <Route path="/appointments/:id" element={<AppointmentDetail />} />
          <Route path="/patients" element={<Patients />} />
          <Route path="/pharmacy" element={<Pharmacy />} />
          <Route path="/audit" element={<AuditLog />} />
        </Routes>
      </main>
    </FlashContext.Provider>
  );
}
