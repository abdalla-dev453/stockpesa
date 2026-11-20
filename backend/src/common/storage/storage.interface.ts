export interface UploadedFile {
  buffer: Buffer;
  mimetype: string;
  originalname: string;
  size: number;
}

export interface StorageProvider {
  upload(file: UploadedFile, key?: string): Promise<{ url: string; key: string }>;
  delete(key: string): Promise<void>;
  getUrl(key: string): string;
}
