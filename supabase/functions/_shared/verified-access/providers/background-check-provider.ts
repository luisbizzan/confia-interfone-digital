import type {
  BackgroundCapabilities,
  BackgroundCheckInput,
  BackgroundCheckRequest,
  BackgroundCheckResult,
  ProviderReadContext,
} from "./contracts.ts";
import type { ProviderResult } from "./result.ts";

export interface BackgroundCheckProvider {
  capabilities(): BackgroundCapabilities;
  requestCheck(
    input: BackgroundCheckInput,
  ): Promise<ProviderResult<BackgroundCheckRequest>>;
  getResult(
    providerRequestId: string,
    context: ProviderReadContext,
  ): Promise<ProviderResult<BackgroundCheckResult>>;
}
