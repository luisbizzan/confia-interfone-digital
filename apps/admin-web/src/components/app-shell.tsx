"use client";

import ApartmentIcon from "@mui/icons-material/Apartment";
import CallIcon from "@mui/icons-material/Call";
import DashboardIcon from "@mui/icons-material/Dashboard";
import HistoryIcon from "@mui/icons-material/History";
import HomeWorkIcon from "@mui/icons-material/HomeWork";
import MenuIcon from "@mui/icons-material/Menu";
import PeopleIcon from "@mui/icons-material/People";
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
import { useState } from "react";

const drawerWidth = 272;

const navItems = [
  { label: "Dashboard", icon: <DashboardIcon />, active: true },
  { label: "Condomínios", icon: <ApartmentIcon /> },
  { label: "Unidades", icon: <HomeWorkIcon /> },
  { label: "Moradores", icon: <PeopleIcon /> },
  { label: "Chamadas", icon: <CallIcon /> },
  { label: "Auditoria", icon: <HistoryIcon /> },
  { label: "Configurações", icon: <SettingsIcon /> },
];

export function AppShell({ children }: { children: React.ReactNode }) {
  const [mobileOpen, setMobileOpen] = useState(false);

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
        {navItems.map((item) => (
          <ListItemButton
            key={item.label}
            selected={item.active}
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
        ))}
      </List>
      <Box sx={{ flexGrow: 1 }} />
      <Box sx={{ p: 2 }}>
        <Button fullWidth variant="outlined">
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
              Gestão operacional de condomínios e chamadas
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
