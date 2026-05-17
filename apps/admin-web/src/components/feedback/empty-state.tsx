import type { ReactNode } from "react";
import { Button, Card, CardContent, Stack, Typography } from "@mui/material";

type EmptyStateProps = {
  title: string;
  description: string;
  actionLabel?: string;
  icon?: ReactNode;
};

export function EmptyState({ title, description, actionLabel, icon }: EmptyStateProps) {
  return (
    <Card>
      <CardContent>
        <Stack
          spacing={1.5}
          sx={{
            alignItems: "center",
            minHeight: 220,
            justifyContent: "center",
            textAlign: "center",
          }}
        >
          {icon}
          <Typography variant="h3">{title}</Typography>
          <Typography color="text.secondary" sx={{ maxWidth: 480 }}>
            {description}
          </Typography>
          {actionLabel && <Button variant="contained">{actionLabel}</Button>}
        </Stack>
      </CardContent>
    </Card>
  );
}
