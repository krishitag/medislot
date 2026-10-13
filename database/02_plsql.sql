-- =============================================================
-- MediSlot : 02_plsql.sql
-- Functions, procedures, package, triggers, cursors, view
-- Run AFTER 01_schema.sql.  In SQL Developer use "Run Script" (F5).
-- =============================================================
SET SERVEROUTPUT ON

-- -------------------------------------------------------------
-- VIEW used by the front-end
-- -------------------------------------------------------------
CREATE OR REPLACE VIEW v_appointment_details AS
SELECT a.appt_id, a.appt_date, a.slot_no, a.status,
       p.patient_id, p.patient_name, p.phone AS patient_phone,
       d.doctor_id, d.doctor_name, d.specialization, d.consult_fee,
       dp.dept_name,
       b.bill_id, b.payment_status
FROM   appointment a
JOIN   patient     p  ON p.patient_id = a.patient_id
JOIN   doctor      d  ON d.doctor_id  = a.doctor_id
JOIN   department  dp ON dp.dept_id   = d.dept_id
LEFT JOIN bill     b  ON b.appt_id    = a.appt_id;

-- =============================================================
-- 4.1  FUNCTIONS
-- =============================================================

-- Number of free slots a doctor still has on a given date
CREATE OR REPLACE FUNCTION fn_available_slots (
  p_doctor_id IN doctor.doctor_id%TYPE,
  p_date      IN DATE
) RETURN NUMBER IS
  v_max     doctor.max_daily_slots%TYPE;
  v_booked  NUMBER;
BEGIN
  SELECT max_daily_slots INTO v_max
  FROM   doctor WHERE doctor_id = p_doctor_id;

  SELECT COUNT(*) INTO v_booked
  FROM   appointment
  WHERE  doctor_id = p_doctor_id
  AND    appt_date = TRUNC(p_date)
  AND    status   <> 'CANCELLED';

  RETURN v_max - v_booked;
EXCEPTION
  WHEN NO_DATA_FOUND THEN
    RAISE_APPLICATION_ERROR(-20020, 'Doctor ' || p_doctor_id || ' does not exist');
END fn_available_slots;
/

-- Total cost of medicines prescribed in one appointment
CREATE OR REPLACE FUNCTION fn_medicine_cost (
  p_appt_id IN appointment.appt_id%TYPE
) RETURN NUMBER IS
  v_cost NUMBER(10,2);
BEGIN
  SELECT NVL(SUM(pr.quantity * m.unit_price), 0)
  INTO   v_cost
  FROM   prescription pr
  JOIN   medicine m ON m.med_id = pr.med_id
  WHERE  pr.appt_id = p_appt_id;
  RETURN v_cost;
END fn_medicine_cost;
/

-- =============================================================
-- 4.2  PROCEDURES
-- =============================================================

-- Books an appointment after enforcing all business rules
CREATE OR REPLACE PROCEDURE pr_book_appointment (
  p_patient_id IN  patient.patient_id%TYPE,
  p_doctor_id  IN  doctor.doctor_id%TYPE,
  p_date       IN  DATE,
  p_slot_no    IN  NUMBER,
  p_appt_id    OUT appointment.appt_id%TYPE
) IS
  v_cnt  NUMBER;
  v_max  doctor.max_daily_slots%TYPE;
BEGIN
  SELECT COUNT(*) INTO v_cnt FROM patient WHERE patient_id = p_patient_id;
  IF v_cnt = 0 THEN
    RAISE_APPLICATION_ERROR(-20016, 'Patient ' || p_patient_id || ' does not exist');
  END IF;

  BEGIN
    SELECT max_daily_slots INTO v_max FROM doctor WHERE doctor_id = p_doctor_id;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      RAISE_APPLICATION_ERROR(-20020, 'Doctor ' || p_doctor_id || ' does not exist');
  END;

  IF p_slot_no > v_max THEN
    RAISE_APPLICATION_ERROR(-20012, 'Doctor works only ' || v_max || ' slots per day');
  END IF;

  -- patient cannot be in two places at the same time
  SELECT COUNT(*) INTO v_cnt
  FROM   appointment
  WHERE  patient_id = p_patient_id
  AND    appt_date  = TRUNC(p_date)
  AND    slot_no    = p_slot_no
  AND    status    <> 'CANCELLED';
  IF v_cnt > 0 THEN
    RAISE_APPLICATION_ERROR(-20013, 'Patient already has an appointment in this slot');
  END IF;

  -- one active appointment per patient per doctor per day
  SELECT COUNT(*) INTO v_cnt
  FROM   appointment
  WHERE  patient_id = p_patient_id
  AND    doctor_id  = p_doctor_id
  AND    appt_date  = TRUNC(p_date)
  AND    status    <> 'CANCELLED';
  IF v_cnt > 0 THEN
    RAISE_APPLICATION_ERROR(-20014, 'Patient already booked with this doctor on this date');
  END IF;

  INSERT INTO appointment (patient_id, doctor_id, appt_date, slot_no)
  VALUES (p_patient_id, p_doctor_id, TRUNC(p_date), p_slot_no)
  RETURNING appt_id INTO p_appt_id;

  COMMIT;
