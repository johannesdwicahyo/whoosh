# Whoosh Client Generator Design

**Date:** 2026-03-30
**Status:** Approved

## Overview

An intelligent client generator for the Whoosh framework that introspects an existing Whoosh API via its OpenAPI spec and produces complete, typed, ready-to-run client applications.

**Command:** `whoosh generate client <type> [--oauth] [--dir=<path>]`

**Supported client types:** `react_spa`, `expo`, `ios`, `flutter`, `htmx`

## CLI Interface & Flow

### Standard flow (existing Whoosh app)

```
$ whoosh generate client react_spa

Inspecting Whoosh app...

Found:
  Auth:       JWT (email/password)
  Resources:  tasks (5 endpoints), users (3 endpoints), comments (4 endpoints)
  Streaming:  SSE on /events

Generate client for:
  [x] Auth (login, register, logout, refresh)
  [x] tasks - CRUD (index, show, create, update, destroy)
  [x] users - Read-only (index, show, me)
  [x] comments - CRUD (index, create, update, destroy)
  [ ] SSE streaming (deselect with arrow keys)

Press enter to confirm, or use arrows to toggle.

Output directory: clients/react_spa (default)

Generated React SPA in clients/react_spa/
   Run: cd clients/react_spa && npm install && npm run dev
```

### Fallback flow (no app or empty routes)

```
$ whoosh generate client react_spa

No Whoosh app found (or no routes defined).

Generate standard starter with:
  - JWT auth (email/password login + register)
  - Tasks CRUD (title, description, status, due_date)
  - Matching backend endpoints in app/

Proceed? [Y/n]
```

### Flags

- `--oauth` — adds Google/GitHub/Apple social login to auth screens and backend
- `--dir=<path>` — override output directory (default: `clients/<type>`)

## Introspection Engine

### Module: `Whoosh::ClientGen::Introspector`

Boots the Whoosh app, extracts the OpenAPI 3.1 spec, and builds a normalized Intermediate Representation (IR) consumed by all client generators.

### Process

1. Load Whoosh app from `config.ru` or `app.rb` in project root
2. Call existing OpenAPI generator to produce full spec
3. Parse spec into IR

### Auth detection from OpenAPI

The introspector identifies auth type from the OpenAPI `securitySchemes`:
- `type: http, scheme: bearer` → `:jwt`
- `type: apiKey` → `:api_key`
- `type: oauth2` → `:oauth2`
- No security schemes defined → no auth layer generated, user wires manually
- Auth endpoints are identified by path convention (`/auth/*`) and grouped separately from resources

### Intermediate Representation

```ruby
{
  auth: {
    type: :jwt,                    # :jwt, :api_key, :oauth2
    endpoints: {
      login:    { method: :post, path: "/auth/login", request: { email: :string, password: :string }, response: { token: :string } },
      register: { method: :post, path: "/auth/register", ... },
      refresh:  { method: :post, path: "/auth/refresh", ... },
      logout:   { method: :delete, path: "/auth/logout" }
    },
    oauth_providers: []            # [:google, :github, :apple] when --oauth
  },
  resources: [
    {
      name: :tasks,
      endpoints: [
        { method: :get,    path: "/tasks",     action: :index,   response: { items: [TaskSchema], pagination: true } },
        { method: :get,    path: "/tasks/:id", action: :show,    response: TaskSchema },
        { method: :post,   path: "/tasks",     action: :create,  request: CreateTaskSchema, response: TaskSchema },
        { method: :put,    path: "/tasks/:id", action: :update,  request: UpdateTaskSchema, response: TaskSchema },
        { method: :delete, path: "/tasks/:id", action: :destroy }
      ],
      fields: [
        { name: :title,       type: :string, required: true },
        { name: :description, type: :string, required: false },
        { name: :status,      type: :string, enum: ["pending", "in_progress", "done"], default: "pending" },
        { name: :due_date,    type: :date,   required: false }
      ]
    }
  ],
  streaming: [
    { path: "/events", type: :sse }
  ],
  base_url: "http://localhost:9292"
}
```

### Type Mapping

| OpenAPI Type   | React/TS     | Swift    | Dart       | htmx         |
|----------------|--------------|----------|------------|--------------|
| string         | `string`     | `String` | `String`   | text input   |
| integer        | `number`     | `Int`    | `int`      | number input |
| boolean        | `boolean`    | `Bool`   | `bool`     | checkbox     |
| string(date)   | `string`     | `Date`   | `DateTime` | date input   |
| string(enum)   | union type   | `enum`   | `enum`     | select       |
| array          | `T[]`        | `[T]`    | `List<T>`  | repeated el  |

## Generated Client Architectures

Each generator produces a complete, ready-to-run project with 6 common layers:

1. **API Client** — typed HTTP layer, auth headers, token refresh, base URL config
2. **Models** — typed data classes matching IR schemas
3. **Auth Module** — login/register/logout screens + token storage
4. **Resource Screens** — list, detail, create/edit forms for each resource
5. **Navigation** — routing between screens
6. **Config** — `.env` with `API_URL`

