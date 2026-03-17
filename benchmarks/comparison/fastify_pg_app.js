const fastify = require("fastify")({ logger: false });
const { Pool } = require("pg");

const pool = new Pool({
  connectionString: process.env.DATABASE_URL || "postgres://localhost/whoosh_bench",
  max: 16,
});

fastify.get("/users/:id", async (request) => {
  const { rows } = await pool.query(
    "SELECT id, name, email, age, role FROM users WHERE id = $1",
    [request.params.id]
  );
  if (rows.length === 0) {
    return { error: "not_found" };
  }
  return rows[0];
});

const port = process.env.PORT || 3007;
fastify.listen({ port: parseInt(port), host: "localhost" }, (err) => {
  if (err) throw err;
  console.log(`Fastify PG listening on ${port}`);
});
