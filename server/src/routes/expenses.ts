import { Request, Response, Router } from "express";
import { z } from "zod";
import { pool } from "../db/pool.js";
import { requireAuth } from "../middleware/auth.js";
import { ensureGroupMembership } from "../services/membership.js";
import { getGroupBalances } from "../services/balances.js";
import { getSignedDownloadUrl } from "../services/s3.js";
import { sendPushNotifications } from "../services/onesignal.js";

export const expensesRouter = Router();
expensesRouter.use(requireAuth);

const lineItemSchema = z.object({
  userId: z.string().uuid(),
  amountCents: z.number().int().nonnegative()
});

// Maximum expense amount: 10,000,000 cents (100,000 in major currency units)
const MAX_EXPENSE_AMOUNT_CENTS = 10_000_000;

const createExpenseSchema = z.object({
  description: z.string().min(1).max(200),
  notes: z.string().max(1000).optional(),
  amountCents: z.number().int().positive().max(MAX_EXPENSE_AMOUNT_CENTS, {
    message: `Expense amount cannot exceed ${(MAX_EXPENSE_AMOUNT_CENTS / 100).toLocaleString()} in total`
  }),
  currency: z.string().length(3).default("INR"),
  expenseDate: z.string().optional(),
  payers: z.array(lineItemSchema).min(1),
  splits: z.array(lineItemSchema).min(1)
});

const sendReminderSchema = z.object({
  userIds: z.array(z.string().uuid()).optional()
});

const markPaidSchema = z.object({
  isPaid: z.boolean().default(true)
});

type AttachmentPayload = {
  id: string;
  fileName: string;
  fileKey?: string;
  fileUrl: string;
  mimeType: string;
  sizeBytes: number;
};

function toSafeAttachment(raw: unknown): AttachmentPayload | null {
  if (raw == null || typeof raw !== "object") {
    return null;
  }

  const row = raw as Record<string, unknown>;
  const id = typeof row.id === "string" ? row.id : "";
  const fileName = typeof row.fileName === "string" ? row.fileName : "";
  const fileKey = typeof row.fileKey === "string" ? row.fileKey : undefined;
  const fileUrl = typeof row.fileUrl === "string" ? row.fileUrl : "";
  const mimeType = typeof row.mimeType === "string" ? row.mimeType : "application/octet-stream";
  const sizeRaw = row.sizeBytes;
  const sizeBytes = typeof sizeRaw === "number" ? sizeRaw : Number(sizeRaw ?? 0);

  if (!id || !fileName || !fileUrl) {
    return null;
  }

  return {
    id,
    fileName,
    fileKey,
    fileUrl,
    mimeType,
    sizeBytes: Number.isFinite(sizeBytes) && sizeBytes >= 0 ? sizeBytes : 0
  };
}

async function signAttachmentUrls(rawAttachments: unknown): Promise<AttachmentPayload[]> {
  if (!Array.isArray(rawAttachments)) {
    return [];
  }

  const safe = rawAttachments
    .map((item) => toSafeAttachment(item))
    .filter((item): item is AttachmentPayload => item !== null);

  return Promise.all(
    safe.map(async (attachment) => {
      const key = attachment.fileKey ?? "";

      if (!key) {
        return attachment;
      }

      try {
        const signedUrl = await getSignedDownloadUrl(key);
        return { ...attachment, fileUrl: signedUrl };
      } catch {
        // Fall back to stored URL if signing fails.
        return attachment;
      }
    })
  );
}

async function upsertExpensePaymentStatus(
  expenseId: string,
  queryable: { query: (text: string, values?: unknown[]) => Promise<unknown> } = pool
) {
  await queryable.query(
    `
      INSERT INTO expense_payment_status (expense_id, user_id, amount_cents, is_paid)
      SELECT
        es.expense_id,
        es.user_id,
        GREATEST(es.amount_cents - COALESCE(ep.amount_cents, 0), 0) AS amount_cents,
        FALSE AS is_paid
      FROM expense_splits es
      LEFT JOIN expense_payers ep
        ON ep.expense_id = es.expense_id
       AND ep.user_id = es.user_id
      WHERE es.expense_id = $1
        AND GREATEST(es.amount_cents - COALESCE(ep.amount_cents, 0), 0) > 0
      ON CONFLICT (expense_id, user_id)
      DO UPDATE SET amount_cents = EXCLUDED.amount_cents;
    `,
    [expenseId]
  );
}

