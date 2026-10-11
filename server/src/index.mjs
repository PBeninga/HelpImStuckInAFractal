import { loadConfig, configProblems } from "./config.mjs";
import { createApp } from "./app.mjs";

const config = loadConfig();
for (const p of configProblems(config)) console.warn(`config: ${p}`);

const { server } = createApp(config);
server.listen(config.port, () => {
  console.log(`fractal phone server on :${config.port} (public ${config.publicBaseUrl || "unset"})`);
});

for (const sig of ["SIGTERM", "SIGINT"]) {
  process.on(sig, () => {
    server.close(() => process.exit(0));
    setTimeout(() => process.exit(0), 3000).unref(); // open sockets do not hold a redeploy up
  });
}
