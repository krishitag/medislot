-- =============================================================
-- MediSlot : 03_seed.sql  --  sample data
-- Run AFTER 02_plsql.sql.
-- Dates are relative to SYSDATE so the demo always works.
-- =============================================================
SET SERVEROUTPUT ON

INSERT INTO department (dept_name, location) VALUES ('General Medicine', 'Block A, Ground Floor');
INSERT INTO department (dept_name, location) VALUES ('Cardiology',       'Block B, First Floor');
INSERT INTO department (dept_name, location) VALUES ('Orthopaedics',     'Block B, Second Floor');
INSERT INTO department (dept_name, location) VALUES ('Dermatology',      'Block C, Ground Floor');

INSERT INTO doctor (doctor_name, dept_id, specialization, consult_fee, phone, max_daily_slots)
VALUES ('Dr. Arvind Rao',     1, 'General Physician',   400, '9840011001', 16);
INSERT INTO doctor (doctor_name, dept_id, specialization, consult_fee, phone, max_daily_slots)
VALUES ('Dr. Meera Iyer',     1, 'Family Medicine',     350, '9840011002', 12);
INSERT INTO doctor (doctor_name, dept_id, specialization, consult_fee, phone, max_daily_slots)
VALUES ('Dr. Sanjay Kulkarni',2, 'Interventional Cardiology', 900, '9840011003', 8);
INSERT INTO doctor (doctor_name, dept_id, specialization, consult_fee, phone, max_daily_slots)
VALUES ('Dr. Farah Siddiqui', 3, 'Sports Injuries',     700, '9840011004', 10);
INSERT INTO doctor (doctor_name, dept_id, specialization, consult_fee, phone, max_daily_slots)
VALUES ('Dr. Vikram Menon',   3, 'Joint Replacement',   800, '9840011005', 6);
INSERT INTO doctor (doctor_name, dept_id, specialization, consult_fee, phone, max_daily_slots)
VALUES ('Dr. Ananya Desai',   4, 'Cosmetic Dermatology',600, '9840011006', 10);

INSERT INTO patient (patient_name, dob, gender, phone, email) VALUES ('Rohan Sharma',   DATE '2001-04-12', 'M', '9000000101', 'rohan.s@example.com');
INSERT INTO patient (patient_name, dob, gender, phone, email) VALUES ('Priya Nair',     DATE '1998-09-30', 'F', '9000000102', 'priya.n@example.com');
INSERT INTO patient (patient_name, dob, gender, phone, email) VALUES ('Aditya Verma',   DATE '1975-01-05', 'M', '9000000103', NULL);
INSERT INTO patient (patient_name, dob, gender, phone, email) VALUES ('Sneha Reddy',    DATE '1989-07-21', 'F', '9000000104', 'sneha.r@example.com');
INSERT INTO patient (patient_name, dob, gender, phone, email) VALUES ('Karthik Subramanian', DATE '1962-11-02', 'M', '9000000105', NULL);
INSERT INTO patient (patient_name, dob, gender, phone, email) VALUES ('Fatima Khan',    DATE '2004-02-14', 'F', '9000000106', 'fatima.k@example.com');
INSERT INTO patient (patient_name, dob, gender, phone, email) VALUES ('Arjun Pillai',   DATE '1993-06-08', 'M', '9000000107', 'arjun.p@example.com');
INSERT INTO patient (patient_name, dob, gender, phone, email) VALUES ('Divya Joshi',    DATE '1985-12-19', 'F', '9000000108', NULL);
INSERT INTO patient (patient_name, dob, gender, phone, email) VALUES ('Nikhil Bose',    DATE '2000-03-03', 'O', '9000000109', 'nikhil.b@example.com');
INSERT INTO patient (patient_name, dob, gender, phone, email) VALUES ('Lakshmi Menon',  DATE '1958-08-25', 'F', '9000000110', NULL);

INSERT INTO medicine (med_name, unit_price, stock_qty, reorder_level) VALUES ('Paracetamol 500mg (strip)',   25.00, 200, 40);
INSERT INTO medicine (med_name, unit_price, stock_qty, reorder_level) VALUES ('Amoxicillin 250mg (strip)',   85.50, 60,  20);
INSERT INTO medicine (med_name, unit_price, stock_qty, reorder_level) VALUES ('Atorvastatin 10mg (strip)', 120.00, 15,  20);
INSERT INTO medicine (med_name, unit_price, stock_qty, reorder_level) VALUES ('Diclofenac Gel 30g',         95.00, 35,  15);
INSERT INTO medicine (med_name, unit_price, stock_qty, reorder_level) VALUES ('Cetirizine 10mg (strip)',     18.00, 150, 30);
INSERT INTO medicine (med_name, unit_price, stock_qty, reorder_level) VALUES ('Metformin 500mg (strip)',     45.00, 8,   25);
INSERT INTO medicine (med_name, unit_price, stock_qty, reorder_level) VALUES ('Calcium + Vit D3 (strip)',    110.00, 40, 20);
INSERT INTO medicine (med_name, unit_price, stock_qty, reorder_level) VALUES ('Clobetasol Cream 15g',        72.00, 5,  10);
INSERT INTO medicine (med_name, unit_price, stock_qty, reorder_level) VALUES ('ORS Sachet',                  20.00, 300, 50);
INSERT INTO medicine (med_name, unit_price, stock_qty, reorder_level) VALUES ('Pantoprazole 40mg (strip)',   65.00, 90,  20);
COMMIT;

-- Historical + today's + future appointments.
-- The date-validation trigger is disabled ONLY while loading historical data,
-- exactly as one would during a data migration, and re-enabled afterwards.
ALTER TRIGGER trg_appt_validate DISABLE;

