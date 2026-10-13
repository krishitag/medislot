// Oracle connection pool + small helpers.
// node-oracledb 6 runs in "thin" mode by default: pure JavaScript,
// no Oracle Instant Client needed (works natively on Apple Silicon).
import oracledb from "oracledb";

oracledb.outFormat = oracledb.OUT_FORMAT_OBJECT;
oracledb.autoCommit = false; // procedures COMMIT themselves; plain DML is committed explicitly

let pool;

export async function initPool() {
  pool = await oracledb.createPool({
    user: process.env.DB_USER,
    password: process.env.DB_PASSWORD,
    connectString: process.env.DB_CONNECT_STRING,
    poolMin: 1,
    poolMax: 5,
    poolIncrement: 1,
  });
  return pool;
}

export async function closePool() {
  if (pool) await pool.close(5);
}

const lowerKeys = (row) =>
  Object.fromEntries(Object.entries(row).map(([k, v]) => [k.toLowerCase(), v]));

/** Run a SELECT and return rows with lower-case keys. */
export async function query(sql, binds = {}) {
  const conn = await pool.getConnection();
  try {
    const res = await conn.execute(sql, binds);
    return res.rows.map(lowerKeys);
  } finally {
    await conn.close();
  }
}

/** Run a PL/SQL block or DML (with OUT binds) and commit. */
export async function exec(sql, binds = {}) {
  const conn = await pool.getConnection();
  try {
    const res = await conn.execute(sql, binds);
    await conn.commit();
    return res;
  } catch (err) {
    await conn.rollback().catch(() => {});
    throw err;
  } finally {
    await conn.close();
  }
}

export { oracledb };
