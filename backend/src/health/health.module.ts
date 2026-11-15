import { Controller, Get, Module, ServiceUnavailableException } from "@nestjs/common";
import { PrismaService } from "../prisma.service";

@Controller("health")
class HealthController {
  constructor(private readonly db: PrismaService) {}

  @Get()
  async get() {
    try {
      await this.db.$queryRaw`SELECT 1`;
      return { status: "ok", database: "ok" };
    } catch {
      throw new ServiceUnavailableException({ status: "unavailable", database: "unavailable" });
    }
  }
}

@Module({ controllers: [HealthController] })
export class HealthModule {}
