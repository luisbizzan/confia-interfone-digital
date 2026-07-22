export type FormValues = {
  nationality: "BR" | "FOREIGN";
  fullName: string;
  dateOfBirth: string;
  documentType: "CPF" | "RNM" | "PASSPORT" | "";
  documentValue: string;
  issuerCountry: string;
  phone: string;
  guardianName: string;
  guardianRelationship: string;
  privacyAcknowledged: boolean;
  termsAccepted: boolean;
};

export function ageAt(dateOfBirth: string, now = new Date()): number | null {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(dateOfBirth)) return null;
  const date = new Date(`${dateOfBirth}T00:00:00.000Z`);
  if (!Number.isFinite(date.getTime()) || date.toISOString().slice(0, 10) !== dateOfBirth || date > now) return null;
  let age = now.getUTCFullYear() - date.getUTCFullYear();
  if (now.getUTCMonth() < date.getUTCMonth() || (now.getUTCMonth() === date.getUTCMonth() && now.getUTCDate() < date.getUTCDate())) age--;
  return age;
}

export function validate(values: FormValues, now = new Date()): Record<string, string> {
  const errors: Record<string, string> = {};
  const age = ageAt(values.dateOfBirth, now);
  if (values.fullName.trim().length < 3) errors.fullName = "Informe o nome completo.";
  if (age === null) errors.dateOfBirth = "Informe uma data de nascimento válida.";
  if (values.nationality === "BR") {
    if ((age ?? 18) >= 18 && (values.documentType !== "CPF" || !validCpf(values.documentValue))) errors.documentValue = "Informe um CPF válido.";
    if (values.documentValue && !validCpf(values.documentValue)) errors.documentValue = "Informe um CPF válido.";
  } else if (values.documentType === "RNM") {
    if (!/^[A-Z][0-9]{6}[A-Z0-9]$/.test(values.documentValue.toUpperCase())) errors.documentValue = "Informe um RNM válido.";
  } else if (values.documentType === "PASSPORT") {
    if (!/^[A-Z0-9]{6,12}$/.test(values.documentValue.toUpperCase())) errors.documentValue = "Informe um passaporte válido.";
    if (!/^[A-Z]{2}$/.test(values.issuerCountry.toUpperCase())) errors.issuerCountry = "Use o código de país com duas letras.";
  } else errors.documentType = "Selecione RNM ou passaporte.";
  if (age !== null && age < 18 && (values.guardianName.trim().length < 3 || values.guardianRelationship.trim().length < 2)) errors.guardianName = "Informe o responsável e o vínculo.";
  if (!values.privacyAcknowledged) errors.privacyAcknowledged = "Confirme a ciência do aviso de privacidade.";
  if (!values.termsAccepted) errors.termsAccepted = "Aceite os termos para continuar.";
  return errors;
}

function validCpf(value: string): boolean {
  const cpf = value.replace(/\D/g, "");
  if (cpf.length !== 11 || /^(\d)\1{10}$/.test(cpf)) return false;
  const digit = (length: number) => {
    let sum = 0;
    for (let index = 0; index < length; index++) sum += Number(cpf[index]) * (length + 1 - index);
    const result = 11 - (sum % 11);
    return result >= 10 ? 0 : result;
  };
  return digit(9) === Number(cpf[9]) && digit(10) === Number(cpf[10]);
}
