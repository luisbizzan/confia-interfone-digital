import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { RegistrationFlow } from "./registration-flow";

const replace = vi.fn();
const api = vi.hoisted(() => ({
  exchangeInvitation: vi.fn(), registrationContext: vi.fn(), startRegistration: vi.fn(),
  submitRegistration: vi.fn(), registrationStatus: vi.fn(), clearSession: vi.fn(),
}));

vi.mock("next/navigation", () => ({ useRouter: () => ({ replace }), useSearchParams: () => new URLSearchParams("token=" + "A".repeat(43)) }));
vi.mock("@/lib/api", () => ({ ...api, PublicApiError: class PublicApiError extends Error { constructor(public code: string, public status: number) { super(code); } } }));

describe("RegistrationFlow", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    sessionStorage.clear();
    api.registrationContext.mockResolvedValue({ condominiumName: "Residencial Teste", requestType: "VISITOR", startsAt: "2026-07-22T12:00:00Z", endsAt: "2026-07-22T13:00:00Z", timezone: "America/Sao_Paulo", sessionStatus: "ACTIVE" });
    api.startRegistration.mockResolvedValue({});
    api.registrationStatus.mockResolvedValue({ registrationStatus: "SUBMITTED", submittedAt: "2026-07-22T12:00:00Z" });
    api.submitRegistration.mockResolvedValue({ registrationStatus: "SUBMITTED" });
  });

  it("exchanges the invitation and never renders the raw token", async () => {
    api.exchangeInvitation.mockResolvedValue({});
    render(<RegistrationFlow mode="invite" />);
    fireEvent.click(screen.getByRole("button", { name: /continuar/i }));
    await waitFor(() => expect(replace).toHaveBeenCalledWith("/register"));
    expect(document.body.textContent).not.toContain("A".repeat(43));
  });

  it("shows context, protected form and explicit DEV legal warning", async () => {
    render(<RegistrationFlow mode="register" />);
    expect(await screen.findByText("Residencial Teste")).toBeInTheDocument();
    expect(screen.getByLabelText("Nome completo")).toBeInTheDocument();
    expect(screen.getByText(/AMBIENTE DE DESENVOLVIMENTO/)).toBeInTheDocument();
  });

  it("does not submit invalid or unaccepted data", async () => {
    render(<RegistrationFlow mode="register" />);
    await screen.findByText("Residencial Teste");
    fireEvent.click(screen.getByRole("button", { name: /enviar cadastro/i }));
    expect(await screen.findByText("Informe o nome completo.")).toBeInTheDocument();
    expect(api.submitRegistration).not.toHaveBeenCalled();
  });

  it("shows guardian fields when the server-aligned age is under 18", async () => {
    render(<RegistrationFlow mode="register" />);
    await screen.findByText("Residencial Teste");
    fireEvent.change(screen.getByLabelText("Data de nascimento"), { target: { value: "2012-01-01" } });
    expect(screen.getByLabelText("Nome do responsável")).toBeInTheDocument();
    expect(screen.getByLabelText("Vínculo com o menor")).toBeInTheDocument();
  });

  it("submits one valid adult form and removes the invitation route", async () => {
    render(<RegistrationFlow mode="register" />);
    await screen.findByText("Residencial Teste");
    fireEvent.change(screen.getByLabelText("Nome completo"), { target: { value: "Maria Teste" } });
    fireEvent.change(screen.getByLabelText("Data de nascimento"), { target: { value: "1990-01-01" } });
    fireEvent.change(screen.getByLabelText("CPF"), { target: { value: "52998224725" } });
    fireEvent.click(screen.getByLabelText(/ciência do aviso/i));
    fireEvent.click(screen.getByLabelText(/aceito os termos/i));
    fireEvent.click(screen.getByRole("button", { name: /enviar cadastro/i }));
    await waitFor(() => expect(api.submitRegistration).toHaveBeenCalledTimes(1));
    expect(replace).toHaveBeenCalledWith("/status");
  });

  it("renders the final confirmation without exposing registration data", async () => {
    render(<RegistrationFlow mode="status" />);
    expect(await screen.findByText("Participação registrada")).toBeInTheDocument();
    expect(document.body.textContent).not.toContain("52998224725");
  });
});
