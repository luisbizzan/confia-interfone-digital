"use client";

import { Box, Button, Stack, Typography } from "@mui/material";

type PageHeaderProps = {
  title: string;
  description: string;
  actionLabel?: string;
  actionHref?: string;
  onAction?: () => void;
};

export function PageHeader({ title, description, actionLabel, actionHref, onAction }: PageHeaderProps) {
  return (
    <Stack
      direction={{ xs: "column", sm: "row" }}
      spacing={2}
      sx={{
        alignItems: { xs: "stretch", sm: "flex-start" },
        justifyContent: "space-between",
        mb: 3,
      }}
    >
      <Box sx={{ minWidth: 0 }}>
        <Typography variant="h1">{title}</Typography>
        <Typography color="text.secondary" sx={{ mt: 0.75 }}>
          {description}
        </Typography>
      </Box>
      {actionLabel && (
        <Button component={actionHref ? "a" : "button"} href={actionHref} onClick={onAction} variant="contained">
          {actionLabel}
        </Button>
      )}
    </Stack>
  );
}
