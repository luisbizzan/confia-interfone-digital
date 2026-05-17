import { Alert, Button, Stack } from "@mui/material";

type ErrorAlertProps = {
  message: string;
  onRetry?: () => void;
};

export function ErrorAlert({ message, onRetry }: ErrorAlertProps) {
  return (
    <Alert
      action={
        onRetry ? (
          <Button color="inherit" onClick={onRetry} size="small">
            Tentar novamente
          </Button>
        ) : undefined
      }
      severity="error"
    >
      <Stack>{message}</Stack>
    </Alert>
  );
}
