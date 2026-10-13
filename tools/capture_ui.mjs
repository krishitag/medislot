// Captures the front-end figures for the report from the running app.
// Needs: API on :4000, Vite on :5173, and a FRESH database (tools/db.sh reset).
//   cd tools && npm install && npx playwright install chromium && node capture_ui.mjs
import { chromium } from "playwright";
import { mkdirSync } from "node:fs";

const BASE = process.env.BASE_URL ?? "http://localhost:5173";
const OUT = new URL("../screenshots/", import.meta.url).pathname;
mkdirSync(OUT, { recursive: true });

const ymd = (d) => d.toLocaleDateString("en-CA"); // YYYY-MM-DD, local time
const addDays = (n) => { const d = new Date(); d.setDate(d.getDate() + n); return d; };
const nextSunday = () => { let n = 1; while (addDays(n).getDay() !== 0) n++; return ymd(addDays(n)); };
const nextWorkday = () => ymd(addDays(addDays(1).getDay() === 0 ? 2 : 1));

const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1280, height: 800 }, deviceScaleFactor: 2 });

async function open(path, readyText) {
  await page.goto(BASE + path);
  await page.waitForLoadState("networkidle");
  if (readyText) await page.getByText(readyText).first().waitFor();
}
async function shot(name) {
  await page.waitForLoadState("networkidle");
  await page.screenshot({ path: OUT + name, fullPage: true });
  console.log("saved screenshots/" + name);
}

try {
  // Fig 5.1 Dashboard
  await open("/", "Dr. Arvind Rao");
  await shot("fig_5_1.png");

  // Fig 5.5 Pharmacy (low-stock rows carry a REORDER badge)
  await open("/pharmacy", "REORDER");
  await shot("fig_5_5.png");

  // Fig B.1 Patients with outstanding dues
  await open("/patients", "Aditya Verma");
  await shot("fig_b_1.png");

  // Fig 5.2 Booking form: a real Sunday booking rejected by trigger trg_appt_validate
  await open("/book", "Book appointment");
  await page.locator("select").nth(0).locator("option").first().waitFor({ state: "attached" });
  await page.locator("select").nth(0).selectOption("3");
  await page.locator("select").nth(1).selectOption("2");
  await page.locator('input[type="date"]').fill(nextSunday());
  await page.locator('input[type="number"]').fill("3");
  await page.getByRole("button", { name: /Book/ }).click();
  await page.locator(".flash.err").waitFor();
  await shot("fig_5_2.png");

  // ...then one valid booking (the next working day)
  await page.locator('input[type="date"]').fill(nextWorkday());
  await page.getByRole("button", { name: /Book/ }).click();
  await page.waitForURL(/\/appointments\/\d+$/);
  await page.locator(".flash.ok").waitFor();
  await shot("fig_5_2_valid.png");

  // Fig 5.3 Appointments list
  await open("/appointments", "Nikhil Bose");
  await shot("fig_5_3.png");

  // Fig 5.4 Appointment #6 (completed, unbilled in the seed): prescribe -> bill -> pay
  await open("/appointments/6", "Appointment #6");
  if (!(await page.getByRole("button", { name: /Generate bill/ }).isVisible())) {
    throw new Error("Appointment 6 is already billed - reset the database (tools/db.sh reset) and re-run.");
  }
  await page.locator("form select").selectOption("1"); // Paracetamol 500mg
  await page.locator('form input[type="number"]').fill("2");
  await page.getByPlaceholder("1-0-1 after food, 5 days").fill("1-0-1 after food, 5 days");
  await page.getByRole("button", { name: "Add medicine" }).click();
  await page.getByText("Medicine added").waitFor();
  await page.getByRole("button", { name: /Generate bill/ }).click();
  await page.getByRole("button", { name: "Record payment" }).waitFor();
  await page.getByRole("button", { name: "Record payment" }).click();
  await page.getByText(/marked PAID/).waitFor();
  await shot("fig_5_4.png");

  // Fig B.2 Audit log
  await open("/audit", "COMPLETED");
  await shot("fig_b_2.png");
} catch (err) {
  console.error("\nCAPTURE FAILED:", err.message);
  await page.screenshot({ path: OUT + "capture_error.png", fullPage: true });
  console.error("Page at the time of failure: screenshots/capture_error.png");
  process.exitCode = 1;
} finally {
  await browser.close();
}
