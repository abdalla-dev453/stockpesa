import { Module, Global } from "@nestjs/common";
import { STORAGE_PROVIDER } from "./storage.token";
import { StorageProvider } from "./storage.interface";
import { LocalStorageProvider } from "./local.storage";
import { S3StorageProvider } from "./s3.storage";

@Global()
@Module({
  providers: [
    {
      provide: STORAGE_PROVIDER,
      useClass:
        process.env.STORAGE_DRIVER === "s3" || process.env.S3_BUCKET
          ? S3StorageProvider
          : LocalStorageProvider,
    },
  ],
  exports: [STORAGE_PROVIDER],
})
export class StorageModule {}
