'use strict';
// Unit tests for the EMI maths and validation (no network, no database).
const assert = require('assert');
const { computeEmi, validateInput } = require('../emi');

// Assignment's sample: P = 500000, 12% a year, 24 months.
const r = computeEmi(500000, 12, 24);
assert.strictEqual(r.emi, 23536.74);
assert.strictEqual(r.totalPayment, 564881.67);
assert.strictEqual(r.totalInterest, 64881.67);

// Textbook check: 100000 at 10% for 12 months -> 8791.59
assert.strictEqual(computeEmi(100000, 10, 12).emi, 8791.59);

assert.ok(validateInput({ principal: 500000, rate: 12, months: 24 }).ok);
assert.ok(validateInput({ principal: '500000', rate: '12.5', months: '24' }).ok); // form-encoded strings
for (const bad of [
  {}, { principal: -1, rate: 12, months: 24 }, { principal: 0, rate: 12, months: 24 },
  { principal: 1000, rate: 0, months: 24 }, { principal: 1000, rate: 12, months: 2.5 },
  { principal: 'abc', rate: 12, months: 24 }, { principal: 1000, rate: 101, months: 24 },
  { principal: 1000, rate: 12, months: 601 }, { principal: '', rate: 12, months: 24 },
]) {
  assert.ok(!validateInput(bad).ok, 'should reject ' + JSON.stringify(bad));
}
console.log('unit tests passed: EMI(500000, 12%, 24) =', r);
