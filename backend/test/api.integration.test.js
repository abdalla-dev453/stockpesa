const test = require('node:test');
const assert = require('node:assert/strict');
const { createHmac } = require('node:crypto');

const databaseUrl = process.env.DATABASE_URL_TEST;

test('API integration: tenant boundary, stock idempotency, sale, and M-Pesa flows', {
  skip: !databaseUrl,
}, async () => {
  const parsed = new URL(databaseUrl);
  if (!/test/i.test(parsed.pathname)) {
    throw new Error('DATABASE_URL_TEST must point to a database whose name contains "test"');
  }

  process.env.DATABASE_URL = databaseUrl;
  process.env.NODE_ENV = 'test';
  process.env.MPESA_MODE = 'mock';
  process.env.JWT_ACCESS_SECRET = 'integration-test-access-secret-which-is-long-enough';
  process.env.JWT_REFRESH_SECRET = 'integration-test-refresh-secret-which-is-long-enough';
  process.env.MPESA_CALLBACK_SECRET = 'integration-test-mpesa-callback-secret';

  require('reflect-metadata');
  const { ValidationPipe } = require('@nestjs/common');
  const { NestFactory } = require('@nestjs/core');
  const { AppModule } = require('../dist/src/app.module.js');
  const { PrismaService } = require('../dist/src/prisma.service.js');
  const app = await NestFactory.create(AppModule, { logger: false });
  app.getHttpAdapter().getInstance().use((req, _res, next) => {
    if (req.url === '/api/v1' || req.url.startsWith('/api/v1/')) req.url = req.url.slice(7) || '/';
    next();
  });
  app.useGlobalPipes(new ValidationPipe({ whitelist: true, transform: true, forbidNonWhitelisted: true }));
  await app.listen(0, '127.0.0.1');
  const address = app.getHttpServer().address();
  const origin = `http://127.0.0.1:${address.port}`;
  const businessIds = [];

  const call = async (path, options = {}) => {
    const headers = { 'content-type': 'application/json', ...(options.token ? { authorization: `Bearer ${options.token}` } : {}), ...(options.key ? { 'idempotency-key': options.key } : {}), ...(options.headers ?? {}) };
    const response = await fetch(`${origin}${path}`, {
      method: options.method ?? 'GET',
      headers,
      ...(options.body === undefined ? {} : { body: JSON.stringify(options.body) }),
    });
    const data = await response.json();
    return { status: response.status, data };
  };
  const confirmCsv = async (token, csv) => {
    const form = new FormData();
    form.append('file', new Blob([csv], { type: 'text/csv' }), 'retry-safe.csv');
    const response = await fetch(`${origin}/products/import/confirm`, {
      method: 'POST',
      headers: { authorization: `Bearer ${token}` },
      body: form,
    });
    return { status: response.status, data: await response.json() };
  };
  const register = async (label) => {
    const suffix = `${Date.now()}${Math.floor(Math.random() * 100000)}`;
    const result = await call('/auth/register', {
      method: 'POST',
      body: {
        businessName: `Integration Shop ${label}`,
        businessType: 'retail shop',
        fullName: `Integration Owner ${label}`,
        phone: `07${suffix.slice(-8)}`,
        email: `integration-${label}-${suffix}@example.test`,
        password: 'Integration123!',
      },
    });
    assert.equal(result.status, 201);
    businessIds.push(result.data.user.businessId);
    return result.data.accessToken;
  };

  try {
    const ownerA = await register('a');
    const ownerB = await register('b');
    const productA = await call('/products', {
      method: 'POST', token: ownerA,
      body: { name: 'Integration Item A', sku: 'INT-A', unit: 'piece', buyingPrice: 5, sellingPrice: 10, minStock: 1 },
    });
    const productB = await call('/products', {
      method: 'POST', token: ownerB,
      body: { name: 'Integration Item B', sku: 'INT-B', unit: 'piece', buyingPrice: 5, sellingPrice: 10, minStock: 1 },
    });
    assert.equal(productA.status, 201);
    assert.equal(productB.status, 201);

    const csv = 'name,selling_price,unit\nCSV No SKU,12.50,piece\n';
    const importFirst = await confirmCsv(ownerA, csv);
    const importRetry = await confirmCsv(ownerA, csv);
    assert.equal(importFirst.status, 201);
    assert.equal(importFirst.data.created, 1);
    assert.equal(importFirst.data.replayed, false);
    assert.equal(importRetry.status, 201);
    assert.equal(importRetry.data.created, 1);
    assert.equal(importRetry.data.replayed, true);

    const cashierCreate = await call('/users', {
      method: 'POST', token: ownerA,
      body: {
        fullName: 'Integration Cashier', email: `cashier-${Date.now()}@example.test`,
        phone: `07${String(Date.now()).slice(-8)}`, password: 'Cashier123!', role: 'CASHIER',
      },
    });
    assert.equal(cashierCreate.status, 201);
    const cashierLogin = await call('/auth/login', {
      method: 'POST', body: { identifier: cashierCreate.data.email, password: 'Cashier123!' },
    });
    assert.equal(cashierLogin.status, 201);
    assert.equal((await call('/products', {
      method: 'POST', token: cashierLogin.data.accessToken,
      body: { name: 'Forbidden Item', unit: 'piece', buyingPrice: 1, sellingPrice: 2 },
    })).status, 403);

    const intake = { productId: productA.data.id, quantity: 3, unitCost: 5 };
    assert.equal((await call('/stock/intake', { method: 'POST', token: ownerA, key: 'intake-once', body: intake })).status, 201);
    const intakeReplay = await call('/stock/intake', { method: 'POST', token: ownerA, key: 'intake-once', body: intake });
    assert.equal(intakeReplay.status, 201);
    assert.equal((await call('/api/v1/products', { token: ownerA })).status, 200);

    const convertedProduct = await call('/products', {
      method: 'POST', token: ownerA,
      body: { name: 'Conversion Item', sku: 'CONV-ITEM', unit: 'piece', buyingPrice: 80, sellingPrice: 120 },
    });
    assert.equal(convertedProduct.status, 201);
    const cartonRule = await call('/unit-conversions', {
      method: 'POST', token: ownerA,
      body: { productId: convertedProduct.data.id, fromUnit: 'carton', toUnit: 'piece', multiplier: 24 },
    });
    assert.equal(cartonRule.status, 201);
    assert.equal((await call('/unit-conversions', { token: ownerB, })).data.length, 0);
    assert.equal((await call('/unit-conversions', {
      method: 'POST', token: cashierLogin.data.accessToken,
      body: { productId: convertedProduct.data.id, fromUnit: 'carton', toUnit: 'piece', multiplier: 24 },
    })).status, 403);
    assert.equal((await call('/unit-conversions', {
      method: 'POST', token: ownerA,
      body: { productId: convertedProduct.data.id, fromUnit: 'piece', toUnit: 'carton', multiplier: 0.041667 },
    })).status, 409);
    const cartonIntake = { productId: convertedProduct.data.id, quantity: 2, unit: 'carton', unitCost: 1920 };
    assert.equal((await call('/stock/intake', { method: 'POST', token: ownerA, key: 'carton-intake', body: cartonIntake })).status, 201);
    assert.equal((await call('/stock/intake', { method: 'POST', token: ownerA, key: 'carton-intake', body: cartonIntake })).data.replayed, true);
    assert.equal((await call('/stock/intake', { method: 'POST', token: ownerA, key: 'carton-intake', body: { ...cartonIntake, quantity: 3 } })).status, 409);
    const convertedStock = await call(`/products/${convertedProduct.data.id}`, { token: ownerA });
    assert.equal(Number(convertedStock.data.quantity), 48);
    assert.equal(Number(convertedStock.data.buyingPrice), 80);
    const cartonSaleBody = { items: [{ productId: convertedProduct.data.id, quantity: 1, unit: 'carton' }], method: 'CASH', amountPaid: 2880 };
    const cartonSale = await call('/sales', { method: 'POST', token: ownerA, key: 'carton-sale', body: cartonSaleBody });
    assert.equal(cartonSale.status, 201);
    assert.equal(Number(cartonSale.data.items[0].unitPrice), 2880);
    assert.equal(cartonSale.data.items[0].unit, 'carton');
    assert.equal(Number(cartonSale.data.items[0].stockQuantity), 24);
    assert.equal((await call('/sales', { method: 'POST', token: ownerA, key: 'carton-sale', body: cartonSaleBody })).data.id, cartonSale.data.id);
    assert.equal(Number((await call(`/products/${convertedProduct.data.id}`, { token: ownerA })).data.quantity), 24);
    const conversionProductReport = await call('/reports/products', { token: ownerA });
    const conversionProductRow = conversionProductReport.data.find((row) => row.product.id === convertedProduct.data.id);
    assert.equal(Number(conversionProductRow.quantitySold), 24);
    assert.equal(conversionProductRow.product.unit, 'piece');
    assert.equal(Number(conversionProductRow.revenue), 2880);
    assert.equal((await call(`/products/${convertedProduct.data.id}`, { method: 'PATCH', token: ownerA, body: { status: 'DISCONTINUED' } })).status, 200);
    assert.equal((await call('/sales', { method: 'POST', token: ownerA, key: 'discontinued-sale', body: cartonSaleBody })).status, 400);
    assert.equal((await call(`/products/${convertedProduct.data.id}`, { method: 'PATCH', token: ownerA, body: { status: 'ACTIVE' } })).status, 200);
    const cartonReturn = await call(`/sales/${cartonSale.data.id}/returns`, {
      method: 'POST', token: ownerA, key: 'carton-return',
      body: { items: [{ saleItemId: cartonSale.data.items[0].id, quantity: 1 }], reason: 'Conversion test', refundAmount: 2880, restock: true },
    });
    assert.equal(cartonReturn.status, 201);
    assert.equal(Number((await call(`/products/${convertedProduct.data.id}`, { token: ownerA })).data.quantity), 48);
    assert.equal(await app.get(PrismaService).productPriceHistory.count({ where: { businessId: businessIds[0], productId: convertedProduct.data.id } }), 1);

    const variantParent = await call('/products', {
      method: 'POST', token: ownerA,
      body: { name: 'Variant Oil', unit: 'piece', buyingPrice: 20, sellingPrice: 30 },
    });
    assert.equal(variantParent.status, 201);
    const variant = await call(`/products/${variantParent.data.id}/variants`, {
      method: 'POST', token: ownerA,
      body: { name: '500ml', attributes: { size: '500ml' }, sku: 'VAR-OIL-500', unit: 'bottle', buyingPrice: 10, sellingPrice: 15, minStock: 2 },
    });
    assert.equal(variant.status, 201);
    const variantIntake = await call(`/product-variants/${variant.data.id}/stock`, {
      method: 'POST', token: ownerA, key: 'variant-intake-once', body: { quantity: 3, unitCost: 10 },
    });
    assert.equal(variantIntake.status, 201);
    assert.equal((await call(`/product-variants/${variant.data.id}/stock`, {
      method: 'POST', token: ownerA, key: 'variant-intake-once', body: { quantity: 3, unitCost: 10 },
    })).data.replayed, true);
    const secondVariantParent = await call('/products', {
      method: 'POST', token: ownerA,
      body: { name: 'Second Variant Parent', unit: 'piece', buyingPrice: 1, sellingPrice: 2 },
    });
    const secondVariant = await call(`/products/${secondVariantParent.data.id}/variants`, {
      method: 'POST', token: ownerA,
      body: { name: 'Second', attributes: { size: 'second' }, unit: 'piece', buyingPrice: 1, sellingPrice: 2 },
    });
    assert.equal((await call(`/product-variants/${secondVariant.data.id}/stock`, {
      method: 'POST', token: ownerA, key: 'variant-intake-once', body: { quantity: 3, unitCost: 10 },
    })).status, 409);
    const variantSale = await call('/sales', {
      method: 'POST', token: ownerA, key: 'variant-sale-once',
      body: { items: [{ variantId: variant.data.id, quantity: 1 }], method: 'CASH', amountPaid: 15 },
    });
    assert.equal(variantSale.status, 201);
    assert.equal(variantSale.data.items[0].variantId, variant.data.id);
    assert.equal(Number((await call(`/product-variants/${variant.data.id}`, { token: ownerA })).data.quantity), 2);
    const variantLowStock = await call('/reports/low-stock', { token: ownerA });
    assert.ok(variantLowStock.data.data.some((row) => row.variantId === variant.data.id && row.unit === 'bottle' && Number(row.quantity) === 2));
    const variantMarket = await call('/reports/market-insights', { token: ownerA });
    assert.equal(variantMarket.status, 200);
    assert.ok(variantMarket.data.bestSellers.some((row) => row.variantId === variant.data.id && row.unit === 'bottle' && Number(row.quantitySold) === 1));
    assert.equal((await call('/reports/stock-summary', { token: ownerA })).status, 200);
    assert.equal((await call(`/product-variants/${variant.data.id}`, { method: 'PATCH', token: ownerA, body: { active: false } })).status, 400);
    assert.equal((await call(`/product-variants/${variant.data.id}`, { method: 'DELETE', token: ownerA })).status, 400);

    const concurrentParent = await call('/products', {
      method: 'POST', token: ownerA,
      body: { name: 'Concurrent Variant Parent', unit: 'piece', buyingPrice: 2, sellingPrice: 4 },
    });
    assert.equal((await call('/stock/intake', {
      method: 'POST', token: ownerA, key: 'concurrent-parent-intake',
      body: { productId: concurrentParent.data.id, quantity: 5, unitCost: 2 },
    })).status, 201);
    const concurrentVariants = await Promise.all(['A', 'B'].map((label) => call(`/products/${concurrentParent.data.id}/variants`, {
      method: 'POST', token: ownerA,
      body: { name: `Option ${label}`, attributes: { option: label }, unit: 'piece', buyingPrice: 2, sellingPrice: 4 },
    })));
    assert.deepEqual(concurrentVariants.map((result) => result.status), [201, 201]);
    const variantsAfterRace = await call(`/products/${concurrentParent.data.id}/variants`, { token: ownerA });
    assert.equal(variantsAfterRace.data.filter((row) => row.name === 'Standard').length, 1);
    assert.equal(variantsAfterRace.data.reduce((total, row) => total + Number(row.quantity), 0), 5);
    assert.equal(Number((await call(`/products/${concurrentParent.data.id}`, { token: ownerA })).data.quantity), 0);

    const bundleProduct = await call('/products', {
      method: 'POST', token: ownerA,
      body: { name: 'Bundle', unit: 'pack', buyingPrice: 8, sellingPrice: 12 },
    });
    const bundleSetup = await call(`/products/${bundleProduct.data.id}/bundle`, {
      method: 'PUT', token: ownerA, body: { items: [{ productId: productA.data.id, quantity: 1 }] },
    });
    assert.equal(bundleSetup.status, 200);
    const bundleSale = await call('/sales', {
      method: 'POST', token: ownerA, key: 'bundle-sale-once',
      body: { items: [{ productId: bundleProduct.data.id, quantity: 1 }], method: 'CASH', amountPaid: 12 },
    });
    assert.equal(bundleSale.status, 201);

    const crossTenant = await call(`/products/${productA.data.id}`, { token: ownerB });
    assert.equal(crossTenant.status, 404);

    const saleBody = { items: [{ productId: productA.data.id, quantity: 1 }], method: 'CASH', amountPaid: 10 };
    const sale = await call('/sales', { method: 'POST', token: ownerA, key: 'cash-sale-once', body: saleBody });
    const saleReplay = await call('/sales', { method: 'POST', token: ownerA, key: 'cash-sale-once', body: saleBody });
    assert.equal(sale.status, 201);
    assert.equal(saleReplay.status, 201);
    assert.equal(sale.data.id, saleReplay.data.id);
    const receiptAsCashier = await call(`/sales/${sale.data.id}`, { token: cashierLogin.data.accessToken });
    assert.equal(receiptAsCashier.status, 200);
    assert.equal(receiptAsCashier.data.cashierName, 'Integration Owner a');
    assert.equal((await call(`/sales/${sale.data.id}`, { token: ownerB })).status, 404);
    const oversell = await call('/sales', {
      method: 'POST', token: ownerA, key: 'oversell-failure',
      body: { items: [{ productId: productA.data.id, quantity: 99 }], method: 'CASH', amountPaid: 10 },
    });
    assert.equal(oversell.status, 400);
    assert.equal(Number((await app.get(PrismaService).stockLevel.findUnique({ where: { productId: productA.data.id } })).quantity), 1);

    const customer = await call('/customers', {
      method: 'POST', token: ownerA,
      body: { name: 'Integration Customer', creditLimit: 100 },
    });
    assert.equal(customer.status, 201);
    const manualMpesa = await call('/sales', {
      method: 'POST', token: ownerA, key: 'manual-mpesa-once',
      body: {
        items: [{ productId: productA.data.id, quantity: 1 }],
        method: 'MPESA', amountPaid: 5, customerId: customer.data.id,
        mpesaReceiptNumber: 'QAB123XYZ',
      },
    });
    assert.equal(manualMpesa.status, 201);
    assert.equal(manualMpesa.data.status, 'partially_paid');
    assert.equal(Number(manualMpesa.data.payments[0].amount), 5);
    assert.equal(manualMpesa.data.payments[0].reference, 'QAB123XYZ');
    const duplicateReceipt = await call('/sales', {
      method: 'POST', token: ownerA, key: 'duplicate-mpesa-reference',
      body: { items: [{ productId: productA.data.id, quantity: 1 }], method: 'MPESA', amountPaid: 5, customerId: customer.data.id, mpesaReceiptNumber: 'qab123xyz' },
    });
    assert.equal(duplicateReceipt.status, 409);
    const customerPayment = await call(`/customers/${customer.data.id}/payments`, {
      method: 'POST', token: ownerA, key: 'customer-payment-once',
      body: { saleId: manualMpesa.data.id, amount: 2, method: 'CASH' },
    });
    assert.equal(customerPayment.status, 201);
    assert.equal(Number((await call(`/customers/${customer.data.id}`, { token: ownerA })).data.balance), 3);

    const mpesaSale = await call('/sales', {
      method: 'POST', token: ownerA, key: 'mock-mpesa-once',
      body: { items: [{ productId: productA.data.id, quantity: 1 }], method: 'MPESA', amountPaid: 10 },
    });
    assert.equal(mpesaSale.status, 201);
    assert.equal(mpesaSale.data.status, 'payment_pending');
    const pendingPayment = mpesaSale.data.payments[0];
    const badSignature = await call('/payments/mpesa/callback', {
      method: 'POST',
      headers: { 'x-mpesa-signature': '0'.repeat(64) },
      body: { checkoutRequestId: pendingPayment.checkoutRequestId, resultCode: 0, receiptNumber: 'ATTACK123' },
    });
    assert.equal(badSignature.status, 403);
    const confirmed = await call(`/payments/mpesa/mock/${pendingPayment.id}/confirm`, { method: 'POST', token: ownerA, body: {} });
    assert.equal(confirmed.status, 201);
    assert.equal(confirmed.data.status, 'PAID');
    const callbackPayload = {
      checkoutRequestId: pendingPayment.checkoutRequestId,
      resultCode: 0,
      receiptNumber: `MOCK-${pendingPayment.id.slice(0, 8).toUpperCase()}`,
    };
    const signature = createHmac('sha256', process.env.MPESA_CALLBACK_SECRET)
      .update(`${callbackPayload.checkoutRequestId}.${callbackPayload.resultCode}.${callbackPayload.receiptNumber}`)
      .digest('hex');
    const paymentReplay = await call('/payments/mpesa/callback', {
      method: 'POST',
      headers: { 'x-mpesa-signature': signature },
      body: callbackPayload,
    });
    assert.equal(paymentReplay.status, 201);
    assert.equal(paymentReplay.data.replayed, true);

    const returned = await call(`/sales/${manualMpesa.data.id}/returns`, {
      method: 'POST', token: ownerA, key: 'manual-mpesa-return',
      body: { items: [{ saleItemId: manualMpesa.data.items[0].id, quantity: 1 }], reason: 'Integration return', refundAmount: 7, restock: true },
    });
    assert.equal(returned.status, 201);
    assert.equal(Number((await call(`/customers/${customer.data.id}`, { token: ownerA })).data.balance), 0);

    const db = app.get(PrismaService);
    const stock = await db.stockLevel.findUnique({ where: { productId: productA.data.id } });
    assert.equal(Number(stock.quantity), 1);
    assert.equal(await db.stockMovement.count({ where: { businessId: businessIds[0], productId: productA.data.id, type: 'purchase_in' } }), 1);
    assert.equal(await db.sale.count({ where: { businessId: businessIds[0], idempotencyKey: 'cash-sale-once' } }), 1);
    assert.equal(await db.product.count({ where: { businessId: businessIds[0], name: 'CSV No SKU' } }), 1);
    assert.equal(await db.auditLog.count({ where: { businessId: businessIds[0], action: 'stock.intake', entityId: productA.data.id } }), 1);
    assert.equal(await db.stockMovement.count({ where: { businessId: businessIds[0], productId: productA.data.id, type: 'return_in' } }), 1);
    assert.equal(Number((await db.customer.findUnique({ where: { id: customer.data.id } })).balance), 0);
  } finally {
    const db = app.get(PrismaService);
    for (const businessId of businessIds) {
      await db.auditLog.deleteMany({ where: { businessId } });
      await db.alert.deleteMany({ where: { businessId } });
      await db.stockMovement.deleteMany({ where: { businessId } });
      await db.stockCountItem.deleteMany({ where: { count: { is: { businessId } } } });
      await db.stockCount.deleteMany({ where: { businessId } });
      await db.returnItem.deleteMany({ where: { return: { is: { businessId } } } });
      await db.returnRecord.deleteMany({ where: { businessId } });
      await db.payment.deleteMany({ where: { businessId } });
      await db.receipt.deleteMany({ where: { businessId } });
      await db.saleItem.deleteMany({ where: { businessId } });
      await db.sale.deleteMany({ where: { businessId } });
      await db.bundleItem.deleteMany({ where: { businessId } });
      await db.productBundle.deleteMany({ where: { businessId } });
      await db.productImage.deleteMany({ where: { businessId } });
      await db.productTagAssignment.deleteMany({ where: { businessId } });
      await db.productTag.deleteMany({ where: { businessId } });
      await db.unitConversion.deleteMany({ where: { businessId } });
      await db.productPriceHistory.deleteMany({ where: { businessId } });
      await db.variantStockMovement.deleteMany({ where: { businessId } });
      await db.productVariant.deleteMany({ where: { businessId } });
      await db.stockLevel.deleteMany({ where: { businessId } });
      await db.product.deleteMany({ where: { businessId } });
      await db.category.deleteMany({ where: { businessId } });
      await db.customer.deleteMany({ where: { businessId } });
      await db.user.deleteMany({ where: { businessId } });
      await db.business.deleteMany({ where: { id: businessId } });
    }
    await app.close();
  }
});
