import { Card, CardContent, LinearProgress, Stack, Typography } from "@mui/material";

type LoadingPanelProps = {
  label: string;
};

export function LoadingPanel({ label }: LoadingPanelProps) {
  return (
    <Card>
      <CardContent>
        <Stack spacing={2}>
          <Typography color="text.secondary">{label}</Typography>
          <LinearProgress />
        </Stack>
      </CardContent>
    </Card>
  );
}