EXCEPTION
  WHEN DUP_VAL_ON_INDEX THEN
    ROLLBACK;
    RAISE_APPLICATION_ERROR(-20011, 'Slot ' || p_slot_no || ' is already booked for this doctor');
  WHEN OTHERS THEN
    ROLLBACK;
    RAISE;
END pr_book_appointment;
/

-- Cancels a BOOKED appointment (uses implicit cursor attribute SQL%ROWCOUNT)
CREATE OR REPLACE PROCEDURE pr_cancel_appointment (
  p_appt_id IN appointment.appt_id%TYPE
) IS
BEGIN
  UPDATE appointment
  SET    status  = 'CANCELLED'
  WHERE  appt_id = p_appt_id
  AND    status  = 'BOOKED';

  IF SQL%ROWCOUNT = 0 THEN
    RAISE_APPLICATION_ERROR(-20015, 'Appointment ' || p_appt_id ||
                            ' not found or not in BOOKED state');
  END IF;
  COMMIT;
EXCEPTION
  WHEN OTHERS THEN
    ROLLBACK;
    RAISE;
END pr_cancel_appointment;
/

-- Marks a BOOKED appointment as COMPLETED (visit done)
CREATE OR REPLACE PROCEDURE pr_complete_appointment (
  p_appt_id IN appointment.appt_id%TYPE
) IS
BEGIN
  UPDATE appointment
  SET    status  = 'COMPLETED'
  WHERE  appt_id = p_appt_id
  AND    status  = 'BOOKED';

  IF SQL%ROWCOUNT = 0 THEN
    RAISE_APPLICATION_ERROR(-20017, 'Appointment ' || p_appt_id ||
                            ' not found or not in BOOKED state');
  END IF;
  COMMIT;
EXCEPTION
  WHEN OTHERS THEN
    ROLLBACK;
    RAISE;
END pr_complete_appointment;
/

-- =============================================================
-- 4.3  PACKAGE : pkg_billing
-- =============================================================
CREATE OR REPLACE PACKAGE pkg_billing AS
  c_gst_rate CONSTANT NUMBER := 5;   -- GST % applied on medicines

  PROCEDURE generate_bill (p_appt_id IN  appointment.appt_id%TYPE,
                           p_bill_id OUT bill.bill_id%TYPE);
  PROCEDURE mark_paid     (p_bill_id IN  bill.bill_id%TYPE);
  FUNCTION  bill_total    (p_bill_id IN  bill.bill_id%TYPE) RETURN NUMBER;
  FUNCTION  patient_outstanding (p_patient_id IN patient.patient_id%TYPE) RETURN NUMBER;
END pkg_billing;
/

