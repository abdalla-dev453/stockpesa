import { Module } from "@nestjs/common";
import { APP_FILTER } from "@nestjs/core";
import { JwtModule } from "@nestjs/jwt";
import { AuthModule } from "./auth/auth.module";
import { SalesModule } from "./sales/sales.module";
import { StockModule } from "./stock/stock.module";
import { CatalogModule } from "./catalog/catalog.module";
import { BusinessModule } from "./business/business.module";
import { CustomersModule } from "./customers/customers.module";
import { StockCountsModule } from "./stock-counts/stock-counts.module";
import { InsightsModule } from "./insights/insights.module";
import { PaymentsModule } from "./payments/payments.module";
import { DbModule } from "./prisma.service";
import { PrismaFilter } from "./common/filters";
import { HealthModule } from "./health/health.module";
@Module({
  imports: [
    DbModule,
    JwtModule.register({ global: true }),
    AuthModule,
    SalesModule,
    StockModule,
    CatalogModule,
    BusinessModule,
    CustomersModule,
    StockCountsModule,
    InsightsModule,
    PaymentsModule,
    HealthModule,
  ],
  providers: [{ provide: APP_FILTER, useClass: PrismaFilter }],
})
export class AppModule {}
