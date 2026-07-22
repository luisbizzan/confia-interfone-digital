"use client";

import { AlertTriangle, ArrowRight, CheckCircle2, LoaderCircle, LockKeyhole, ShieldCheck } from "lucide-react";
import Image from "next/image";
import { useRouter, useSearchParams } from "next/navigation";
import { FormEvent, useEffect, useMemo, useState } from "react";
import { clearSession, exchangeInvitation, PublicApiError, registrationContext, registrationStatus, startRegistration, submitRegistration, type RegistrationContext } from "@/lib/api";
import { ageAt, type FormValues, validate } from "@/lib/validation";

const LEGAL_VERSION = "dev-provisional-v1";
const INITIAL: FormValues = { nationality: "BR", fullName: "", dateOfBirth: "", documentType: "CPF", documentValue: "", issuerCountry: "", phone: "", guardianName: "", guardianRelationship: "", privacyAcknowledged: false, termsAccepted: false };

export function RegistrationFlow({ mode }: { mode: "invite" | "register" | "status" }) {
  const router = useRouter();
  const search = useSearchParams();
  const [context, setContext] = useState<RegistrationContext | null>(null);
  const [values, setValues] = useState(INITIAL);
  const [errors, setErrors] = useState<Record<string, string>>({});
  const [busy, setBusy] = useState(mode !== "invite");
  const [error, setError] = useState<string | null>(null);
  const [status, setStatus] = useState<{ registrationStatus: string; submittedAt?: string } | null>(null);
  const age = useMemo(() => ageAt(values.dateOfBirth), [values.dateOfBirth]);

  useEffect(() => {
    if (mode === "invite") return;
    let active = true;
    const load = async () => {
      try {
        if (mode === "status") {
          const result = await registrationStatus();
          if (active) setStatus(result);
        } else {
          const result = await registrationContext();
          let key = sessionStorage.getItem("verified-access-start-key");
          if (!key) {
            key = `start-${crypto.randomUUID()}`;
            sessionStorage.setItem("verified-access-start-key", key);
          }
          await startRegistration(key);
          if (active) setContext(result);
        }
      } catch (caught) {
        if (active) setError(message(caught));
      } finally {
        if (active) setBusy(false);
      }
    };
    void load();
    return () => { active = false; };
  }, [mode]);

  const continueInvitation = async () => {
    const token = search.get("token");
    if (!token) return setError("Este convite não está disponível.");
    setBusy(true);
    setError(null);
    try {
      await exchangeInvitation(token, `exchange-${crypto.randomUUID()}`);
      router.replace("/register");
    } catch (caught) {
      setError(message(caught));
      setBusy(false);
    }
  };

  const submit = async (event: FormEvent) => {
    event.preventDefault();
    const found = validate(values);
    setErrors(found);
    if (Object.keys(found).length) return;
    setBusy(true);
    setError(null);
    try {
      await submitRegistration({
        idempotencyKey: `submit-${crypto.randomUUID()}`,
        nationality: values.nationality,
        fullName: values.fullName,
        dateOfBirth: values.dateOfBirth,
        documentType: values.documentType || null,
        documentValue: values.documentValue || null,
        issuerCountry: values.issuerCountry || null,
        phone: values.phone || null,
        guardianName: values.guardianName || null,
        guardianRelationship: values.guardianRelationship || null,
        privacyNoticeVersion: LEGAL_VERSION,
        termsVersion: LEGAL_VERSION,
        privacyAcknowledged: values.privacyAcknowledged,
        termsAccepted: values.termsAccepted,
      });
      sessionStorage.removeItem("verified-access-start-key");
      router.replace("/status");
    } catch (caught) {
      setError(message(caught));
      setBusy(false);
    }
  };

  return (
    <main className="shell">
      <header className="brand"><Image src="/favicon.ico" alt="" width={36} height={36} /><div><strong>Confia</strong><span>Acesso Verificado</span></div><ShieldCheck aria-hidden="true" /></header>
      <div className="progress" aria-label="Etapas do cadastro"><span className={mode === "invite" ? "current" : "done"}>Convite</span><span className={mode === "register" ? "current" : mode === "status" ? "done" : ""}>Identificação</span><span className={mode === "status" ? "current" : ""}>Conclusão</span></div>

      {error && <div className="alert" role="alert"><AlertTriangle aria-hidden="true" /><div><strong>Não foi possível continuar</strong><p>{error}</p></div></div>}
      {busy && <div className="loading" role="status"><LoaderCircle className="spin" aria-hidden="true" />Processando com segurança...</div>}

      {!busy && mode === "invite" && <section className="intro"><p className="eyebrow">Cadastro por convite</p><h1>Confirme sua participação</h1><p>Este link inicia uma sessão protegida de 30 minutos para o cadastro solicitado pelo condomínio.</p><div className="security-note"><LockKeyhole aria-hidden="true" /><span>Seus dados não são salvos neste dispositivo como rascunho.</span></div><button className="primary" onClick={continueInvitation}>Continuar <ArrowRight aria-hidden="true" /></button></section>}

      {!busy && mode === "register" && context && <form onSubmit={submit} noValidate>
        <section className="context"><p className="eyebrow">Convite válido</p><h1>{context.condominiumName}</h1><dl><div><dt>Tipo</dt><dd>{requestLabel(context.requestType)}</dd></div><div><dt>Período</dt><dd>{formatPeriod(context.startsAt, context.endsAt)}</dd></div></dl></section>
        <section className="form-section"><h2>Identificação</h2><fieldset className="segmented"><legend>Nacionalidade</legend><label><input type="radio" checked={values.nationality === "BR"} onChange={() => setValues({ ...values, nationality: "BR", documentType: "CPF", issuerCountry: "" })} />Brasileira</label><label><input type="radio" checked={values.nationality === "FOREIGN"} onChange={() => setValues({ ...values, nationality: "FOREIGN", documentType: "RNM", documentValue: "" })} />Estrangeira</label></fieldset>
          <Field label="Nome completo" name="fullName" value={values.fullName} error={errors.fullName} onChange={update(setValues, values, "fullName")} autoComplete="name" />
          <Field label="Data de nascimento" name="dateOfBirth" type="date" value={values.dateOfBirth} error={errors.dateOfBirth} onChange={update(setValues, values, "dateOfBirth")} autoComplete="bday" />
          {values.nationality === "FOREIGN" && <label className="field"><span>Documento</span><select value={values.documentType} onChange={(event) => setValues({ ...values, documentType: event.target.value as FormValues["documentType"], issuerCountry: "" })}><option value="RNM">RNM</option><option value="PASSPORT">Passaporte</option></select>{errors.documentType && <small>{errors.documentType}</small>}</label>}
          {(values.nationality === "FOREIGN" || age === null || age >= 18 || values.documentValue) && <Field label={values.documentType === "CPF" ? "CPF" : values.documentType === "RNM" ? "RNM" : "Passaporte"} name="documentValue" value={values.documentValue} error={errors.documentValue} onChange={update(setValues, values, "documentValue")} autoComplete="off" />}
          {values.documentType === "PASSPORT" && <Field label="País emissor (código ISO)" name="issuerCountry" value={values.issuerCountry} error={errors.issuerCountry} onChange={update(setValues, values, "issuerCountry")} autoComplete="country" />}
          <Field label="Telefone (opcional)" name="phone" type="tel" value={values.phone} onChange={update(setValues, values, "phone")} autoComplete="tel" />
        </section>
        {age !== null && age < 18 && <section className="form-section"><h2>Responsável</h2><Field label="Nome do responsável" name="guardianName" value={values.guardianName} error={errors.guardianName} onChange={update(setValues, values, "guardianName")} autoComplete="off" /><Field label="Vínculo com o menor" name="guardianRelationship" value={values.guardianRelationship} onChange={update(setValues, values, "guardianRelationship")} autoComplete="off" /></section>}
        <section className="legal"><h2>Confirmações</h2><div className="dev-warning"><AlertTriangle aria-hidden="true" /><strong>AMBIENTE DE DESENVOLVIMENTO: aviso de privacidade e termos provisórios. Este fluxo não está autorizado para uso em produção.</strong></div><label className="check"><input type="checkbox" checked={values.privacyAcknowledged} onChange={(event) => setValues({ ...values, privacyAcknowledged: event.target.checked })} /><span>Declaro ciência do aviso de privacidade provisório.</span></label>{errors.privacyAcknowledged && <small>{errors.privacyAcknowledged}</small>}<label className="check"><input type="checkbox" checked={values.termsAccepted} onChange={(event) => setValues({ ...values, termsAccepted: event.target.checked })} /><span>Aceito os termos provisórios deste cadastro.</span></label>{errors.termsAccepted && <small>{errors.termsAccepted}</small>}</section>
        <button className="primary submit" type="submit">Enviar cadastro <ArrowRight aria-hidden="true" /></button>
      </form>}

      {!busy && mode === "status" && status && <section className="complete"><CheckCircle2 aria-hidden="true" /><p className="eyebrow">Cadastro recebido</p><h1>Participação registrada</h1><p>Os dados foram enviados com proteção e o convite foi concluído.</p>{status.submittedAt && <time dateTime={status.submittedAt}>Enviado em {new Date(status.submittedAt).toLocaleString("pt-BR")}</time>}<button className="secondary" onClick={() => { clearSession(); router.replace("/invite"); }}>Encerrar</button></section>}
      <footer>Confia Interfone Digital · Ambiente de desenvolvimento</footer>
    </main>
  );
}

