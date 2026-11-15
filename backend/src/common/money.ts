/** Integer cent helpers for transaction decisions and rounding. Database columns remain NUMERIC. */
export const cents = (value: unknown): number =>
  Math.round(Number(value ?? 0) * 100);

export const money = (valueInCents: number): number =>
  Math.round(valueInCents) / 100;

export const quantityMilli = (value: unknown): number =>
  Math.round(Number(value ?? 0) * 1000);

export const multiplyUnitCents = (unitPrice: unknown, quantity: unknown): number =>
  Math.round((cents(unitPrice) * quantityMilli(quantity)) / 1000);
