const fastify = require("fastify")({ logger: false });

fastify.get("/health", async () => {
  return { status: "ok" };
});

const port = process.env.PORT || 3007;
fastify.listen({ port: parseInt(port), host: "localhost" }, (err) => {
  if (err) throw err;
  console.log(`Fastify listening on ${port}`);
});
