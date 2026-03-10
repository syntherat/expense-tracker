import dotenv from "dotenv";
import { z } from "zod";

dotenv.config();

const envSchema = z.object({
  PORT: z.coerce.number().default(4000),
  NODE_ENV: z.enum(["development", "production", "test"]).default("development"),
  DATABASE_URL: z.string().min(1),
  SESSION_SECRET: z.string().min(8),
  SESSION_COOKIE_NAME: z.string().default("expense.sid"),
  CLIENT_ORIGIN: z.string().default("http://localhost:3000"),
  APP_INVITE_BASE_URL: z.string().default("https://app.expensetracker.local/invite"),
  S3_ENABLED: z.coerce.boolean().default(false),
  AWS_REGION: z.string().optional().default(""),
  AWS_S3_BUCKET: z.string().optional().default(""),
  AWS_ACCESS_KEY_ID: z.string().optional().default(""),
  AWS_SECRET_ACCESS_KEY: z.string().optional().default(""),
  AWS_S3_PUBLIC_BASE_URL: z.string().optional().default("")
});

export const env = envSchema.parse(process.env);
