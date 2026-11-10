import './globals.css';

export const metadata = {
  title: 'Online Blogging Platform',
  description: 'Next.js skeleton for the DBMS project',
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
