import type {
  IdentityCancellation,
  IdentityCapabilities,
  IdentityResult,
  IdentitySession,
  IdentitySessionInput,
  ProviderMutationContext,
  ProviderReadContext,
} from "./contracts.ts";
import type { ProviderResult } from "./result.ts";

export interface IdentityProvider {
  capabilities(): IdentityCapabilities;
  createSession(
    input: IdentitySessionInput,
  ): Promise<ProviderResult<IdentitySession>>;
  getResult(
    providerSessionId: string,
    context: ProviderReadContext,
  ): Promise<ProviderResult<IdentityResult>>;
  cancelSession(
    providerSessionId: string,
    context: ProviderMutationContext,
  ): Promise<ProviderResult<IdentityCancellation>>;
}
