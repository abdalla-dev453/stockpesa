import { Injectable, Logger } from "@nestjs/common";
import { S3Client, PutObjectCommand, DeleteObjectCommand, GetObjectCommand } from "@aws-sdk/client-s3";
import { getSignedUrl } from "@aws-sdk/s3-request-presigner";
import { randomUUID } from "node:crypto";
import { StorageProvider, UploadedFile } from "./storage.interface";

@Injectable()
export class S3StorageProvider implements StorageProvider {
  private readonly logger = new Logger(S3StorageProvider.name);
  private readonly s3: S3Client;
  private readonly bucket: string;
  private readonly region: string;
  private readonly baseUrl?: string;

  constructor() {
    this.bucket = process.env.S3_BUCKET ?? "stockpesa-uploads";
    this.region = process.env.S3_REGION ?? "us-east-1";
    this.baseUrl = process.env.S3_BASE_URL;

    this.s3 = new S3Client({
      region: this.region,
      endpoint: process.env.S3_ENDPOINT, // for MinIO
      forcePathStyle: !!process.env.S3_FORCE_PATH_STYLE,
      credentials: {
        accessKeyId: process.env.S3_ACCESS_KEY_ID ?? "",
        secretAccessKey: process.env.S3_SECRET_ACCESS_KEY ?? "",
      },
    });
  }

  async upload(file: UploadedFile, key?: string): Promise<{ url: string; key: string }> {
    const storageKey = key ?? `products/${randomUUID()}.${this.extension(file.mimetype)}`;
    await this.s3.send(
      new PutObjectCommand({
        Bucket: this.bucket,
        Key: storageKey,
        Body: file.buffer,
        ContentType: file.mimetype,
        ContentDisposition: `inline; filename="${file.originalname}"`,
      }),
    );
    const url = this.baseUrl ? `${this.baseUrl}/${storageKey}` : await this.getSignedUrl(storageKey);
    return { url, key: storageKey };
  }

  async delete(key: string): Promise<void> {
    await this.s3.send(
      new DeleteObjectCommand({
        Bucket: this.bucket,
        Key: key.startsWith("products/") ? key : `products/${key}`,
      }),
    ).catch((err) => this.logger.warn(`Failed to delete S3 object ${key}: ${err.message}`));
  }

  getUrl(key: string): string {
    const fullKey = key.startsWith("products/") ? key : `products/${key}`;
    if (this.baseUrl) return `${this.baseUrl}/${fullKey}`;
    return `https://${this.bucket}.s3.${this.region}.amazonaws.com/${fullKey}`;
  }

  private async getSignedUrl(key: string): Promise<string> {
    const command = new GetObjectCommand({ Bucket: this.bucket, Key: key });
    return getSignedUrl(this.s3, command, { expiresIn: 3600 });
  }

  private extension(mimetype: string): string {
    const map: Record<string, string> = {
      "image/jpeg": "jpg",
      "image/png": "png",
      "image/webp": "webp",
    };
    return map[mimetype] ?? "jpg";
  }
}
