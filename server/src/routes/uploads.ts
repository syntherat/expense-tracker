import { Router } from "express";
import { z } from "zod";
import { requireAuth } from "../middleware/auth.js";
import { createPresignedUpload, uploadFileToS3 } from "../services/s3.js";
import { ensureGroupMembership } from "../services/membership.js";

export const uploadsRouter = Router();
uploadsRouter.use(requireAuth);

uploadsRouter.post("/presign", async (req, res) => {
  const schema = z.object({
    groupId: z.string().uuid(),
    fileName: z.string().min(1),
    mimeType: z.string().min(1)
  });

  const parsed = schema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ message: parsed.error.flatten() });
  }

  const isMember = await ensureGroupMembership(parsed.data.groupId, req.user!.id);
  if (!isMember) {
    return res.status(403).json({ message: "Not a group member" });
  }

  let signed;
  try {
    signed = await createPresignedUpload(
      parsed.data.fileName,
      parsed.data.mimeType,
      parsed.data.groupId
    );
  } catch (error) {
    return res.status(503).json({
      message: (error as Error).message
    });
  }

  return res.json(signed);
});

uploadsRouter.post("/upload", async (req, res) => {
  const schema = z.object({
    groupId: z.string().uuid(),
    fileName: z.string().min(1),
    mimeType: z.string().min(1),
    data: z.string().min(1), // base64-encoded file bytes
  });

  const parsed = schema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ message: parsed.error.flatten() });
  }

  const isMember = await ensureGroupMembership(parsed.data.groupId, req.user!.id);
  if (!isMember) {
    return res.status(403).json({ message: "Not a group member" });
  }

  try {
    const buffer = Buffer.from(parsed.data.data, "base64");
    const result = await uploadFileToS3(
      buffer,
      parsed.data.fileName,
      parsed.data.mimeType,
      parsed.data.groupId
    );
    return res.json({ ...result, sizeBytes: buffer.length });
  } catch (error) {
    return res.status(503).json({ message: (error as Error).message });
  }
});
