'use strict';
/**
 * EMI maths and input validation. Kept free of Express and MongoDB so it can
 * be unit-tested on its own.
 *
 *   EMI = P * r * (1 + r)^n / ((1 + r)^n - 1)
 *   P = principal, r = annual rate / 12 / 100, n = number of months
 */

const LIMITS = {
  principal: { min: 0, max: 1e10 },   // strictly > 0
  rate: { min: 0, max: 100 },         // annual %, strictly > 0
  months: { min: 1, max: 600 },       // whole months, 1..600 (50 years)
};

const round2 = (x) => Math.round((x + Number.EPSILON) * 100) / 100;

/** Accepts numbers or numeric strings (JSON or form-encoded bodies). */
function toNumber(v) {
  if (typeof v === 'number') return v;
  if (typeof v === 'string' && v.trim() !== '' && /^[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?$/.test(v.trim())) {
    return Number(v.trim());
  }
  return NaN;
}

/** Returns { ok: true, value: {principal, rate, months} } or { ok: false, errors: [...] }. */
function validateInput(body) {
  const errors = [];
  const b = body || {};
  const principal = toNumber(b.principal);
  const rate = toNumber(b.rate);
  const months = toNumber(b.months);

  if (!Number.isFinite(principal) || principal <= LIMITS.principal.min || principal > LIMITS.principal.max) {
    errors.push('principal must be a positive number up to 10,000,000,000');
  }
  if (!Number.isFinite(rate) || rate <= LIMITS.rate.min || rate > LIMITS.rate.max) {
    errors.push('rate must be a positive annual percentage up to 100');
  }
  if (!Number.isInteger(months) || months < LIMITS.months.min || months > LIMITS.months.max) {
    errors.push('months must be a whole number from 1 to 600');
  }
  return errors.length ? { ok: false, errors } : { ok: true, value: { principal, rate, months } };
}

function computeEmi(principal, annualRate, months) {
  const r = annualRate / 12 / 100;
  const growth = Math.pow(1 + r, months);
  const emi = (principal * r * growth) / (growth - 1);
  const totalPayment = emi * months;
  return {
    emi: round2(emi),
    totalPayment: round2(totalPayment),
    totalInterest: round2(totalPayment - principal),
  };
}

module.exports = { validateInput, computeEmi, round2, LIMITS };
