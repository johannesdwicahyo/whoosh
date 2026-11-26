# Delete one line and your API refuses to boot

Here is an endpoint in a Rails app. It lists products and anyone can call it.

```ruby
class ProductsApi < ApplicationApi
  get "/products" do
    public!
    paginate :offset
    returns ProductSchema
    handle { Product.order(:name) }
  end
end
```

Delete the `public!` line and boot the app the way production does, with eager loading:

```
ProductsApi GET /v1/products has no access rule (add `authorize { |user| ... }`,
or `public!` for anonymous access) (Whoosh::DefinitionError)
```

The app does not start. In development, where Rails loads classes lazily, the server still comes up, but the API class cannot load. In the test suite of the app this example comes from, 14 of 20 tests failed with the same message: every test that touches the API. So the mistake cannot get through CI, and it cannot get through a deploy. No reviewer has to notice it.

An endpoint with no access rule is not a warning in Whoosh. It is a class that fails to load. That one behaviour is the idea Whoosh 2 is built around.

## The mistake is always an omission

The usual way a Rails API leaks data is not somebody writing the wrong thing. It is somebody not writing something:

- a new controller action without the `before_action` the others have
- a `params.permit` that was skipped because the hash "only goes to a service object"
- a new `password_digest` or `internal_notes` column that `to_json` started sending the day it was migrated
- an endpoint that never got a rate limit because rate limits live in another file

Rails, Pundit, rack-attack and a serializer can prevent every one of these. They all share one property: when you forget the step, the code still works.

Whoosh turns it around. Every endpoint has to say who may call it, what it accepts and what it returns. What you did not declare does not exist:

- **No access rule:** the class fails to load.
- **Input you did not declare:** dropped before your handler runs, so a field you never declared cannot be mass-assigned.
- **Output you did not declare:** never serialized, so a new column stays private until you add it to the schema.
- **Rate limits, body size limits, page size caps:** on by default, and applied before the 401 check so token guessing is throttled too.

## It mounts in the Rails app you already have

Whoosh is not a replacement for Rails. It is a Rack app you mount in your routes, and your handlers use your models and service objects as they are.

```sh
bundle add whoosh
bin/rails g whoosh:install
bin/rails g whoosh:api Orders
```

`whoosh:api` reads the `orders` table and writes a list endpoint, a show endpoint, a schema and a test. Columns whose names look like credentials are left out of the schema, with a comment saying so. It is only a match on the name, so read the schema before you ship it. On a table of API tokens it produced this:

```ruby
class ApiTokenSchema < Whoosh::Schema
  field :id, :integer
  field :user_id, :integer
  field :revoked_at, :datetime
  field :created_at, :datetime
  field :updated_at, :datetime
  # Left out on purpose: digest
end
```

A fuller endpoint looks like this:

```ruby
post "/orders" do
  authorize { |user| user.can_sell? }
  idempotent
  params do
    required :customer_id, :integer
    required :items, :array, max_items: 50 do
      required :product_id, :integer
      required :quantity, :integer, min: 1, max: 999
    end
  end
  returns OrderSchema
  handle { |p| Orders::Create.call(p, by: current_user) }
end
```

The same declarations produce the OpenAPI document, so the docs cannot drift from the code.

## What it costs in speed

Nothing you will notice. I benchmarked the same two endpoints written in Whoosh, in Grape with grape-entity, and as a plain Rails API controller, all inside one Puma process:

| Requests per second | 1 record | 25 records |
|---|---|---|
| **Mounted in a Rails app** | | |
| Whoosh | 5,000 | 4,500 |
| Rails controller | 4,650 | 4,450 |
| Grape | 4,550 | 3,050 |
| An endpoint that does nothing | 5,800 | |
| **Straight on Puma, no Rails** | | |
| Whoosh | 18,000 | 13,600 |
| Grape | 13,900 | 6,400 |
| An endpoint that does nothing | 31,000 | |

Ruby 3.4 with YJIT, 5 Puma threads, Apple M4 Pro, no database. Whoosh was the only one doing rate limiting.

I am not going to claim Whoosh makes a Rails app faster. Look at the rows that do nothing: an empty response manages 31,000 requests a second on bare Puma and 5,800 through Rails. The Rails middleware stack costs more than any of the three frameworks, and a real endpoint spends its time in the database. The claim is narrower: you get validation, rate limiting and output schemas without paying for them. The script is in the repository (`rake bench:http`), so you can check it on your own machine.

## What it is not

- It only speaks JSON. No XML, no file uploads, no streaming.
- It is new. The API may still move before 3.0, and so far it has been proven in a demo app, not in production.
- Grape and plain Rails are far more mature and have much larger ecosystems. If you need those, use them.

One more thing, since the gem name has history. Whoosh 1.x was a different project: a much larger framework with LLM helpers, MCP, background jobs and more. It tried to be everything and was nobody's first choice for anything. Version 2 shares no code with it and does one job. The old code is still on the `1.x` branch.

## Try it

```ruby
gem "whoosh", "~> 2.2"
```

Source and README: https://github.com/johannesdwicahyo/whoosh

The fastest way to see the point is the one this post started with: generate an API, delete the `authorize` line, and run your tests.

Whoosh 2 has not been in production yet. If you try it in an app of yours, I would like to hear where it breaks: open an issue on GitHub.
