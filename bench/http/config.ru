# One Rails app, one Puma, the same two endpoints written three ways:
#   /rails/items   a plain ActionController::API controller
#   /grape/items   Grape with grape-entity, mounted in the Rails router
#   /whoosh/items  Whoosh, mounted in the Rails router
# Under /bare/ Grape and Whoosh also run straight on Puma, with no Rails in front.
# /noop and /bare/noop do nothing: they show what Rails and Puma cost on their own.
# Every version checks a bearer token, validates :id as an integer and
# returns the same JSON. Run it with `ruby bench/http/run.rb`.
require "bundler/setup"
require "action_controller/railtie"
require "grape"
require "grape-entity"
require "whoosh"

Item = Struct.new(:id, :name, :price, :created_at)
ITEMS = (1..25).map { |i| Item.new(i, "Item #{i}", BigDecimal("1000.5") * i, Time.utc(2026, 1, 1, 0, 0, i)) }
TOKEN = "Bearer t".freeze
NOOP = ->(_env) { [200, {}, ["ok"]] }

class BenchApp < Rails::Application
  config.load_defaults 8.1
  config.api_only = true
  config.eager_load = true
  config.secret_key_base = "bench"
  config.hosts.clear
  config.cache_store = :memory_store
  # Info level into /dev/null: every framework pays for building its log lines, none for the disk.
  config.logger = ActiveSupport::Logger.new(File::NULL)
  config.log_level = :info
end

# --- Rails ---
class ItemsController < ActionController::API
  before_action { head :unauthorized unless request.authorization == TOKEN }

  def index
    render json: { data: ITEMS.map { |item| row(item) } }
  end

  def show
    id = Integer(params[:id], exception: false) or return head(:unprocessable_entity)
    render json: { data: row(ITEMS.fetch(id - 1)) }
  end

  private

  def row(item) = { id: item.id, name: item.name, price: item.price.to_s("F"), created_at: item.created_at.iso8601(3) }
end

# --- Grape ---
class ItemEntity < Grape::Entity
  expose :id, :name
  expose(:price) { |item| item.price.to_s("F") }
  expose(:created_at) { |item| item.created_at.iso8601(3) }
end

class GrapeAPI < Grape::API
  format :json
  before { error!("Unauthorized", 401) unless headers["authorization"] == TOKEN }

  get "/items" do
    present :data, ITEMS, with: ItemEntity
  end

  params { requires :id, type: Integer }
  get "/items/:id" do
    present :data, ITEMS.fetch(params[:id] - 1), with: ItemEntity
  end
end

# --- Whoosh ---
class ItemSchema < Whoosh::Schema
  field :id, :integer
  field :name, :string
  field :price, :decimal
  field :created_at, :datetime
end

class WhooshAPI < Whoosh::API
  get "/items" do
    authorize { |user| user }
    returns ItemSchema, many: true
    handle { ITEMS }
  end

  get "/items/:id" do
    authorize { |user| user }
    params { required :id, :integer }
    returns ItemSchema
    handle { |p| ITEMS.fetch(p[:id] - 1) }
  end
end

Whoosh.configure do |c|
  c.authenticate = ->(req) { req.bearer_token == "t" ? :user : nil }
  # Rate limiting stays on (the other two don't have any); the limit is only raised so the run isn't cut off.
  c.rate_limit = [1_000_000_000, 60]
end

BenchApp.initialize!
BenchApp.routes.draw do
  get "/rails/items" => "items#index"
  get "/rails/items/:id" => "items#show"
  mount GrapeAPI => "/grape"
  mount WhooshAPI => "/whoosh"
  mount NOOP => "/noop"
end

map("/bare/whoosh") { run WhooshAPI }
map("/bare/grape") { run GrapeAPI }
map("/bare/noop") { run NOOP }
run BenchApp
