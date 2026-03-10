import { NextFunction, Request, Response, Router } from "express";
import passport from "passport";
import { Strategy as LocalStrategy } from "passport-local";
import { env } from "../config/env.js";
import { pool } from "../db/pool.js";
import { requireAuth } from "../middleware/auth.js";

export const authRouter = Router();

passport.use(
  new LocalStrategy(
    {
      usernameField: "phone",
      passwordField: "name",
      session: true
    },
    async (phone: string, name: string, done: (error: Error | null, user?: Express.User | false, options?: { message: string }) => void) => {
      try {
        const userResult = await pool.query(
          "SELECT id, full_name, phone FROM users WHERE phone = $1 LIMIT 1",
          [phone.trim()]
        );

        if (!userResult.rowCount) {
          return done(null, false, { message: "User not found" });
        }

        const user = userResult.rows[0];
        if (user.full_name.toLowerCase() !== name.trim().toLowerCase()) {
          return done(null, false, { message: "Name and phone do not match" });
        }

        return done(null, user);
      } catch (error) {
        return done(error as Error);
      }
    }
  )
);

passport.serializeUser((user: Express.User, done) => {
  done(null, user.id);
});

passport.deserializeUser(async (id: string, done) => {
  try {
    const userResult = await pool.query(
      "SELECT id, full_name, phone FROM users WHERE id = $1 LIMIT 1",
      [id]
    );

    if (!userResult.rowCount) {
      return done(null, false);
    }

    return done(null, userResult.rows[0]);
  } catch (error) {
    return done(error as Error);
  }
});

authRouter.post("/login", (req: Request, res: Response, next: NextFunction) => {
  passport.authenticate("local", (err: Error | null, user: Express.User | false) => {
    if (err) {
      return next(err);
    }

    if (!user) {
      return res.status(401).json({ message: "Invalid name or phone" });
    }

    req.logIn(user, (loginErr) => {
      if (loginErr) {
        return next(loginErr);
      }

      return res.json({ user });
    });
  })(req, res, next);
});

authRouter.post("/logout", requireAuth, (req: Request, res: Response, next: NextFunction) => {
  req.logout((err) => {
    if (err) {
      return next(err);
    }

    req.session.destroy((destroyErr) => {
      if (destroyErr) {
        return next(destroyErr);
      }

      res.clearCookie(env.SESSION_COOKIE_NAME);
      return res.status(204).send();
    });
  });
});

authRouter.get("/me", requireAuth, (req: Request, res: Response) => {
  res.json({ user: req.user });
});
