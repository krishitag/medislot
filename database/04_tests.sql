-- =============================================================
-- MediSlot : 04_tests.sql  --  test cases TC01 .. TC22
-- Run on a FRESH load (01 -> 02 -> 03 -> 04).  Run Script (F5).
-- Screenshot each TC's block of output from the Script Output /
-- DBMS Output pane for Section 6 of the report.
-- =============================================================
SET SERVEROUTPUT ON
SET FEEDBACK OFF

-- helper: next working (non-Sunday) day >= today + n
CREATE OR REPLACE FUNCTION fn_test_day (n NUMBER) RETURN DATE IS
  d DATE := TRUNC(SYSDATE) + n;
BEGIN
  IF TO_CHAR(d, 'DY', 'NLS_DATE_LANGUAGE=ENGLISH') = 'SUN' THEN d := d + 1; END IF;
  RETURN d;
END;
/

PROMPT ===== TC01  Book a valid appointment =====
DECLARE v_id NUMBER;
BEGIN
  pr_book_appointment(3, 2, fn_test_day(1), 3, v_id);
  DBMS_OUTPUT.PUT_LINE('PASS: booked appointment id ' || v_id);
EXCEPTION WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('FAIL: ' || SQLERRM);
END;
/

PROMPT ===== TC02  Double-book an occupied doctor slot =====
DECLARE v_id NUMBER;
BEGIN
  pr_book_appointment(7, 1, fn_test_day(3), 5, v_id);   -- slot held by appt 15
  DBMS_OUTPUT.PUT_LINE('FAIL: booking was accepted');
EXCEPTION WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('PASS (rejected): ' || SQLERRM);
END;
/

PROMPT ===== TC03  Book for a past date (trigger T1) =====
DECLARE v_id NUMBER;
BEGIN
  pr_book_appointment(3, 1, TRUNC(SYSDATE) - 1, 9, v_id);
  DBMS_OUTPUT.PUT_LINE('FAIL: booking was accepted');
EXCEPTION WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('PASS (rejected): ' || SQLERRM);
END;
/

PROMPT ===== TC04  Book on a Sunday (trigger T1) =====
DECLARE v_id NUMBER;
BEGIN
  pr_book_appointment(3, 1, TRUNC(SYSDATE, 'IW') + 13, 9, v_id);   -- a future Sunday
  DBMS_OUTPUT.PUT_LINE('FAIL: booking was accepted');
EXCEPTION WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('PASS (rejected): ' || SQLERRM);
END;
/

PROMPT ===== TC05  Slot number beyond doctor's daily capacity =====
DECLARE v_id NUMBER;
BEGIN
  pr_book_appointment(3, 5, fn_test_day(1), 8, v_id);   -- Dr. Menon works 6 slots
  DBMS_OUTPUT.PUT_LINE('FAIL: booking was accepted');
EXCEPTION WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('PASS (rejected): ' || SQLERRM);
END;
/

PROMPT ===== TC06  Patient already busy in that slot (other doctor) =====
DECLARE v_id NUMBER;
BEGIN
  pr_book_appointment(1, 2, fn_test_day(2), 1, v_id);   -- patient 1 has slot 1 with doctor 3
  DBMS_OUTPUT.PUT_LINE('FAIL: booking was accepted');
EXCEPTION WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('PASS (rejected): ' || SQLERRM);
END;
/

PROMPT ===== TC07  CHECK constraint on gender =====
BEGIN
  INSERT INTO patient (patient_name, dob, gender, phone) VALUES ('Test User', DATE '2000-01-01', 'X', '9111111111');
  DBMS_OUTPUT.PUT_LINE('FAIL: row inserted');
  ROLLBACK;
EXCEPTION WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('PASS (rejected): ' || SQLERRM);
END;
/

PROMPT ===== TC08  UNIQUE constraint on patient phone =====
BEGIN
  INSERT INTO patient (patient_name, dob, gender, phone) VALUES ('Duplicate', DATE '2000-01-01', 'M', '9000000101');
  DBMS_OUTPUT.PUT_LINE('FAIL: row inserted');
  ROLLBACK;
EXCEPTION WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('PASS (rejected): ' || SQLERRM);
END;
/

PROMPT ===== TC09  FOREIGN KEY: non-existent doctor =====
BEGIN
  INSERT INTO appointment (patient_id, doctor_id, appt_date, slot_no) VALUES (1, 99, fn_test_day(1), 1);
  DBMS_OUTPUT.PUT_LINE('FAIL: row inserted');
  ROLLBACK;
EXCEPTION WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('PASS (rejected): ' || SQLERRM);
END;
/

PROMPT ===== TC10  Cancel, then re-book the freed slot =====
DECLARE v_id NUMBER;
BEGIN
  pr_cancel_appointment(15);
  DBMS_OUTPUT.PUT_LINE('Appointment 15 cancelled');
  pr_book_appointment(7, 1, fn_test_day(3), 5, v_id);
  DBMS_OUTPUT.PUT_LINE('PASS: freed slot re-booked as appointment ' || v_id);
EXCEPTION WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('FAIL: ' || SQLERRM);
END;
/

PROMPT ===== TC11  Re-open a CANCELLED appointment (trigger T2) =====
BEGIN
  UPDATE appointment SET status = 'BOOKED' WHERE appt_id = 15;
  DBMS_OUTPUT.PUT_LINE('FAIL: status changed');
  ROLLBACK;
EXCEPTION WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('PASS (rejected): ' || SQLERRM);
END;
/

PROMPT ===== TC12  Complete a future appointment (trigger T2) =====
BEGIN
  pr_complete_appointment(13);
  DBMS_OUTPUT.PUT_LINE('FAIL: completed');
