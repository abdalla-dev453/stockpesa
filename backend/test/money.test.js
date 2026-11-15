const test = require('node:test');
const assert = require('node:assert/strict');
const { cents, money, multiplyUnitCents, quantityMilli } = require('../dist/src/common/money.js');

test('money decisions round to integer cents', () => {
  assert.equal(cents(0.1 + 0.2), 30);
  assert.equal(money(123456), 1234.56);
});

test('unit price multiplied by fractional quantity rounds once to cents', () => {
  assert.equal(multiplyUnitCents(19.99, 1.5), 2999);
  assert.equal(quantityMilli(0.125), 125);
});

test('negative adjustments retain sign at cent precision', () => {
  assert.equal(cents(-0.01), -1);
});
