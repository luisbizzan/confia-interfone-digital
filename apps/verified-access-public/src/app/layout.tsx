import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Acesso Verificado | Confia",
  description: "Cadastro protegido de visitantes e prestadores convidados.",
  robots: { index: false, follow: false },
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return <html lang="pt-BR"><body>{children}</body></html>;
}