CREATE OR REPLACE PACKAGE BODY pkg_billing AS

  -- private helper: not visible outside the package
  FUNCTION calc_total (p_consult NUMBER, p_med NUMBER, p_gst NUMBER) RETURN NUMBER IS
  BEGIN
    RETURN ROUND(p_consult + p_med + (p_med * p_gst / 100), 2);
  END calc_total;

  PROCEDURE generate_bill (p_appt_id IN  appointment.appt_id%TYPE,
                           p_bill_id OUT bill.bill_id%TYPE) IS
    v_status  appointment.status%TYPE;
    v_fee     doctor.consult_fee%TYPE;
    v_cnt     NUMBER;
  BEGIN
    BEGIN
      SELECT a.status, d.consult_fee
      INTO   v_status, v_fee
      FROM   appointment a JOIN doctor d ON d.doctor_id = a.doctor_id
      WHERE  a.appt_id = p_appt_id;
    EXCEPTION
      WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(-20033, 'Appointment ' || p_appt_id || ' does not exist');
    END;

    IF v_status <> 'COMPLETED' THEN
      RAISE_APPLICATION_ERROR(-20030, 'Bill can be generated only for COMPLETED appointments (current: '
                              || v_status || ')');
    END IF;

    SELECT COUNT(*) INTO v_cnt FROM bill WHERE appt_id = p_appt_id;
    IF v_cnt > 0 THEN
      RAISE_APPLICATION_ERROR(-20031, 'Bill already exists for appointment ' || p_appt_id);
    END IF;

    INSERT INTO bill (appt_id, consult_amt, med_amt, gst_rate)
    VALUES (p_appt_id, v_fee, fn_medicine_cost(p_appt_id), c_gst_rate)
    RETURNING bill_id INTO p_bill_id;

    COMMIT;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      RAISE;
  END generate_bill;

  PROCEDURE mark_paid (p_bill_id IN bill.bill_id%TYPE) IS
  BEGIN
    UPDATE bill
    SET    payment_status = 'PAID',
           paid_on        = SYSDATE
    WHERE  bill_id        = p_bill_id
    AND    payment_status = 'UNPAID';

    IF SQL%ROWCOUNT = 0 THEN
      RAISE_APPLICATION_ERROR(-20032, 'Bill ' || p_bill_id || ' not found or already paid');
    END IF;
    COMMIT;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      RAISE;
  END mark_paid;

  FUNCTION bill_total (p_bill_id IN bill.bill_id%TYPE) RETURN NUMBER IS
    v_c bill.consult_amt%TYPE;
    v_m bill.med_amt%TYPE;
    v_g bill.gst_rate%TYPE;
  BEGIN
    SELECT consult_amt, med_amt, gst_rate INTO v_c, v_m, v_g
    FROM   bill WHERE bill_id = p_bill_id;
    RETURN calc_total(v_c, v_m, v_g);
  EXCEPTION
    WHEN NO_DATA_FOUND THEN RETURN NULL;
  END bill_total;

  FUNCTION patient_outstanding (p_patient_id IN patient.patient_id%TYPE) RETURN NUMBER IS
    v_total NUMBER := 0;
  BEGIN
    FOR r IN (SELECT b.consult_amt, b.med_amt, b.gst_rate
              FROM   bill b JOIN appointment a ON a.appt_id = b.appt_id
              WHERE  a.patient_id = p_patient_id
              AND    b.payment_status = 'UNPAID')
    LOOP
      v_total := v_total + calc_total(r.consult_amt, r.med_amt, r.gst_rate);
    END LOOP;
    RETURN v_total;
  END patient_outstanding;

END pkg_billing;
/

-- =============================================================
-- 4.4  TRIGGERS
-- =============================================================

-- (T1) Date validation: no past dates, no Sundays
CREATE OR REPLACE TRIGGER trg_appt_validate
BEFORE INSERT OR UPDATE OF appt_date ON appointment
FOR EACH ROW
BEGIN
  :NEW.appt_date := TRUNC(:NEW.appt_date);

  IF :NEW.appt_date < TRUNC(SYSDATE) THEN
    RAISE_APPLICATION_ERROR(-20001, 'Appointment date cannot be in the past');
  END IF;

  IF TO_CHAR(:NEW.appt_date, 'DY', 'NLS_DATE_LANGUAGE=ENGLISH') = 'SUN' THEN
    RAISE_APPLICATION_ERROR(-20002, 'Clinic is closed on Sundays');
  END IF;
END;
/

-- (T2) Status-transition guard: final states cannot change;
--      a visit cannot be completed before its date
CREATE OR REPLACE TRIGGER trg_appt_status_guard
BEFORE UPDATE OF status ON appointment
FOR EACH ROW
WHEN (OLD.status <> NEW.status)
BEGIN
  IF :OLD.status IN ('COMPLETED', 'CANCELLED', 'NO_SHOW') THEN
    RAISE_APPLICATION_ERROR(-20003, 'Cannot change status of a ' || :OLD.status || ' appointment');
  END IF;

  IF :NEW.status = 'COMPLETED' AND :NEW.appt_date > TRUNC(SYSDATE) THEN
    RAISE_APPLICATION_ERROR(-20005, 'Cannot complete an appointment scheduled in the future');
  END IF;
END;
/

-- (T3) Audit trail of every status change
CREATE OR REPLACE TRIGGER trg_appt_audit
AFTER INSERT OR UPDATE OF status ON appointment
FOR EACH ROW
BEGIN
  IF INSERTING THEN
    INSERT INTO appt_audit (appt_id, old_status, new_status)
    VALUES (:NEW.appt_id, NULL, :NEW.status);
  ELSIF :OLD.status <> :NEW.status THEN
    INSERT INTO appt_audit (appt_id, old_status, new_status)
    VALUES (:NEW.appt_id, :OLD.status, :NEW.status);
  END IF;
END;
/

-- (T4) Inventory control on prescriptions
CREATE OR REPLACE TRIGGER trg_prescription_stock
BEFORE INSERT OR DELETE ON prescription
FOR EACH ROW
DECLARE
  v_stock   medicine.stock_qty%TYPE;
  v_status  appointment.status%TYPE;
  v_billed  NUMBER;
