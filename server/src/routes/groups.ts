import { randomBytes } from "node:crypto";
import { Request, Response, Router } from "express";
import { z } from "zod";
import { env } from "../config/env.js";
import { pool } from "../db/pool.js";
import { requireAuth } from "../middleware/auth.js";
import { ensureGroupMembership } from "../services/membership.js";
import { getGroupBalances } from "../services/balances.js";

export const groupsRouter = Router();

groupsRouter.use(requireAuth);

const createGroupSchema = z.object({
  name: z.string().min(2).max(80),
  currency: z.string().min(3).max(3).default("INR")
});

const joinGroupSchema = z.object({
  inviteToken: z.string().min(10)
});

function makeInviteToken() {
  return randomBytes(16).toString("hex");
}

function makeInviteLink(token: string) {
  const base = env.APP_INVITE_BASE_URL.replace(/\/+$/, "");
  return `${base}/${token}`;
}

groupsRouter.post("/", async (req: Request, res: Response) => {
  const parsed = createGroupSchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ message: parsed.error.flatten() });
  }

  const userId = req.user!.id;
  const { name, currency } = parsed.data;
  const client = await pool.connect();

  try {
    await client.query("BEGIN");

    const groupResult = await client.query(
      `
        INSERT INTO groups (name, currency, created_by)
        VALUES ($1, $2, $3)
        RETURNING id, name, currency, created_by, created_at;
      `,
      [name, currency.toUpperCase(), userId]
    );

    const group = groupResult.rows[0];

    await client.query(
      `
        INSERT INTO group_members (group_id, user_id, role)
        VALUES ($1, $2, 'admin')
        ON CONFLICT (group_id, user_id) DO NOTHING;
      `,
      [group.id, userId]
    );

    const inviteResult = await client.query(
      `
        INSERT INTO group_invites (group_id, token, created_by, expires_at)
        VALUES ($1, $2, $3, NOW() + INTERVAL '30 days')
        RETURNING token, expires_at;
      `,
      [group.id, makeInviteToken(), userId]
    );

    await client.query("COMMIT");

    return res.status(201).json({
      group,
      invite: {
        ...inviteResult.rows[0],
        inviteLink: makeInviteLink(inviteResult.rows[0].token)
      }
    });
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
});

groupsRouter.get("/", async (req: Request, res: Response) => {
  const userId = req.user!.id;
  const groups = await pool.query(
    `
      SELECT g.id, g.name, g.currency, g.created_at
      FROM groups g
      JOIN group_members gm ON gm.group_id = g.id
      WHERE gm.user_id = $1
      ORDER BY g.created_at DESC;
    `,
    [userId]
  );

  return res.json({ groups: groups.rows });
});

groupsRouter.post("/join", async (req: Request, res: Response) => {
  const parsed = joinGroupSchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ message: parsed.error.flatten() });
  }

  const userId = req.user!.id;
  const client = await pool.connect();

  try {
    await client.query("BEGIN");

    const invite = await client.query(
      `
        SELECT id, group_id, token, expires_at, is_active
        FROM group_invites
        WHERE token = $1
        LIMIT 1;
      `,
      [parsed.data.inviteToken]
    );

    if (!invite.rowCount) {
      await client.query("ROLLBACK");
      return res.status(404).json({ message: "Invite not found" });
    }

    const row = invite.rows[0];
    const expired = row.expires_at && new Date(row.expires_at) < new Date();
    if (!row.is_active || expired) {
      await client.query("ROLLBACK");
      return res.status(400).json({ message: "Invite expired or inactive" });
    }

    await client.query(
      `
        INSERT INTO group_members (group_id, user_id, role)
        VALUES ($1, $2, 'member')
        ON CONFLICT (group_id, user_id) DO NOTHING;
      `,
      [row.group_id, userId]
    );

    await client.query(
      `
        UPDATE group_invites
        SET current_uses = current_uses + 1
        WHERE id = $1;
      `,
      [row.id]
    );

    await client.query("COMMIT");

    return res.status(201).json({ groupId: row.group_id });
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
});

groupsRouter.get("/:groupId", async (req: Request, res: Response) => {
  const { groupId } = req.params;
  const userId = req.user!.id;
  const isMember = await ensureGroupMembership(groupId, userId);

  if (!isMember) {
    return res.status(403).json({ message: "Not a group member" });
  }

  const [groupResult, membersResult, balances] = await Promise.all([
    pool.query("SELECT id, name, currency, created_at FROM groups WHERE id = $1", [groupId]),
    pool.query(
      `
        SELECT u.id, u.full_name, u.phone, gm.role, gm.joined_at
        FROM group_members gm
        JOIN users u ON u.id = gm.user_id
        WHERE gm.group_id = $1
        ORDER BY u.full_name ASC;
      `,
      [groupId]
    ),
    getGroupBalances(groupId)
  ]);

  return res.json({
    group: groupResult.rows[0],
    members: membersResult.rows,
    balances
  });
});

groupsRouter.post("/:groupId/invites", async (req: Request, res: Response) => {
  const { groupId } = req.params;
  const userId = req.user!.id;

  const member = await pool.query(
    `
      SELECT role
      FROM group_members
      WHERE group_id = $1 AND user_id = $2
      LIMIT 1;
    `,
    [groupId, userId]
  );

  if (!member.rowCount) {
    return res.status(403).json({ message: "Not a group member" });
  }

  const token = makeInviteToken();
  const invite = await pool.query(
    `
      INSERT INTO group_invites (group_id, token, created_by, expires_at)
      VALUES ($1, $2, $3, NOW() + INTERVAL '30 days')
      RETURNING token, expires_at;
    `,
    [groupId, token, userId]
  );

  return res.status(201).json({
    invite: {
      ...invite.rows[0],
      inviteLink: makeInviteLink(invite.rows[0].token)
    }
  });
});
