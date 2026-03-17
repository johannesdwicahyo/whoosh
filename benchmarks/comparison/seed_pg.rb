# frozen_string_literal: true

require "sequel"

DB_URL = ENV["DATABASE_URL"] || "postgres://localhost/whoosh_bench"
db = Sequel.connect(DB_URL)

db.drop_table?(:users)
db.create_table :users do
  primary_key :id
  String :name, null: false
  String :email, null: false
  Integer :age
  String :role, default: "user"
  DateTime :created_at
end

# Add index for faster lookups
db.add_index :users, :id

1000.times do |i|
  db[:users].insert(
    name: "User #{i + 1}",
    email: "user#{i + 1}@example.com",
    age: 20 + (i % 50),
    role: i < 10 ? "admin" : "user",
    created_at: Time.now
  )
end

puts "Seeded #{db[:users].count} users into #{DB_URL}"
db.disconnect