async function insertNotifications({
  userIds,
  groupId,
  expenseId,
  type,
  title,
  body,
  data,
  soundName
}: {
  userIds: string[];
  groupId: string;
  expenseId: string;
  type: string;
  title: string;
  body: string;
  data?: Record<string, unknown>;
  soundName?: string;
}) {
  if (!userIds.length) {
    return;
  }

  await pool.query(
    `
      INSERT INTO notifications (user_id, group_id, expense_id, type, title, body, data)
      SELECT
        target_user_id,
        $2::uuid,
        $3::uuid,
        $4::text,
        $5::text,
        $6::text,
        $7::jsonb
      FROM unnest($1::uuid[]) AS target_user_id;
    `,
    [userIds, groupId, expenseId, type, title, body, JSON.stringify(data ?? {})]
  );

  // Fire push notifications (non-blocking, never crashes request on failure).
  void sendPushNotifications({ userIds, title, body, data, soundName });
}

expensesRouter.post("/groups/:groupId/expenses", async (req: Request, res: Response) => {
  const parsed = createExpenseSchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ message: parsed.error.flatten() });
  }

  const { groupId } = req.params;
  const userId = req.user!.id;
  const isMember = await ensureGroupMembership(groupId, userId);
  if (!isMember) {
    return res.status(403).json({ message: "Not a group member" });
  }

  const payload = parsed.data;
  const payersTotal = payload.payers.reduce((sum: number, p: { amountCents: number }) => sum + p.amountCents, 0);
  const splitsTotal = payload.splits.reduce((sum: number, s: { amountCents: number }) => sum + s.amountCents, 0);

  if (payersTotal !== payload.amountCents || splitsTotal !== payload.amountCents) {
    return res.status(400).json({
      message: "Payers and splits must both add up to amountCents"
    });
  }

  const uniqueUserIds = new Set([
    ...payload.payers.map((p) => p.userId),
    ...payload.splits.map((s) => s.userId)
  ]);

  const members = await pool.query(
    "SELECT user_id FROM group_members WHERE group_id = $1",
    [groupId]
  );
  const memberSet = new Set(members.rows.map((row) => row.user_id));
  const notificationUserIds = members.rows
    .map((row) => row.user_id as string)
    .filter((targetUserId) => targetUserId !== userId);

  for (const targetUserId of uniqueUserIds) {
    if (!memberSet.has(targetUserId)) {
      return res.status(400).json({
        message: `User ${targetUserId} is not in the group`
      });
    }
  }

  const client = await pool.connect();

  try {
    await client.query("BEGIN");

    const expenseResult = await client.query(
      `
        INSERT INTO expenses (
          group_id,
          description,
          notes,
          amount_cents,
          currency,
          created_by,
          expense_date
        )
        VALUES ($1, $2, $3, $4, $5, $6, COALESCE($7::date, CURRENT_DATE))
        RETURNING *;
      `,
      [
        groupId,
        payload.description,
        payload.notes ?? null,
        payload.amountCents,
        payload.currency.toUpperCase(),
        userId,
        payload.expenseDate ?? null
      ]
    );

    const expense = expenseResult.rows[0];

    for (const payer of payload.payers) {
      await client.query(
        `
          INSERT INTO expense_payers (expense_id, user_id, amount_cents)
          VALUES ($1, $2, $3)
          ON CONFLICT (expense_id, user_id)
          DO UPDATE SET amount_cents = EXCLUDED.amount_cents;
        `,
        [expense.id, payer.userId, payer.amountCents]
      );
    }

    for (const split of payload.splits) {
      await client.query(
        `
          INSERT INTO expense_splits (expense_id, user_id, amount_cents)
          VALUES ($1, $2, $3)
          ON CONFLICT (expense_id, user_id)
          DO UPDATE SET amount_cents = EXCLUDED.amount_cents;
        `,
        [expense.id, split.userId, split.amountCents]
      );
    }

    await upsertExpensePaymentStatus(expense.id, client);

    await client.query("COMMIT");

    if (notificationUserIds.length) {
      try {
        await insertNotifications({
          userIds: notificationUserIds,
          groupId,
          expenseId: expense.id,
          type: "expense_created",
          title: "New expense added",
          body: `${payload.description} was added in this group.`,
          data: {
            expenseId: expense.id,
            description: payload.description,
            amountCents: payload.amountCents,
            createdBy: userId
          },
          soundName: "expense_tracker"
        });
      } catch (notificationError) {
        console.error("Failed to dispatch expense-created notifications", notificationError);
      }
    }

    return res.status(201).json({ expense });
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
});

