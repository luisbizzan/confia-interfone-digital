import { describe, expect, it } from "vitest";
import { ageAt, type FormValues, validate } from "./validation";

const ADULT: FormValues = {
  nationality: "BR",
  fullName: "Maria Teste",
  dateOfBirth: "1990-01-01",
  documentType: "CPF",
  documentValue: "52998224725",
  issuerCountry: "",
  phone: "",
  guardianName: "",
  guardianRelationship: "",
  privacyAcknowledged: true,
  termsAccepted: true,
};

describe("public registration validation", () => {
  it("uses the birthday boundary for minor status", () => {
    expect(ageAt("2008-07-23", new Date("2026-07-22T12:00:00Z"))).toBe(17);
    expect(ageAt("2008-07-22", new Date("2026-07-22T12:00:00Z"))).toBe(18);
  });

  it("accepts a structurally valid Brazilian adult", () => {
    expect(validate(ADULT, new Date("2026-07-22T12:00:00Z"))).toEqual({});
  });

  it("requires a guardian for a minor and legal acceptance", () => {
    const errors = validate({ ...ADULT, dateOfBirth: "2012-01-01", documentValue: "", privacyAcknowledged: false }, new Date("2026-07-22T12:00:00Z"));
    expect(errors.guardianName).toBeTruthy();
    expect(errors.privacyAcknowledged).toBeTruthy();
  });

  it("requires issuer country for a foreign passport", () => {
    const errors = validate({ ...ADULT, nationality: "FOREIGN", documentType: "PASSPORT", documentValue: "AB123456", issuerCountry: "" }, new Date("2026-07-22T12:00:00Z"));
    expect(errors.issuerCountry).toBeTruthy();
  });
});
