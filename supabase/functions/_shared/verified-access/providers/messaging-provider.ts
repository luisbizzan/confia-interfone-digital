import type {
  InvitationMessageInput,
  MessageDelivery,
  MessageDeliveryStatus,
  MessagingProviderReadContext,
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
    context: MessagingProviderReadContext,
  ): Promise<ProviderResult<MessageDeliveryStatus>>;
}