### react_spa (React + Vite + TypeScript)

```
clients/react_spa/
├── src/
│   ├── api/
│   │   ├── client.ts          # Fetch wrapper, auth interceptor, token refresh
│   │   ├── auth.ts            # login(), register(), logout(), refresh()
│   │   └── tasks.ts           # list(), get(), create(), update(), destroy()
│   ├── models/
│   │   └── task.ts            # TypeScript interfaces from IR
│   ├── hooks/
│   │   ├── useAuth.ts         # Auth state + context
│   │   └── useTasks.ts        # CRUD hooks with loading/error states
│   ├── pages/
│   │   ├── Login.tsx
│   │   ├── Register.tsx
│   │   ├── TaskList.tsx
│   │   ├── TaskDetail.tsx
│   │   └── TaskForm.tsx
│   ├── components/
│   │   ├── Layout.tsx
│   │   ├── ProtectedRoute.tsx
│   │   └── Pagination.tsx
│   ├── router.tsx             # React Router
│   ├── App.tsx
│   └── main.tsx
├── .env                       # API_URL=http://localhost:9292
├── index.html
├── package.json
├── vite.config.ts
└── tsconfig.json
```

**Stack:** React 19, Vite, TypeScript, React Router, plain CSS (no UI library)

### expo (Expo + TypeScript)

```
clients/expo/
├── app/
│   ├── (auth)/
│   │   ├── login.tsx
│   │   └── register.tsx
│   ├── (app)/
│   │   ├── tasks/
│   │   │   ├── index.tsx       # List
│   │   │   ├── [id].tsx        # Detail
│   │   │   └── form.tsx        # Create/Edit
│   │   └── _layout.tsx
│   └── _layout.tsx             # Root layout with auth guard
├── src/
│   ├── api/
│   │   ├── client.ts
│   │   ├── auth.ts
│   │   └── tasks.ts
│   ├── models/
│   │   └── task.ts
│   ├── hooks/
│   │   ├── useAuth.ts
│   │   └── useTasks.ts
│   └── store/
│       └── auth.ts             # SecureStore for tokens
├── app.json
├── .env
├── package.json
└── tsconfig.json
```

**Stack:** Expo SDK 52+, Expo Router (file-based), TypeScript, SecureStore for tokens

### ios (Swift + SwiftUI)

```
clients/ios/
├── WhooshApp/
│   ├── App.swift               # Entry point, auth state
│   ├── API/
│   │   ├── APIClient.swift     # URLSession wrapper, auth interceptor
│   │   ├── AuthService.swift
│   │   └── TaskService.swift
│   ├── Models/
│   │   └── Task.swift          # Codable structs
│   ├── Views/
│   │   ├── Auth/
│   │   │   ├── LoginView.swift
│   │   │   └── RegisterView.swift
│   │   └── Tasks/
│   │       ├── TaskListView.swift
│   │       ├── TaskDetailView.swift
│   │       └── TaskFormView.swift
│   ├── ViewModels/
│   │   ├── AuthViewModel.swift
│   │   └── TaskViewModel.swift
│   └── Keychain/
│       └── KeychainHelper.swift  # Token storage
├── WhooshApp.xcodeproj/
├── .env
└── README.md
```

**Stack:** SwiftUI, async/await, URLSession, Keychain for tokens, MVVM

### flutter (Dart)

```
clients/flutter/
├── lib/
│   ├── main.dart
│   ├── api/
│   │   ├── client.dart         # Dio HTTP client, interceptors
│   │   ├── auth_service.dart
│   │   └── task_service.dart
│   ├── models/
│   │   └── task.dart           # Freezed data classes
│   ├── screens/
│   │   ├── auth/
│   │   │   ├── login_screen.dart
│   │   │   └── register_screen.dart
│   │   └── tasks/
│   │       ├── task_list_screen.dart
│   │       ├── task_detail_screen.dart
│   │       └── task_form_screen.dart
│   ├── providers/
│   │   ├── auth_provider.dart
│   │   └── task_provider.dart
│   └── router.dart             # GoRouter
├── pubspec.yaml
├── .env
└── README.md
```

**Stack:** Flutter 3.x, Dio, Riverpod, GoRouter, flutter_secure_storage for tokens

### htmx (Standalone, minimal JS)

A separate static project like the other clients — HTML files that talk to the Whoosh API via htmx attributes.

```
clients/htmx/
├── index.html                  # Entry point, redirects to login or tasks
├── pages/
│   ├── auth/
│   │   ├── login.html          # hx-post to /auth/login
│   │   └── register.html       # hx-post to /auth/register
│   └── tasks/
│       ├── index.html          # hx-get for list, hx-swap for updates
│       ├── show.html           # hx-get for detail
│       └── form.html           # hx-post / hx-put for create/edit
├── js/
│   ├── auth.js                 # Token storage (localStorage), auth headers
│   └── api.js                  # htmx:configRequest interceptor for JWT
├── css/
│   └── style.css               # Minimal styling
├── config.js                   # API_URL configuration
└── README.md
```

