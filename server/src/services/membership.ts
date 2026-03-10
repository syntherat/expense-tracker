import { pool } from "../db/pool.js";

export async function ensureGroupMembership(groupId: string, userId: string) {
  const membership = await pool.query(
    "SELECT 1 FROM group_members WHERE group_id = $1 AND user_id = $2",
    [groupId, userId]
  );

  return Boolean(membership.rowCount);
}
