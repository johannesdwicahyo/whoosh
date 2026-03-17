const fastify = require("fastify")({ logger: false });
const Database = require("better-sqlite3");
const path = require("path");

const db = new Database(path.join(__dirname, "bench.sqlite3"), { readonly: true });
const stmt = db.prepare("SELECT id, name, email, age, role FROM users WHERE id = ?");

fastify.get("/users/:id", async (request, reply) => {
  const user = stmt.get(request.params.id);
  if (!user) {
    reply.code(404);
    return { error: "not_found" };
  }
  return user;
});

const port = process.env.PORT || 3007;
fastify.listen({ port: parseInt(port), host: "localhost" }, (err) => {
  if (err) throw err;
  console.log(`Fastify DB listening on ${port}`);
});