expensesRouter.get("/groups/:groupId/expenses", async (req: Request, res: Response) => {
  const { groupId } = req.params;
  const userId = req.user!.id;
  const isMember = await ensureGroupMembership(groupId, userId);

  if (!isMember) {
    return res.status(403).json({ message: "Not a group member" });
  }

  const expensesResult = await pool.query(
    `
      SELECT
        e.id,
        e.group_id,
        e.description,
        e.notes,
        e.amount_cents,
        e.currency,
        e.created_by,
        creator.full_name AS created_by_name,
        e.expense_date,
        e.created_at,
        COALESCE(
          json_agg(
            DISTINCT jsonb_build_object(
              'id', a.id,
              'fileName', a.file_name,
              'fileKey', a.file_key,
              'fileUrl', a.file_url,
              'mimeType', a.mime_type,
              'sizeBytes', a.size_bytes
            )
          ) FILTER (WHERE a.id IS NOT NULL),
          '[]'::json
        ) AS attachments
      FROM expenses e
      JOIN users creator ON creator.id = e.created_by
      LEFT JOIN expense_attachments a ON a.expense_id = e.id
      WHERE e.group_id = $1
      GROUP BY e.id, creator.full_name
      ORDER BY e.expense_date DESC, e.created_at DESC;
    `,
    [groupId]
  );

  const expenses = await Promise.all(
    expensesResult.rows.map(async (expense) => ({
      ...expense,
      attachments: await signAttachmentUrls(expense.attachments)
    }))
  );

  return res.json({ expenses });
});

expensesRouter.get("/groups/:groupId/summary", async (req: Request, res: Response) => {
  const { groupId } = req.params;
  const userId = req.user!.id;
  const isMember = await ensureGroupMembership(groupId, userId);

  if (!isMember) {
    return res.status(403).json({ message: "Not a group member" });
  }

  const balances = await getGroupBalances(groupId);
  const me = balances.find((item) => item.user_id === userId);
  const others = balances.filter((item) => item.user_id !== userId);

  return res.json({
    me,
    others,
    status:
      Number(me?.net_cents ?? 0) > 0
        ? "group_owes_you"
        : Number(me?.net_cents ?? 0) < 0
          ? "you_owe_group"
          : "settled"
  });
});

