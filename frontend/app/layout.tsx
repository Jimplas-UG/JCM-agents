import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "JCM Mission Control — BSv3.2",
  description: "Jimplas Capital Management CEO Dashboard",
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