type FieldProps = { label: string; name: string; value: string; onChange: (value: string) => void; error?: string; type?: string; autoComplete?: string };
function Field({ label, name, value, onChange, error, type = "text", autoComplete }: FieldProps) { return <label className="field"><span>{label}</span><input name={name} type={type} value={value} onChange={(event) => onChange(event.target.value)} aria-invalid={Boolean(error)} aria-describedby={error ? `${name}-error` : undefined} autoComplete={autoComplete} />{error && <small id={`${name}-error`}>{error}</small>}</label>; }
function update(setter: (value: FormValues) => void, values: FormValues, key: keyof FormValues) { return (value: string) => setter({ ...values, [key]: value }); }
function message(error: unknown) { if (error instanceof PublicApiError && error.status === 429) return "Muitas tentativas. Aguarde alguns minutos e tente novamente."; if (error instanceof PublicApiError && error.status === 404) return "Este convite não está disponível."; return "O serviço está temporariamente indisponível. Tente novamente."; }
function requestLabel(value: string) { return value === "VISITOR" ? "Visitante" : value === "SERVICE_PROVIDER" ? "Prestador de serviço" : "Acesso temporário"; }
function formatPeriod(start: string, end: string) { const formatter = new Intl.DateTimeFormat("pt-BR", { dateStyle: "short", timeStyle: "short" }); return `${formatter.format(new Date(start))} a ${formatter.format(new Date(end))}`; }
