const test = require('node:test');
const assert = require('node:assert/strict');
const { planMpesaCheckout } = require('../dist/src/common/mpesa-checkout.js');

test('manual M-Pesa receipt records the received partial amount as settled', () => {
  assert.deepEqual(
    planMpesaCheckout({ receiptNumber: 'QAB123XYZ', requestedPaidCents: 1250, totalCents: 3000, mode: 'disabled' }),
    { manual: true, pending: false, paymentAmountCents: 1250, salePaidCents: 1250 },
  );
});

test('manual M-Pesa rejects zero and amounts above the sale total', () => {
  assert.equal(planMpesaCheckout({ receiptNumber: 'QAB123XYZ', requestedPaidCents: 0, totalCents: 3000 }).error, 'receipt_amount_required');
  assert.equal(planMpesaCheckout({ receiptNumber: 'QAB123XYZ', requestedPaidCents: 3001, totalCents: 3000 }).error, 'amount_exceeds_total');
});

test('mock M-Pesa remains pending for the full requested amount', () => {
  assert.deepEqual(
    planMpesaCheckout({ requestedPaidCents: 3000, totalCents: 3000, mode: 'mock' }),
    { manual: false, pending: true, paymentAmountCents: 3000, salePaidCents: 0 },
  );
});

test('mock M-Pesa remains disabled unless mock mode is explicitly enabled', () => {
  assert.equal(planMpesaCheckout({ requestedPaidCents: 3000, totalCents: 3000, mode: 'disabled' }).error, 'mock_disabled');
  assert.equal(planMpesaCheckout({ requestedPaidCents: 2000, totalCents: 3000, mode: 'mock' }).error, 'mock_requires_full_amount');
});