**Stack:** htmx 2.x, plain HTML, vanilla JS for auth token handling, no build step. Serve with any static file server.

## Fallback Backend Scaffolding

When no Whoosh app exists or the API is incomplete, the generator scaffolds a standard backend.

### Standard auth endpoints

| Method | Path                         | Description                      |
|--------|------------------------------|----------------------------------|
| POST   | `/auth/register`             | Create account (name, email, pw) |
| POST   | `/auth/login`                | Returns JWT token                |
| POST   | `/auth/refresh`              | Refresh expired token            |
| DELETE | `/auth/logout`               | Invalidate token                 |
| GET    | `/auth/me`                   | Current user profile             |

With `--oauth`, adds:

| Method | Path                         | Description                      |
|--------|------------------------------|----------------------------------|
| GET    | `/auth/:provider`            | Redirect to OAuth provider       |
| GET    | `/auth/:provider/callback`   | Handle OAuth callback, return JWT|

### Standard tasks resource

| Method | Path           | Description              |
|--------|----------------|--------------------------|
| GET    | `/tasks`       | List (cursor-paginated)  |
| GET    | `/tasks/:id`   | Show                     |
| POST   | `/tasks`       | Create                   |
| PUT    | `/tasks/:id`   | Update                   |
| DELETE | `/tasks/:id`   | Destroy                  |

### Generated backend files

```
app/
├── endpoints/
│   ├── auth_endpoint.rb
│   └── tasks_endpoint.rb
├── schemas/
│   ├── auth_schemas.rb         # Login, Register, Token response
│   └── task_schemas.rb         # Create, Update, Task response
├── db/
│   └── migrations/
│       ├── 001_create_users.rb
│       └── 002_create_tasks.rb
```

### Schema conventions

```ruby
class TaskSchema < Whoosh::Schema
  field :title, String, required: true, min_length: 1, max_length: 255, desc: "Task title"
  field :description, String, desc: "Task description"
  field :status, String, enum: %w[pending in_progress done], default: "pending", desc: "Task status"
  field :due_date, Date, desc: "Due date"
end
```

### Password handling

bcrypt via `require "bcrypt"` — hashed on register, verified on login. No plaintext storage.

## Error Handling & Edge Cases

### During introspection

- **App fails to boot** — clear error message, suggest `whoosh check` to debug
- **Empty OpenAPI spec** (app exists but no routes) — treat as "no backend", offer fallback scaffolding
- **Partial API** (has auth but no resources, or vice versa) — show what's found, ask which gaps to fill

### During generation

- **Output directory exists** — prompt: "clients/react_spa/ already exists. Overwrite? [y/N]"
- **Missing platform dependencies** (no `node`, no `flutter` CLI) — detect before generating, warn with install instructions
- **Unknown auth type** (custom middleware) — warn "Custom auth detected, generating API client without auth layer. Wire auth manually."

### In generated clients

- **Token expiry** — auto-refresh on 401 response, redirect to login if refresh fails
- **Network errors** — standardized error handling per platform (toast/alert/snackbar)
- **API validation errors (422)** — map `details[].field` to form field errors
- **Pagination** — cursor-based by default matching Whoosh's `paginate_cursor`

### Platform dependency checks

| Client    | Required         | Check command          |
|-----------|------------------|------------------------|
| react_spa | Node.js 18+      | `node --version`       |
| expo      | Node.js 18+, Expo CLI | `npx expo --version` |
| ios       | Xcode 15+, macOS | `xcodebuild -version`  |
| flutter   | Flutter 3.x, Dart| `flutter --version`    |
| htmx      | Nothing extra     | (runs inside Whoosh)   |

## Testing Strategy

### Generator test suite (in Whoosh's specs)

- **Introspector specs** — feed mock Whoosh apps with various configs, verify IR output
- **Generator specs per platform** — verify file structure, correct type mappings, auth wiring
- **Fallback specs** — verify backend scaffolding when no app exists
- **Integration spec** — boot test Whoosh app, generate client, verify generated files compile/parse

### Tests included in generated clients

| Client    | Test framework        | Coverage                                      |
|-----------|-----------------------|-----------------------------------------------|
| react_spa | Vitest                | API client mocks, auth hooks, form validation |
| expo      | Jest (Expo default)   | Same as react_spa, adapted for RN             |
| ios       | XCTest                | APIClient, ViewModels, Keychain helper        |
| flutter   | flutter_test          | Services, providers, model serialization      |
| htmx      | Whoosh::Test (RSpec)  | HTML endpoint responses, form submissions     |

Each generated project includes 3-5 starter tests covering:

1. Login flow (success + failure)
2. Token storage and refresh
3. CRUD list fetch
4. Form validation errors
