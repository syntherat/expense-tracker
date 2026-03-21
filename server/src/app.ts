import cors from "cors";
import compression from "compression";
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

// Needed on platforms like Render/Heroku where TLS terminates at a proxy.
app.set("trust proxy", 1);

app.use(
  cors({
    // Reflect the caller's Origin header so credentialed requests work from any origin.
    origin: true,
    credentials: true
  })
);

app.use(express.json({ limit: "20mb" }));
app.use(compression());

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
    proxy: env.NODE_ENV === "production",
    cookie: {
      maxAge: 30 * 24 * 60 * 60 * 1000,
      sameSite: env.NODE_ENV === "production" ? "none" : "lax",
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

app.get("/invite/:token", (req, res) => {
  const token = String(req.params.token ?? "").trim();
  if (!token) {
    return res.status(400).send("Invalid invite link");
  }

  const encodedToken = encodeURIComponent(token);
  const deepLink = `expensetracker://invite/${encodedToken}`;
  const webFallback = `${env.CLIENT_ORIGIN.replace(/\/+$/, "")}/invite/${encodedToken}`;
  const apiPreview = `/api/invites/${encodedToken}`;

  return res
    .status(200)
    .set("Content-Type", "text/html; charset=utf-8")
    .send(`<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Open Invite</title>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, Segoe UI, Roboto, sans-serif; margin: 0; background: #0f1720; color: #e6edf3; }
    .wrap { min-height: 100vh; display: grid; place-items: center; padding: 24px; }
    .card { width: 100%; max-width: 460px; border-radius: 16px; background: #18232d; border: 1px solid #2a3946; padding: 20px; }
    .title { font-size: 22px; font-weight: 700; margin-bottom: 8px; }
    .muted { color: #9fb2c0; margin-bottom: 16px; }
    .btn { display: inline-block; background: #27d3b5; color: #032028; text-decoration: none; font-weight: 700; border-radius: 10px; padding: 12px 14px; margin-right: 8px; }
    .btn.secondary { background: transparent; color: #e6edf3; border: 1px solid #3a4c5b; }
    .small { margin-top: 12px; color: #8ea3b2; font-size: 13px; }
  </style>
</head>
<body>
  <div class="wrap">
    <div class="card">
      <div class="title">Opening group invite</div>
      <div class="muted">If the app is installed, it should open automatically.</div>
      <a class="btn" href="${deepLink}">Open App</a>
      <a class="btn secondary" href="${webFallback}">Continue in Browser</a>
      <div class="small" id="status">Checking invite...</div>
    </div>
  </div>
  <script>
    (function () {
      var token = ${JSON.stringify(token)};
      var deepLink = ${JSON.stringify(deepLink)};
      var webFallback = ${JSON.stringify(webFallback)};
      var apiPreview = ${JSON.stringify(apiPreview)};
      var statusEl = document.getElementById('status');
      var ua = navigator.userAgent || '';
      var isMobile = /Android|iPhone|iPad|iPod/i.test(ua);

      fetch(apiPreview).then(function (res) {
        if (!res.ok) throw new Error('Invite not found');
        return res.json();
      }).then(function (payload) {
        var invite = payload && payload.invite;
        if (!invite || !invite.isActive || invite.isExpired) {
          statusEl.textContent = 'This invite is inactive or expired.';
          return;
        }

        if (!isMobile) {
          statusEl.textContent = 'Desktop detected. Continue in browser.';
          return;
        }

        statusEl.textContent = 'Opening app...';
        setTimeout(function () {
          window.location.href = deepLink;
        }, 120);

        setTimeout(function () {
          window.location.href = webFallback;
        }, 1800);
      }).catch(function () {
        statusEl.textContent = 'Invite is invalid. Please ask for a new link.';
      });
    })();
  </script>
</body>
</html>`);
});

app.use("/api/auth", authRouter);
app.use("/api/invites", invitesRouter);
app.use("/api/groups", groupsRouter);
app.use("/api", expensesRouter);
app.use("/api/uploads", uploadsRouter);

// Error handling middleware - must be last
app.use((err: Error, _req: express.Request, res: express.Response, _next: express.NextFunction) => {
  console.error("Unhandled error:", err);
  
  // Check if headers have already been sent
  if (res.headersSent) {
    return;
  }
  
  // Default to 500 error
  const statusCode = (err as any).status || 500;
  const message = err.message || "Internal server error";
  
  res.status(statusCode).json({
    message: process.env.NODE_ENV === "production" 
      ? "An error occurred processing your request" 
      : message
  });
});