DECLARE
  -- past dates are plain offsets; future dates skip Sundays
  dm7 DATE := TRUNC(SYSDATE) - 7;  dm6 DATE := TRUNC(SYSDATE) - 6;
  dm5 DATE := TRUNC(SYSDATE) - 5;  dm4 DATE := TRUNC(SYSDATE) - 4;
  dm3 DATE := TRUNC(SYSDATE) - 3;  dm2 DATE := TRUNC(SYSDATE) - 2;
  dm1 DATE := TRUNC(SYSDATE) - 1;  d0  DATE := TRUNC(SYSDATE);
  dp2 DATE := TRUNC(SYSDATE) + 2 +
              CASE WHEN TO_CHAR(TRUNC(SYSDATE) + 2, 'DY', 'NLS_DATE_LANGUAGE=ENGLISH') = 'SUN'
                   THEN 1 ELSE 0 END;
  dp3 DATE := TRUNC(SYSDATE) + 3 +
              CASE WHEN TO_CHAR(TRUNC(SYSDATE) + 3, 'DY', 'NLS_DATE_LANGUAGE=ENGLISH') = 'SUN'
                   THEN 1 ELSE 0 END;
BEGIN
  -- past, completed visits (appt_id 1..6)
  INSERT INTO appointment (patient_id, doctor_id, appt_date, slot_no, status) VALUES (1, 1, dm7, 2, 'COMPLETED');
  INSERT INTO appointment (patient_id, doctor_id, appt_date, slot_no, status) VALUES (2, 4, dm6, 1, 'COMPLETED');
  INSERT INTO appointment (patient_id, doctor_id, appt_date, slot_no, status) VALUES (3, 3, dm5, 3, 'COMPLETED');
  INSERT INTO appointment (patient_id, doctor_id, appt_date, slot_no, status) VALUES (4, 6, dm4, 5, 'COMPLETED');
  INSERT INTO appointment (patient_id, doctor_id, appt_date, slot_no, status) VALUES (5, 5, dm3, 1, 'COMPLETED');
  INSERT INTO appointment (patient_id, doctor_id, appt_date, slot_no, status) VALUES (6, 2, dm2, 4, 'COMPLETED');
  -- past, never attended -> will become NO_SHOW (appt_id 7..8)
  INSERT INTO appointment (patient_id, doctor_id, appt_date, slot_no, status) VALUES (7, 1, dm2, 6, 'BOOKED');
  INSERT INTO appointment (patient_id, doctor_id, appt_date, slot_no, status) VALUES (8, 4, dm1, 2, 'BOOKED');
  -- today (appt_id 9..12)
  INSERT INTO appointment (patient_id, doctor_id, appt_date, slot_no, status) VALUES (9,  1, d0, 1, 'BOOKED');
  INSERT INTO appointment (patient_id, doctor_id, appt_date, slot_no, status) VALUES (10, 1, d0, 2, 'BOOKED');
  INSERT INTO appointment (patient_id, doctor_id, appt_date, slot_no, status) VALUES (2,  3, d0, 4, 'BOOKED');
  INSERT INTO appointment (patient_id, doctor_id, appt_date, slot_no, status) VALUES (5,  6, d0, 3, 'BOOKED');
  -- future (appt_id 13..15)
  INSERT INTO appointment (patient_id, doctor_id, appt_date, slot_no, status) VALUES (1, 3, dp2, 1, 'BOOKED');
  INSERT INTO appointment (patient_id, doctor_id, appt_date, slot_no, status) VALUES (4, 5, dp3, 2, 'BOOKED');
  INSERT INTO appointment (patient_id, doctor_id, appt_date, slot_no, status) VALUES (6, 1, dp3, 5, 'BOOKED');
  COMMIT;
END;
/

ALTER TRIGGER trg_appt_validate ENABLE;

-- Prescriptions for completed visits (trigger trg_prescription_stock reduces stock)
INSERT INTO prescription VALUES (1, 1, 2, '1-0-1 after food, 5 days');
INSERT INTO prescription VALUES (1, 5, 1, '0-0-1, 5 days');
INSERT INTO prescription VALUES (2, 4, 1, 'Apply twice daily');
INSERT INTO prescription VALUES (2, 7, 2, '1-0-0, 30 days');
INSERT INTO prescription VALUES (3, 3, 3, '0-0-1, 90 days');
INSERT INTO prescription VALUES (4, 8, 1, 'Apply at night, 14 days');
INSERT INTO prescription VALUES (5, 7, 2, '1-0-0, 60 days');
INSERT INTO prescription VALUES (5, 1, 1, 'SOS for pain');
COMMIT;

-- Bills for appointments 1..5 (6 is left unbilled for the demo); bills 1-3 paid
DECLARE
  v_bill bill.bill_id%TYPE;
BEGIN
  FOR i IN 1 .. 5 LOOP
    pkg_billing.generate_bill(i, v_bill);
    IF i <= 3 THEN
      pkg_billing.mark_paid(v_bill);
    END IF;
  END LOOP;
  DBMS_OUTPUT.PUT_LINE('Seed data loaded.');
END;
/

SELECT 'department' AS tbl, COUNT(*) AS cnt FROM department UNION ALL
SELECT 'doctor',      COUNT(*) FROM doctor      UNION ALL
SELECT 'patient',     COUNT(*) FROM patient     UNION ALL
SELECT 'appointment', COUNT(*) FROM appointment UNION ALL
SELECT 'medicine',    COUNT(*) FROM medicine    UNION ALL
SELECT 'prescription',COUNT(*) FROM prescription UNION ALL
SELECT 'bill',        COUNT(*) FROM bill        UNION ALL
SELECT 'appt_audit',  COUNT(*) FROM appt_audit;
