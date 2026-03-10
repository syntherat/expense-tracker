import cors from "cors";
import express from "express";
import session from "express-session";
import passport from "passport";
import connectPgSimple from "connect-pg-simple";
import { env } from "./config/env.js";
import { pool } from "./db/pool.js";
import { authRouter } from "./routes/auth.js";
import { groupsRouter } from "./routes/groups.js";
import { expensesRouter } from "./routes/expenses.js";
import { uploadsRouter } from "./routes/uploads.js";
import { invitesRouter } from "./routes/invites.js";

const PgSession = connectPgSimple(session);

export const app = express();

app.use(
  cors({
    origin: env.CLIENT_ORIGIN,
    credentials: true
  })
);

app.use(express.json({ limit: "20mb" }));

app.use(
  session({
    name: env.SESSION_COOKIE_NAME,
    store: new PgSession({
      pool,
      tableName: "user_sessions",
      createTableIfMissing: false
    }),
    secret: env.SESSION_SECRET,
    resave: false,
    saveUninitialized: false,
    rolling: true,
    cookie: {
      maxAge: 30 * 24 * 60 * 60 * 1000,
      sameSite: "lax",
      secure: env.NODE_ENV === "production",
      httpOnly: true
    }
  })
);

app.use(passport.initialize());
app.use(passport.session());

app.get("/health", (_req, res) => {
  res.json({ ok: true });
});

app.use("/api/auth", authRouter);
app.use("/api/invites", invitesRouter);
app.use("/api/groups", groupsRouter);
app.use("/api", expensesRouter);
app.use("/api/uploads", uploadsRouter);

app.use((err: Error, _req: express.Request, res: express.Response, _next: express.NextFunction) => {
  console.error(err);
  res.status(500).json({ message: "Internal server error" });
});
