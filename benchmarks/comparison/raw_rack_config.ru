# Absolute bare minimum Rack app — zero framework overhead
run -> (env) {
  [200, { "content-type" => "application/json" }, ['{"status":"ok"}']]
}
