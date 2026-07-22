import { ageOn, validateRegistrationInput, validCpf } from "./contracts.ts";

Deno.test("validates CPF digits and rejects repeated or malformed values", () => {
  equal(validCpf("529.982.247-25"), true);
  equal(validCpf("529.982.247-24"), false);
  equal(validCpf("111.111.111-11"), false);
});

Deno.test("calculates age at the UTC birthday boundary", () => {
  equal(ageOn("2008-07-23", new Date("2026-07-22T12:00:00Z")), 17);
  equal(ageOn("2008-07-22", new Date("2026-07-22T12:00:00Z")), 18);
});

Deno.test("accepts a Brazilian adult and normalizes protected inputs", () => {
  const value = validateRegistrationInput({
    idempotencyKey: "submit-key-000001",
    nationality: "BR",
    fullName: "  Maria   Teste ",
    dateOfBirth: "1990-01-01",
    documentType: "CPF",
    documentValue: "529.982.247-25",
    issuerCountry: null,
    phone: "11999999999",
    guardianName: null,
    guardianRelationship: null,
    privacyNoticeVersion: "dev-v1",
    termsVersion: "dev-v1",
    privacyAcknowledged: true,
    termsAccepted: true,
  }, new Date("2026-07-22T12:00:00Z"));
  equal(value.fullName, "Maria Teste");
  equal(value.documentValue, "52998224725");
  equal(value.phone, "+5511999999999");
  equal(value.isMinor, false);
});

Deno.test("requires guardian for a minor and rejects unknown document modes", () => {
  throws(() =>
    validateRegistrationInput({
      idempotencyKey: "submit-key-000002",
      nationality: "BR",
      fullName: "Pessoa Menor",
      dateOfBirth: "2012-01-01",
      documentType: null,
      documentValue: null,
      issuerCountry: null,
      phone: null,
      guardianName: null,
      guardianRelationship: null,
      privacyNoticeVersion: "dev-v1",
      termsVersion: "dev-v1",
      privacyAcknowledged: true,
      termsAccepted: true,
    }, new Date("2026-07-22T12:00:00Z"))
  );
});

Deno.test("rejects future birth dates and incomplete foreign documents", () => {
  const base = {
    idempotencyKey: "submit-key-000003",
    nationality: "FOREIGN",
    fullName: "Foreign Person",
    dateOfBirth: "1990-01-01",
    documentType: "PASSPORT",
    documentValue: "AB123456",
    issuerCountry: null,
    phone: null,
    guardianName: null,
    guardianRelationship: null,
    privacyNoticeVersion: "dev-v1",
    termsVersion: "dev-v1",
    privacyAcknowledged: true,
    termsAccepted: true,
  };
  throws(() =>
    validateRegistrationInput(base, new Date("2026-07-22T12:00:00Z"))
  );
  throws(() =>
    validateRegistrationInput(
      { ...base, dateOfBirth: "2030-01-01", issuerCountry: "BR" },
      new Date("2026-07-22T12:00:00Z"),
    )
  );
});

function equal(actual: unknown, expected: unknown) {
  if (actual !== expected) throw new Error(`${actual} !== ${expected}`);
}
function throws(callback: () => unknown) {
  try {
    callback();
  } catch {
    return;
  }
  throw new Error("expected callback to throw");
}
