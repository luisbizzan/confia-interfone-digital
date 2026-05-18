"use client";

import LoginIcon from "@mui/icons-material/Login";
import { Alert, Box, Button, Card, CardContent, Stack, TextField, Typography } from "@mui/material";
import { useRouter, useSearchParams } from "next/navigation";
import { useState } from "react";

export function LoginForm() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState("");
  const [pending, setPending] = useState(false);

  async function handleSubmit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setPending(true);
    setError("");

    const response = await fetch("/api/auth/login", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ email, password }),
    });

    const payload = await response.json();
    setPending(false);

    if (!response.ok) {
      setError(payload?.error ?? "Falha no login");
      return;
    }

    router.replace(searchParams.get("next") || "/");
    router.refresh();
  }

  return (
    <Box
      sx={{
        minHeight: "100vh",
        display: "grid",
        placeItems: "center",
        bgcolor: "background.default",
        px: 2,
      }}
    >
      <Card sx={{ width: "100%", maxWidth: 420 }}>
        <CardContent>
          <Stack component="form" onSubmit={handleSubmit} spacing={2.5}>
            <Stack spacing={0.75}>
              <Typography variant="h1">Confia</Typography>
              <Typography color="text.secondary">Acesse o backoffice administrativo.</Typography>
            </Stack>
            {error && <Alert severity="error">{error}</Alert>}
            <TextField
              autoComplete="email"
              autoFocus
              fullWidth
              label="Email"
              onChange={(event) => setEmail(event.target.value)}
              required
              type="email"
              value={email}
            />
            <TextField
              autoComplete="current-password"
              fullWidth
              label="Senha"
              onChange={(event) => setPassword(event.target.value)}
              required
              type="password"
              value={password}
            />
            <Button disabled={pending} startIcon={<LoginIcon />} type="submit" variant="contained">
              {pending ? "Entrando..." : "Entrar"}
            </Button>
          </Stack>
        </CardContent>
      </Card>
    </Box>
  );
}
