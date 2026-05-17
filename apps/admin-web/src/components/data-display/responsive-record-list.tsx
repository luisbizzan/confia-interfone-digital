import type { ReactNode } from "react";
import {
  Box,
  Card,
  CardContent,
  Divider,
  Stack,
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableRow,
  Typography,
} from "@mui/material";
import { EmptyState } from "@/components/feedback/empty-state";

export type ResponsiveColumn<T> = {
  key: string;
  header: string;
  render: (item: T) => ReactNode;
  hideOnMobile?: boolean;
};

type ResponsiveRecordListProps<T> = {
  title: string;
  description?: string;
  items: T[];
  columns: ResponsiveColumn<T>[];
  getKey: (item: T) => string;
  emptyTitle: string;
  emptyDescription: string;
};

export function ResponsiveRecordList<T>({
  title,
  description,
  items,
  columns,
  getKey,
  emptyTitle,
  emptyDescription,
}: ResponsiveRecordListProps<T>) {
  if (items.length === 0) {
    return <EmptyState description={emptyDescription} title={emptyTitle} />;
  }

  return (
    <Card>
      <CardContent>
        <Stack spacing={0.75} sx={{ mb: 2 }}>
          <Typography variant="h3">{title}</Typography>
          {description && <Typography color="text.secondary">{description}</Typography>}
        </Stack>

        <Box sx={{ display: { xs: "none", md: "block" }, overflowX: "auto" }}>
          <Table sx={{ minWidth: 720 }}>
            <TableHead>
              <TableRow>
                {columns.map((column) => (
                  <TableCell key={column.key}>{column.header}</TableCell>
                ))}
              </TableRow>
            </TableHead>
            <TableBody>
              {items.map((item) => (
                <TableRow key={getKey(item)} hover>
                  {columns.map((column) => (
                    <TableCell key={column.key}>{column.render(item)}</TableCell>
                  ))}
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </Box>

        <Stack spacing={1.5} sx={{ display: { xs: "flex", md: "none" } }}>
          {items.map((item) => (
            <Card key={getKey(item)} variant="outlined">
              <CardContent>
                <Stack divider={<Divider flexItem />} spacing={1.25}>
                  {columns
                    .filter((column) => !column.hideOnMobile)
                    .map((column) => (
                      <Box key={column.key}>
                        <Typography color="text.secondary" variant="caption">
                          {column.header}
                        </Typography>
                        <Box sx={{ mt: 0.25 }}>{column.render(item)}</Box>
                      </Box>
                    ))}
                </Stack>
              </CardContent>
            </Card>
          ))}
        </Stack>
      </CardContent>
    </Card>
  );
}
