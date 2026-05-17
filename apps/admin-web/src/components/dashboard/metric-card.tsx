import type { ReactElement } from "react";
import { Box, Card, CardContent, Chip, Stack, Typography } from "@mui/material";
import type { SummaryMetric } from "@/lib/types";

type MetricCardProps = SummaryMetric & {
  icon: ReactElement;
};

export function MetricCard({ label, value, helper, tone, icon }: MetricCardProps) {
  return (
    <Card sx={{ height: "100%" }}>
      <CardContent>
        <Stack direction="row" spacing={2} sx={{ justifyContent: "space-between" }}>
          <Box>
            <Typography color="text.secondary" variant="body2">
              {label}
            </Typography>
            <Typography sx={{ mt: 1 }} variant="h2">
              {value}
            </Typography>
          </Box>
          <Chip color={tone === "default" ? undefined : tone} icon={icon} label="MVP" />
        </Stack>
        <Typography color="text.secondary" sx={{ mt: 2 }} variant="body2">
          {helper}
        </Typography>
      </CardContent>
    </Card>
  );
}