EXCEPTION WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('PASS (rejected): ' || SQLERRM);
END;
/

PROMPT ===== TC13  Prescribe before the visit is completed (trigger T4) =====
BEGIN
  INSERT INTO prescription VALUES (9, 1, 1, '1-0-1');
  DBMS_OUTPUT.PUT_LINE('FAIL: prescription accepted');
  ROLLBACK;
EXCEPTION WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('PASS (rejected): ' || SQLERRM);
END;
/

PROMPT ===== TC14  Complete visit, prescribe, stock auto-decrements (trigger T4) =====
DECLARE v_before NUMBER; v_after NUMBER;
BEGIN
  pr_complete_appointment(9);
  SELECT stock_qty INTO v_before FROM medicine WHERE med_id = 1;
  INSERT INTO prescription VALUES (9, 1, 2, '1-0-1 after food, 3 days');
  INSERT INTO prescription VALUES (9, 9, 4, 'After each loose stool');
  COMMIT;
  SELECT stock_qty INTO v_after FROM medicine WHERE med_id = 1;
  DBMS_OUTPUT.PUT_LINE('Paracetamol stock: before=' || v_before || ' after=' || v_after);
  DBMS_OUTPUT.PUT_LINE(CASE WHEN v_before - v_after = 2 THEN 'PASS' ELSE 'FAIL' END);
EXCEPTION WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('FAIL: ' || SQLERRM);
END;
/

PROMPT ===== TC15  Prescribe more than available stock (trigger T4) =====
BEGIN
  INSERT INTO prescription VALUES (9, 8, 10, 'Apply daily');   -- Clobetasol has 4 left
  DBMS_OUTPUT.PUT_LINE('FAIL: prescription accepted');
  ROLLBACK;
EXCEPTION WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('PASS (rejected): ' || SQLERRM);
END;
/

PROMPT ===== TC16  Generate bill via package (pkg_billing) =====
DECLARE v_bill NUMBER;
BEGIN
  pkg_billing.generate_bill(9, v_bill);
  DBMS_OUTPUT.PUT_LINE('Bill id        : ' || v_bill);
  DBMS_OUTPUT.PUT_LINE('Medicine cost  : ' || fn_medicine_cost(9));
  DBMS_OUTPUT.PUT_LINE('Bill total     : ' || pkg_billing.bill_total(v_bill));
  -- expected: 400 + (2*25 + 4*20) + 5% of 130 = 536.50
  DBMS_OUTPUT.PUT_LINE(CASE WHEN pkg_billing.bill_total(v_bill) = 536.5 THEN 'PASS' ELSE 'FAIL' END);
EXCEPTION WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('FAIL: ' || SQLERRM);
END;
/

PROMPT ===== TC17  Bill a non-completed appointment =====
DECLARE v_bill NUMBER;
BEGIN
  pkg_billing.generate_bill(10, v_bill);
  DBMS_OUTPUT.PUT_LINE('FAIL: bill generated');
EXCEPTION WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('PASS (rejected): ' || SQLERRM);
END;
/

PROMPT ===== TC18  Generate a duplicate bill =====
DECLARE v_bill NUMBER;
BEGIN
  pkg_billing.generate_bill(9, v_bill);
  DBMS_OUTPUT.PUT_LINE('FAIL: second bill generated');
EXCEPTION WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('PASS (rejected): ' || SQLERRM);
END;
/

PROMPT ===== TC19  Edit prescription after billing (trigger T4) =====
BEGIN
  INSERT INTO prescription VALUES (9, 5, 1, '0-0-1');
  DBMS_OUTPUT.PUT_LINE('FAIL: prescription accepted');
  ROLLBACK;
EXCEPTION WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('PASS (rejected): ' || SQLERRM);
END;
/

PROMPT ===== TC20  Payment and outstanding balance =====
DECLARE v_bill NUMBER; v_pat NUMBER := 9;
BEGIN
  SELECT bill_id INTO v_bill FROM bill WHERE appt_id = 9;
  DBMS_OUTPUT.PUT_LINE('Outstanding before payment: ' || pkg_billing.patient_outstanding(v_pat));
  pkg_billing.mark_paid(v_bill);
  DBMS_OUTPUT.PUT_LINE('Outstanding after payment : ' || pkg_billing.patient_outstanding(v_pat));
  BEGIN
    pkg_billing.mark_paid(v_bill);
    DBMS_OUTPUT.PUT_LINE('FAIL: paid twice');
  EXCEPTION WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('PASS (second payment rejected): ' || SQLERRM);
  END;
END;
/

PROMPT ===== TC21  Functions: free slots and medicine cost =====
BEGIN
  DBMS_OUTPUT.PUT_LINE('Free slots, Dr. Rao today : ' || fn_available_slots(1, SYSDATE));
  DBMS_OUTPUT.PUT_LINE('Medicine cost, appt 2     : ' || fn_medicine_cost(2));
END;
/
SELECT doctor_name, fn_available_slots(doctor_id, SYSDATE) AS free_today FROM doctor ORDER BY doctor_id;

PROMPT ===== TC22  Cursors: schedule, low stock, no-shows =====
EXEC pr_doctor_schedule(1, SYSDATE);
EXEC pr_low_stock_report;
EXEC pr_mark_no_shows;
EXEC pr_mark_no_shows;

PROMPT ===== Audit trail written by trigger T3 =====
SELECT audit_id, appt_id, NVL(old_status, '-') AS old_status, new_status,
       TO_CHAR(changed_on, 'DD-MON HH24:MI:SS') AS changed_on
FROM   appt_audit
WHERE  old_status IS NOT NULL
ORDER  BY audit_id;

DROP FUNCTION fn_test_day;
SET FEEDBACK ON
