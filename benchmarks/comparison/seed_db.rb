# frozen_string_literal: true

# Seed a shared SQLite database for all framework benchmarks
require "sequel"

DB_PATH = File.join(__dir__, "bench.sqlite3")
File.delete(DB_PATH) if File.exist?(DB_PATH)

db = Sequel.sqlite(DB_PATH)

db.create_table :users do
  primary_key :id
  String :name, null: false
  String :email, null: false
  Integer :age
  String :role, default: "user"
  DateTime :created_at
end

1000.times do |i|
  db[:users].insert(
    name: "User #{i + 1}",
    email: "user#{i + 1}@example.com",
    age: 20 + (i % 50),
    role: i < 10 ? "admin" : "user",
    created_at: Time.now
  )
end

puts "Seeded #{db[:users].count} users into #{DB_PATH}"
