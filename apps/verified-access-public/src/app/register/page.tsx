import { Suspense } from "react";
import { RegistrationFlow } from "@/components/registration-flow";

export default function RegisterPage() {
  return <Suspense fallback={<main className="shell"><p>Carregando...</p></main>}><RegistrationFlow mode="register" /></Suspense>;
}
