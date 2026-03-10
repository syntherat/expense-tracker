import { pool } from "../db/pool.js";

export async function getGroupBalances(groupId: string) {
  const result = await pool.query(
    `
      WITH paid AS (
        SELECT ep.user_id, COALESCE(SUM(ep.amount_cents), 0) AS paid_cents
        FROM expense_payers ep
        JOIN expenses e ON e.id = ep.expense_id
        WHERE e.group_id = $1
        GROUP BY ep.user_id
      ),
      owed AS (
        SELECT es.user_id, COALESCE(SUM(es.amount_cents), 0) AS owed_cents
        FROM expense_splits es
        JOIN expenses e ON e.id = es.expense_id
        WHERE e.group_id = $1
        GROUP BY es.user_id
      )
      SELECT
        u.id AS user_id,
        u.full_name,
        u.phone,
        COALESCE(p.paid_cents, 0) AS paid_cents,
        COALESCE(o.owed_cents, 0) AS owed_cents,
        COALESCE(p.paid_cents, 0) - COALESCE(o.owed_cents, 0) AS net_cents
      FROM group_members gm
      JOIN users u ON u.id = gm.user_id
      LEFT JOIN paid p ON p.user_id = u.id
      LEFT JOIN owed o ON o.user_id = u.id
      WHERE gm.group_id = $1
      ORDER BY u.full_name ASC;
    `,
    [groupId]
  );

  return result.rows;
}
