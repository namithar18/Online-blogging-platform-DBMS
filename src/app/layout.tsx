import "./globals.css";
import NavBar from "./NavBar";

export const metadata = {
  title: "Community Blog",
  description: "Community blogging with keyword and semantic search",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>
        <NavBar />
        {children}
      </body>
    </html>
  );
}