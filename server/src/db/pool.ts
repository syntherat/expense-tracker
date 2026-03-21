import pg from "pg";
import { env } from "../config/env.js";

const { Pool } = pg;

export const pool = new Pool({
  connectionString: env.DATABASE_URL,
  ssl: { rejectUnauthorized: false },
  // Connection pool optimization for handling traffic spikes
  max: 20,                          // Maximum number of connections
  min: 2,                           // Minimum number of connections to keep
  idleTimeoutMillis: 30000,         // Close idle connections after 30s
  connectionTimeoutMillis: 10000,   // Timeout for acquiring a connection
  allowExitOnIdle: true             // Allow process to exit when pool is idle
});
