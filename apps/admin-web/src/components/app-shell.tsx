"use client";

import ApartmentIcon from "@mui/icons-material/Apartment";
import CallIcon from "@mui/icons-material/Call";
import DashboardIcon from "@mui/icons-material/Dashboard";
import HistoryIcon from "@mui/icons-material/History";
import HomeWorkIcon from "@mui/icons-material/HomeWork";
import MenuIcon from "@mui/icons-material/Menu";
import PeopleIcon from "@mui/icons-material/People";
import SecurityIcon from "@mui/icons-material/Security";
import SettingsIcon from "@mui/icons-material/Settings";
import {
  AppBar,
  Box,
  Button,
  Divider,
  Drawer,
  IconButton,
  List,
  ListItemButton,
  ListItemIcon,
  ListItemText,
  Stack,
  Toolbar,
  Typography,
} from "@mui/material";
import { usePathname } from "next/navigation";
import { useEffect, useState } from "react";

const drawerWidth = 272;

const navItems = [
  { label: "Dashboard", icon: <DashboardIcon />, href: "/" },
  { label: "Condomínios", icon: <ApartmentIcon />, href: "/condominios" },
  { label: "Unidades", icon: <HomeWorkIcon />, href: "/unidades" },
  { label: "Moradores", icon: <PeopleIcon />, href: "/moradores" },
  { label: "Portaria", icon: <SecurityIcon />, href: "/portaria" },
  { label: "Chamadas", icon: <CallIcon />, href: "/chamadas" },
  { label: "Auditoria", icon: <HistoryIcon />, href: "/auditoria" },
  { label: "Configurações", icon: <SettingsIcon />, href: "/configuracoes" },
];

export function AppShell({ children }: { children: React.ReactNode }) {
  const [mobileOpen, setMobileOpen] = useState(false);
  const [userLabel, setUserLabel] = useState("Backoffice");
  const pathname = usePathname();

  useEffect(() => {
    let mounted = true;

    fetch("/api/auth/me")
      .then((response) => (response.ok ? response.json() : null))
      .then((payload) => {
        if (mounted && payload) {
          setUserLabel(`${payload.name} · ${payload.role}`);
        }
      })
      .catch(() => undefined);

    return () => {
      mounted = false;
    };
  }, []);

  async function handleLogout() {
    await fetch("/api/auth/logout", { method: "POST" });
    window.location.href = "/login";
  }

  const drawer = (
    <Box sx={{ height: "100%", display: "flex", flexDirection: "column" }}>
      <Stack spacing={0.5} sx={{ px: 3, py: 2.5 }}>
        <Typography variant="h3" sx={{ fontSize: "1.15rem" }}>
          Confia
        </Typography>
        <Typography color="text.secondary" variant="body2">
          Interfone Digital
        </Typography>
      </Stack>
      <Divider />
      <List sx={{ px: 1.5, py: 1.5 }}>
        {navItems.map((item) => {
          const selected = item.href === "/" ? pathname === "/" : pathname.startsWith(item.href);

          return (
            <ListItemButton
              component="a"
              href={item.href}
              key={item.label}
              onClick={() => setMobileOpen(false)}
              selected={selected}
              sx={{
                borderRadius: 1,
                mb: 0.5,
                minHeight: 44,
                "&.Mui-selected": {
                  bgcolor: "primary.main",
                  color: "primary.contrastText",
                  "& .MuiListItemIcon-root": { color: "primary.contrastText" },
                },
              }}
            >
              <ListItemIcon sx={{ minWidth: 40 }}>{item.icon}</ListItemIcon>
              <ListItemText primary={<Typography sx={{ fontWeight: 700 }}>{item.label}</Typography>} />
            </ListItemButton>
          );
        })}
      </List>
      <Box sx={{ flexGrow: 1 }} />
      <Box sx={{ p: 2 }}>
        <Button fullWidth onClick={handleLogout} variant="outlined">
          Sair
        </Button>
      </Box>
    </Box>
  );

  return (
    <Box sx={{ minHeight: "100vh", bgcolor: "background.default" }}>
      <AppBar
        color="inherit"
        elevation={0}
        position="fixed"
        sx={{
          borderBottom: "1px solid",
          borderColor: "divider",
          width: { md: `calc(100% - ${drawerWidth}px)` },
          ml: { md: `${drawerWidth}px` },
        }}
      >
        <Toolbar sx={{ gap: 2 }}>
          <IconButton
            aria-label="Abrir navegação"
            edge="start"
            onClick={() => setMobileOpen(true)}
            sx={{ display: { xs: "inline-flex", md: "none" } }}
          >
            <MenuIcon />
          </IconButton>
          <Box sx={{ flexGrow: 1, minWidth: 0 }}>
            <Typography noWrap sx={{ fontWeight: 700 }} variant="subtitle1">
              Backoffice Confia
            </Typography>
            <Typography noWrap color="text.secondary" variant="caption">
              {userLabel}
            </Typography>
          </Box>
        </Toolbar>
      </AppBar>

      <Box component="nav" sx={{ width: { md: drawerWidth }, flexShrink: { md: 0 } }}>
        <Drawer
          ModalProps={{ keepMounted: true }}
          onClose={() => setMobileOpen(false)}
          open={mobileOpen}
          sx={{
            display: { xs: "block", md: "none" },
            "& .MuiDrawer-paper": { width: drawerWidth },
          }}
          variant="temporary"
        >
          {drawer}
        </Drawer>
        <Drawer
          open
          sx={{
            display: { xs: "none", md: "block" },
            "& .MuiDrawer-paper": {
              width: drawerWidth,
              boxSizing: "border-box",
              borderRight: "1px solid",
              borderColor: "divider",
            },
          }}
          variant="permanent"
        >
          {drawer}
        </Drawer>
      </Box>

      <Box
        component="main"
        sx={{
          ml: { md: `${drawerWidth}px` },
          minHeight: "100vh",
          pt: 10,
          px: { xs: 2, sm: 3, lg: 4 },
          pb: 4,
        }}
      >
        {children}
      </Box>
    </Box>
  );
}
