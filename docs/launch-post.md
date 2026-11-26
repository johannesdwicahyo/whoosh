# Delete one line and your API refuses to boot

*Draft. Not published anywhere yet.*

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

Delete the `public!` line and start the app:

```
ProductsApi GET /v1/products has no access rule (add `authorize { |user| ... }`,
or `public!` for anonymous access) (Whoosh::DefinitionError)
```

The app does not start. There is no request to send, no test that has to exist, and no reviewer who has to notice. An endpoint with no access rule is not a warning in Whoosh. It is a class that fails to load.

That one behaviour is why I wrote Whoosh 2.

## The mistake is always an omission

Most API leaks I have seen in Rails apps were not somebody writing the wrong thing. They were somebody not writing something:

- a new controller action without the `before_action` the others have
- a `params.permit` that was skipped because the hash "only goes to a service object"
- a new `password_digest` or `internal_notes` column that `to_json` started sending the day it was migrated
- an endpoint that never got a rate limit because rate limits live in another file

Rails, Pundit, rack-attack and a serializer can prevent every one of these. They all share one property: when you forget the step, the code still works.

Whoosh turns it around. Every endpoint has to say who may call it, what it accepts and what it returns. What you did not declare does not exist:

- **No access rule:** the class fails to load.
- **Input you did not declare:** dropped before your handler runs, so mass assignment cannot happen.
- **Output you did not declare:** never serialized, so a new column stays private until you add it to the schema.
- **Rate limits, body size limits, page size caps:** on by default, and applied before the 401 check so token guessing is throttled too.

## It mounts in the Rails app you already have

Whoosh is not a replacement for Rails. It is a Rack app you mount in your routes, and your handlers use your models and service objects as they are.

```sh
bundle add whoosh
bin/rails g whoosh:install
bin/rails g whoosh:api Orders
```

The second generator reads the `orders` table and writes a list endpoint, a show endpoint, a schema and a test. Columns that look like credentials are left out of the schema with a comment saying so. On a table of API tokens it produced this:

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
| **Straight on Puma, no Rails** | | |
| Whoosh | 18,000 | 13,600 |
| Grape | 13,900 | 6,400 |

Ruby 3.4 with YJIT, 5 Puma threads, no database. Whoosh was the only one doing rate limiting.

I am not going to claim Whoosh makes a Rails app faster. Inside Rails, the Rails middleware stack costs more than any of the three, and a real endpoint spends its time in the database. The claim is narrower: you get validation, rate limiting and output schemas without paying for them. The script is in the repository (`rake bench:http`), so you can check it on your own machine.

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

The fastest way to see the point is the one this post started with: generate an API, delete the `authorize` line, and try to boot.