expensesRouter.get("/expenses/:expenseId", async (req: Request, res: Response) => {
  const { expenseId } = req.params;
  const userId = req.user!.id;

  const expenseResult = await pool.query(
    `
      SELECT
        e.id,
        e.group_id,
        e.description,
        e.notes,
        e.amount_cents,
        e.currency,
        e.created_by,
        creator.full_name AS created_by_name,
        e.expense_date,
        e.created_at,
        COALESCE(
          json_agg(
            DISTINCT jsonb_build_object(
              'id', a.id,
              'fileName', a.file_name,
              'fileKey', a.file_key,
              'fileUrl', a.file_url,
              'mimeType', a.mime_type,
              'sizeBytes', a.size_bytes
            )
          ) FILTER (WHERE a.id IS NOT NULL),
          '[]'::json
        ) AS attachments
      FROM expenses e
      JOIN users creator ON creator.id = e.created_by
      LEFT JOIN expense_attachments a ON a.expense_id = e.id
      WHERE e.id = $1
      GROUP BY e.id, creator.full_name
      LIMIT 1;
    `,
    [expenseId]
  );

  if (!expenseResult.rowCount) {
    return res.status(404).json({ message: "Expense not found" });
  }

  const expense = expenseResult.rows[0];
  const isMember = await ensureGroupMembership(expense.group_id, userId);
  if (!isMember) {
    return res.status(403).json({ message: "Not a group member" });
  }

  expense.attachments = await signAttachmentUrls(expense.attachments);

  await upsertExpensePaymentStatus(expenseId);

  const [payersResult, splitsResult, pendingResult] = await Promise.all([
    pool.query(
      `
        SELECT ep.user_id, u.full_name, ep.amount_cents
        FROM expense_payers ep
        JOIN users u ON u.id = ep.user_id
        WHERE ep.expense_id = $1
        ORDER BY u.full_name ASC;
      `,
      [expenseId]
    ),
    pool.query(
      `
        SELECT es.user_id, u.full_name, es.amount_cents
        FROM expense_splits es
        JOIN users u ON u.id = es.user_id
        WHERE es.expense_id = $1
        ORDER BY u.full_name ASC;
      `,
      [expenseId]
    ),
    pool.query(
      `
        SELECT eps.user_id, u.full_name, eps.amount_cents, eps.is_paid, eps.paid_at, eps.reminder_sent_at
        FROM expense_payment_status eps
        JOIN users u ON u.id = eps.user_id
        WHERE eps.expense_id = $1
        ORDER BY u.full_name ASC;
      `,
      [expenseId]
    )
  ]);

  return res.json({
    expense,
    payers: payersResult.rows,
    splits: splitsResult.rows,
    pendingPayments: pendingResult.rows
  });
});

expensesRouter.post("/expenses/:expenseId/reminders", async (req: Request, res: Response) => {
  const parsed = sendReminderSchema.safeParse(req.body ?? {});
  if (!parsed.success) {
    return res.status(400).json({ message: parsed.error.flatten() });
  }

  const { expenseId } = req.params;
  const userId = req.user!.id;

  const expenseResult = await pool.query(
    "SELECT id, group_id, created_by, description FROM expenses WHERE id = $1 LIMIT 1",
    [expenseId]
  );

  if (!expenseResult.rowCount) {
    return res.status(404).json({ message: "Expense not found" });
  }

  const expense = expenseResult.rows[0];
  const isMember = await ensureGroupMembership(expense.group_id, userId);
  if (!isMember) {
    return res.status(403).json({ message: "Not a group member" });
  }

  if (expense.created_by !== userId) {
    return res.status(403).json({ message: "Only expense creator can send reminders" });
  }

  await upsertExpensePaymentStatus(expenseId);

  const pendingResult = await pool.query(
    `
      SELECT user_id, amount_cents
      FROM expense_payment_status
      WHERE expense_id = $1 AND is_paid = FALSE;
    `,
    [expenseId]
  );

  const pendingIds = pendingResult.rows.map((row) => row.user_id as string);
  const requestedIds = parsed.data.userIds;
  const targetIds = requestedIds == null
    ? pendingIds
    : pendingIds.filter((id) => requestedIds.includes(id));

  if (!targetIds.length) {
    return res.json({ notifiedCount: 0 });
  }

  await insertNotifications({
    userIds: targetIds,
    groupId: expense.group_id,
    expenseId,
    type: "payment_reminder",
    title: "Payment reminder",
    body: `Reminder: payment is pending for ${expense.description}.`,
    data: { expenseId },
    soundName: "expense_tracker"
  });

  await pool.query(
    `
      UPDATE expense_payment_status
      SET reminder_sent_at = NOW()
      WHERE expense_id = $1 AND user_id = ANY($2::uuid[]);
    `,
    [expenseId, targetIds]
  );

  return res.json({ notifiedCount: targetIds.length });
});

