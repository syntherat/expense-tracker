import { Request, Response, Router } from "express";
import { pool } from "../db/pool.js";

export const invitesRouter = Router();

invitesRouter.get("/:token", async (req: Request, res: Response) => {
  const { token } = req.params;

  const invite = await pool.query(
    `
      SELECT
        gi.token,
        gi.expires_at,
        gi.is_active,
        g.id AS group_id,
        g.name AS group_name,
        g.currency,
        COUNT(gm.user_id)::int AS member_count
      FROM group_invites gi
      JOIN groups g ON g.id = gi.group_id
      LEFT JOIN group_members gm ON gm.group_id = g.id
      WHERE gi.token = $1
      GROUP BY gi.token, gi.expires_at, gi.is_active, g.id, g.name, g.currency
      LIMIT 1;
    `,
    [token]
  );

  if (!invite.rowCount) {
    return res.status(404).json({ message: "Invite not found" });
  }

  const row = invite.rows[0];
  const expired = row.expires_at && new Date(row.expires_at) < new Date();

  return res.json({
    invite: {
      token: row.token,
      isActive: row.is_active,
      isExpired: Boolean(expired),
      expiresAt: row.expires_at,
      group: {
        id: row.group_id,
        name: row.group_name,
        currency: row.currency,
        memberCount: row.member_count
      }
    }
  });
});
