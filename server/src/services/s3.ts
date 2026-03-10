import { randomUUID } from "node:crypto";
import { GetObjectCommand, S3Client, PutObjectCommand } from "@aws-sdk/client-s3";
import { getSignedUrl } from "@aws-sdk/s3-request-presigner";
import { env } from "../config/env.js";

function assertS3Enabled() {
  const hasAllS3Values =
    Boolean(env.AWS_REGION) &&
    Boolean(env.AWS_S3_BUCKET) &&
    Boolean(env.AWS_ACCESS_KEY_ID) &&
    Boolean(env.AWS_SECRET_ACCESS_KEY) &&
    Boolean(env.AWS_S3_PUBLIC_BASE_URL);

  if (!env.S3_ENABLED || !hasAllS3Values) {
    throw new Error("S3 uploads are disabled. Set S3_ENABLED=true and provide all AWS_* env vars.");
  }
}

function getS3Client() {
  return new S3Client({
    region: env.AWS_REGION,
    credentials: {
      accessKeyId: env.AWS_ACCESS_KEY_ID,
      secretAccessKey: env.AWS_SECRET_ACCESS_KEY
    }
  });
}

export async function uploadFileToS3(
  buffer: Buffer,
  originalFileName: string,
  mimeType: string,
  groupId: string
): Promise<{ key: string; fileUrl: string }> {
  assertS3Enabled();

  const safeName = originalFileName.replace(/[^a-zA-Z0-9._-]/g, "_");
  const key = `groups/${groupId}/${randomUUID()}-${safeName}`;

  await getS3Client().send(new PutObjectCommand({
    Bucket: env.AWS_S3_BUCKET,
    Key: key,
    ContentType: mimeType,
    Body: buffer,
  }));

  const fileUrl = `${env.AWS_S3_PUBLIC_BASE_URL}/${key}`;
  return { key, fileUrl };
}

export async function createPresignedUpload(
  originalFileName: string,
  mimeType: string,
  groupId: string
) {
  assertS3Enabled();

  const safeName = originalFileName.replace(/[^a-zA-Z0-9._-]/g, "_");
  const key = `groups/${groupId}/${randomUUID()}-${safeName}`;

  const command = new PutObjectCommand({
    Bucket: env.AWS_S3_BUCKET,
    Key: key,
    ContentType: mimeType
  });

  const uploadUrl = await getSignedUrl(getS3Client(), command, { expiresIn: 300 });
  const fileUrl = `${env.AWS_S3_PUBLIC_BASE_URL}/${key}`;

  return { key, uploadUrl, fileUrl };
}

export async function getSignedDownloadUrl(
  key: string,
  expiresInSeconds = 15 * 60
): Promise<string> {
  assertS3Enabled();

  const command = new GetObjectCommand({
    Bucket: env.AWS_S3_BUCKET,
    Key: key
  });

  return getSignedUrl(getS3Client(), command, { expiresIn: expiresInSeconds });
}
