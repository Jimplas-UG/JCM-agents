/** @type {import('next').NextConfig} */
const nextConfig = {
  output: "standalone",
  reactStrictMode: true,
  async rewrites() {
    const apiHost = process.env.JCM_API_HOST || "127.0.0.1";
    const apiPort = process.env.JCM_API_PORT || "8000";
    return [
      {
        source: "/jcm-api/:path*",
        destination: `http://${apiHost}:${apiPort}/:path*`,
      },
    ];
  },
};

module.exports = nextConfig;