BEGIN
  IF INSERTING THEN
    SELECT status INTO v_status FROM appointment WHERE appt_id = :NEW.appt_id;
    IF v_status <> 'COMPLETED' THEN
      RAISE_APPLICATION_ERROR(-20006, 'Medicines can be prescribed only after the visit is COMPLETED');
    END IF;

    SELECT COUNT(*) INTO v_billed FROM bill WHERE appt_id = :NEW.appt_id;
    IF v_billed > 0 THEN
      RAISE_APPLICATION_ERROR(-20007, 'Appointment already billed; prescription is locked');
    END IF;

    SELECT stock_qty INTO v_stock
    FROM   medicine WHERE med_id = :NEW.med_id
    FOR UPDATE;                                  -- lock row against concurrent sales

    IF v_stock < :NEW.quantity THEN
      RAISE_APPLICATION_ERROR(-20004, 'Insufficient stock: only ' || v_stock || ' units available');
    END IF;

    UPDATE medicine SET stock_qty = stock_qty - :NEW.quantity
    WHERE  med_id = :NEW.med_id;

  ELSIF DELETING THEN
    UPDATE medicine SET stock_qty = stock_qty + :OLD.quantity
    WHERE  med_id = :OLD.med_id;
  END IF;
END;
/

-- =============================================================
-- 4.5  CURSORS
-- =============================================================

-- (C1) Parameterized explicit cursor: a doctor's schedule for a day
CREATE OR REPLACE PROCEDURE pr_doctor_schedule (
  p_doctor_id IN doctor.doctor_id%TYPE,
  p_date      IN DATE
) IS
  CURSOR c_sched (cp_doc NUMBER, cp_date DATE) IS
    SELECT a.slot_no, a.appt_id, p.patient_name, a.status
    FROM   appointment a JOIN patient p ON p.patient_id = a.patient_id
    WHERE  a.doctor_id = cp_doc
    AND    a.appt_date = TRUNC(cp_date)
    ORDER  BY a.slot_no;
  v_count NUMBER := 0;
BEGIN
  DBMS_OUTPUT.PUT_LINE('Schedule for doctor ' || p_doctor_id ||
                       ' on ' || TO_CHAR(p_date, 'DD-MON-YYYY'));
  DBMS_OUTPUT.PUT_LINE(RPAD('Slot',6) || RPAD('Appt',7) || RPAD('Patient',22) || 'Status');
  FOR r IN c_sched(p_doctor_id, p_date) LOOP
    DBMS_OUTPUT.PUT_LINE(RPAD(r.slot_no,6) || RPAD(r.appt_id,7) ||
                         RPAD(r.patient_name,22) || r.status);
    v_count := v_count + 1;
  END LOOP;
  DBMS_OUTPUT.PUT_LINE(v_count || ' appointment(s); free slots: ' ||
                       fn_available_slots(p_doctor_id, p_date));
END pr_doctor_schedule;
/

-- (C2) Explicit cursor with OPEN / FETCH / CLOSE: low-stock report
CREATE OR REPLACE PROCEDURE pr_low_stock_report IS
  CURSOR c_low IS
    SELECT med_id, med_name, stock_qty, reorder_level
    FROM   medicine
    WHERE  stock_qty <= reorder_level
    ORDER  BY stock_qty;
  v_rec c_low%ROWTYPE;
BEGIN
  OPEN c_low;
  LOOP
    FETCH c_low INTO v_rec;
    EXIT WHEN c_low%NOTFOUND;
    DBMS_OUTPUT.PUT_LINE('REORDER  ' || RPAD(v_rec.med_name, 28) ||
                         ' stock=' || v_rec.stock_qty ||
                         ' (reorder level ' || v_rec.reorder_level || ')');
  END LOOP;
  DBMS_OUTPUT.PUT_LINE(c_low%ROWCOUNT || ' medicine(s) need reordering');
  CLOSE c_low;
END pr_low_stock_report;
/

-- (C3) Implicit cursor: bulk-mark missed appointments as NO_SHOW
CREATE OR REPLACE PROCEDURE pr_mark_no_shows IS
BEGIN
  UPDATE appointment
  SET    status = 'NO_SHOW'
  WHERE  status = 'BOOKED'
  AND    appt_date < TRUNC(SYSDATE);

  IF SQL%FOUND THEN
    DBMS_OUTPUT.PUT_LINE(SQL%ROWCOUNT || ' appointment(s) marked NO_SHOW');
  ELSE
    DBMS_OUTPUT.PUT_LINE('No missed appointments found');
  END IF;
  COMMIT;
END pr_mark_no_shows;
/

-- Show any compilation errors
SELECT name, type, line, text FROM user_errors ORDER BY name, line;