expensesRouter.delete("/expenses/:expenseId", async (req: Request, res: Response) => {
  const { expenseId } = req.params;
  const userId = req.user!.id;

  const expenseResult = await pool.query(
    `
      SELECT id, group_id, created_by
      FROM expenses
      WHERE id = $1
      LIMIT 1;
    `,
    [expenseId]
  );

  if (!expenseResult.rowCount) {
    return res.status(404).json({ message: "Expense not found" });
  }

  const expense = expenseResult.rows[0];
  const isMember = await ensureGroupMembership(expense.group_id, userId);
  if (!isMember) {
    return res.status(403).json({ message: "Not a group member" });
  }

  if (expense.created_by !== userId) {
    return res.status(403).json({ message: "Only expense creator can delete this expense" });
  }

  await pool.query("DELETE FROM expenses WHERE id = $1", [expenseId]);

  return res.status(204).send();
});

expensesRouter.post("/expenses/:expenseId/payments/:targetUserId", async (req: Request, res: Response) => {
  const parsed = markPaidSchema.safeParse(req.body ?? {});
  if (!parsed.success) {
    return res.status(400).json({ message: parsed.error.flatten() });
  }

  const { expenseId, targetUserId } = req.params;
  const userId = req.user!.id;

  const expenseResult = await pool.query(
    "SELECT id, group_id, created_by FROM expenses WHERE id = $1 LIMIT 1",
    [expenseId]
  );

  if (!expenseResult.rowCount) {
    return res.status(404).json({ message: "Expense not found" });
  }

  const expense = expenseResult.rows[0];
  const isMember = await ensureGroupMembership(expense.group_id, userId);
  if (!isMember) {
    return res.status(403).json({ message: "Not a group member" });
  }

  const canUpdate = expense.created_by === userId || targetUserId === userId;
  if (!canUpdate) {
    return res.status(403).json({ message: "Not allowed to update this payment status" });
  }

  await upsertExpensePaymentStatus(expenseId);

  const updated = await pool.query(
    `
      UPDATE expense_payment_status
      SET
        is_paid = $1,
        paid_at = CASE WHEN $1 THEN NOW() ELSE NULL END
      WHERE expense_id = $2 AND user_id = $3
      RETURNING expense_id, user_id, amount_cents, is_paid, paid_at, reminder_sent_at;
    `,
    [parsed.data.isPaid, expenseId, targetUserId]
  );

  if (!updated.rowCount) {
    return res.status(404).json({ message: "No pending payment found for this user" });
  }

  return res.json({ payment: updated.rows[0] });
});

expensesRouter.post("/expenses/:expenseId/attachments", async (req: Request, res: Response) => {
  const schema = z.object({
    fileName: z.string().min(1),
    fileKey: z.string().min(1),
    fileUrl: z.string().url(),
    mimeType: z.string().min(1),
    sizeBytes: z.number().int().nonnegative()
  });

  const parsed = schema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ message: parsed.error.flatten() });
  }

  const { expenseId } = req.params;
  const userId = req.user!.id;

  const expenseResult = await pool.query(
    "SELECT id, group_id FROM expenses WHERE id = $1 LIMIT 1",
    [expenseId]
  );

  if (!expenseResult.rowCount) {
    return res.status(404).json({ message: "Expense not found" });
  }

  const groupId = expenseResult.rows[0].group_id;
  const isMember = await ensureGroupMembership(groupId, userId);

  if (!isMember) {
    return res.status(403).json({ message: "Not a group member" });
  }

  const inserted = await pool.query(
    `
      INSERT INTO expense_attachments (
        expense_id,
        file_name,
        file_key,
        file_url,
        mime_type,
        size_bytes,
        uploaded_by
      )
      VALUES ($1, $2, $3, $4, $5, $6, $7)
      RETURNING *;
    `,
    [
      expenseId,
      parsed.data.fileName,
      parsed.data.fileKey,
      parsed.data.fileUrl,
      parsed.data.mimeType,
      parsed.data.sizeBytes,
      userId
    ]
  );

  return res.status(201).json({ attachment: inserted.rows[0] });
});
