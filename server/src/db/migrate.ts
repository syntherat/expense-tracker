import fs from "node:fs";
import path from "node:path";
import { pool } from "./pool.js";

const migrationsDir = path.resolve(process.cwd(), "migrations");

async function runMigrations() {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS schema_migrations (
      id SERIAL PRIMARY KEY,
      file_name TEXT NOT NULL UNIQUE,
      executed_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );
  `);

  const files = fs
    .readdirSync(migrationsDir)
    .filter((file: string) => file.endsWith(".sql"))
    .sort();

  for (const file of files) {
    const exists = await pool.query(
      "SELECT 1 FROM schema_migrations WHERE file_name = $1",
      [file]
    );

    if (exists.rowCount) {
      continue;
    }

    const sql = fs.readFileSync(path.join(migrationsDir, file), "utf8");
    const client = await pool.connect();

    try {
      await client.query("BEGIN");
      await client.query(sql);
      await client.query(
        "INSERT INTO schema_migrations(file_name) VALUES ($1)",
        [file]
      );
      await client.query("COMMIT");
      console.log(`Applied migration: ${file}`);
    } catch (error) {
      await client.query("ROLLBACK");
      throw error;
    } finally {
      client.release();
    }
  }

  await pool.end();
}

runMigrations().catch((error) => {
  console.error("Migration failed", error);
  process.exit(1);
});
