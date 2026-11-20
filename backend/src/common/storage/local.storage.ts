import { Injectable } from "@nestjs/common";
import { mkdir, unlink, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { randomUUID } from "node:crypto";
import { StorageProvider, UploadedFile } from "./storage.interface";

@Injectable()
export class LocalStorageProvider implements StorageProvider {
  private readonly baseDir: string;
  private readonly baseUrl: string;

  constructor() {
    this.baseDir = process.env.UPLOAD_DIR ?? "uploads";
    this.baseUrl = process.env.UPLOAD_BASE_URL ?? "/uploads";
  }

  async upload(file: UploadedFile, key?: string): Promise<{ url: string; key: string }> {
    const storageKey = key ?? `${randomUUID()}.${this.extension(file.mimetype)}`;
    const directory = join(this.baseDir, "products");
    await mkdir(directory, { recursive: true });
    const fullPath = join(directory, storageKey);
    await writeFile(fullPath, file.buffer, { flag: "wx" });
    return {
      url: `${this.baseUrl}/products/${storageKey}`,
      key: storageKey,
    };
  }

  async delete(key: string): Promise<void> {
    const fullPath = join(this.baseDir, "products", key);
    await unlink(fullPath).catch(() => undefined);
  }

  getUrl(key: string): string {
    return `${this.baseUrl}/products/${key}`;
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
