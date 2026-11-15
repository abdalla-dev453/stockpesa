export type MpesaCheckoutPlan = {
  manual: boolean;
  pending: boolean;
  paymentAmountCents: number;
  salePaidCents: number;
  error?: "receipt_amount_required" | "amount_exceeds_total" | "mock_disabled" | "mock_requires_full_amount";
};

/** Resolves manual receipt recording versus mock pending checkout in integer cents. */
export function planMpesaCheckout(input: {
  receiptNumber?: string;
  requestedPaidCents: number;
  totalCents: number;
  mode?: string;
}): MpesaCheckoutPlan {
  const manual = !!input.receiptNumber?.trim();
  if (manual) {
    if (input.requestedPaidCents <= 0) {
      return { manual: true, pending: false, paymentAmountCents: 0, salePaidCents: 0, error: "receipt_amount_required" };
    }
    if (input.requestedPaidCents > input.totalCents) {
      return { manual: true, pending: false, paymentAmountCents: 0, salePaidCents: 0, error: "amount_exceeds_total" };
    }
    return {
      manual: true,
      pending: false,
      paymentAmountCents: input.requestedPaidCents,
      salePaidCents: input.requestedPaidCents,
    };
  }

  if (input.mode !== "mock") {
    return { manual: false, pending: true, paymentAmountCents: 0, salePaidCents: 0, error: "mock_disabled" };
  }
  if (input.requestedPaidCents !== input.totalCents) {
    return { manual: false, pending: true, paymentAmountCents: 0, salePaidCents: 0, error: "mock_requires_full_amount" };
  }
  return {
    manual: false,
    pending: true,
    paymentAmountCents: input.totalCents,
    salePaidCents: 0,
  };
}
