import type {
  InvitationMessageInput,
  MessageDelivery,
  MessageDeliveryStatus,
  ProviderReadContext,
  StatusMessageInput,
} from "./contracts.ts";
import type { ProviderResult } from "./result.ts";

export interface MessagingProvider {
  sendInvitation(
    input: InvitationMessageInput,
  ): Promise<ProviderResult<MessageDelivery>>;
  sendStatusUpdate(
    input: StatusMessageInput,
  ): Promise<ProviderResult<MessageDelivery>>;
  getDeliveryStatus(
    providerMessageId: string,
    context: ProviderReadContext,
  ): Promise<ProviderResult<MessageDeliveryStatus>>;
}
