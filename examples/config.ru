# Standalone Whoosh app. Run with: bundle exec rackup examples/config.ru
# (or any Rack server: puma, falcon, iodine)
require "whoosh"

Note = Struct.new(:id, :title, :body, :created_at)
NOTES = []

class NoteSchema < Whoosh::Schema
  field :id, :integer
  field :title, :string
  field :body, :text
  field :created_at, :datetime
end

class NotesAPI < Whoosh::API
  version 1

  helpers do
    def find_note!(id) = NOTES.find { |n| n.id == id } || not_found!
  end

  get "/notes" do
    authorize { true }
    paginate
    returns NoteSchema
    handle { NOTES }
  end

  get "/notes/:id" do
    authorize { true }
    params { required :id, :integer }
    returns NoteSchema
    handle { |p| find_note!(p[:id]) }
  end

  post "/notes" do
    authorize { |user| user[:can_write] }
    idempotent
    params do
      required :title, :string, max_length: 120
      optional :body, :text, max_length: 20_000
    end
    returns NoteSchema
    handle do |p|
      note = Note.new(NOTES.size + 1, p[:title], p[:body], Time.now)
      NOTES << note
      header "location", "/v1/notes/#{note.id}"
      note
    end
  end
end

Whoosh.configure do |c|
  # Demo only: one hard-coded token. Compare tokens in constant time.
  c.authenticate = lambda do |request|
    token = request.bearer_token.to_s
    { id: 1, can_write: true } if !token.empty? && OpenSSL.fixed_length_secure_compare(
      OpenSSL::Digest::SHA256.digest(token), OpenSSL::Digest::SHA256.digest(ENV.fetch("API_TOKEN", "dev-token"))
    )
  end
  c.openapi = true
end

run NotesAPI
