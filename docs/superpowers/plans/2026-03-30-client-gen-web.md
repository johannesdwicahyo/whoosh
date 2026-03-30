# Client Generator — Web Clients Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the `react_spa`, `htmx`, and `telegram_mini_app` client generators that consume the IR from Plan 1.

**Architecture:** Each generator extends `BaseGenerator`, reads the IR, and writes a complete project using ERB-free string templates. All three share the TypeScript/HTML ecosystem.

**Tech Stack:** Ruby (generators), TypeScript/React/Vite (react_spa, telegram_mini_app), HTML/htmx (htmx)

**Depends on:** Plan 1 (Core Engine) must be completed first.

---

## File Structure

```
lib/whoosh/client_gen/generators/
├── react_spa.rb                # React + Vite + TypeScript generator
├── htmx.rb                     # Plain HTML + htmx generator
└── telegram_mini_app.rb        # React + Telegram WebApp SDK generator
spec/whoosh/client_gen/generators/
├── react_spa_spec.rb
├── htmx_spec.rb
└── telegram_mini_app_spec.rb
```

---

### Task 1: React SPA Generator — API Layer

**Files:**
- Create: `lib/whoosh/client_gen/generators/react_spa.rb`
- Test: `spec/whoosh/client_gen/generators/react_spa_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/whoosh/client_gen/generators/react_spa_spec.rb
# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "whoosh/client_gen/ir"
require "whoosh/client_gen/generators/react_spa"

RSpec.describe Whoosh::ClientGen::Generators::ReactSpa do
  let(:ir) do
    Whoosh::ClientGen::IR::AppSpec.new(
      auth: Whoosh::ClientGen::IR::Auth.new(
        type: :jwt,
        endpoints: {
          login: { method: :post, path: "/auth/login" },
          register: { method: :post, path: "/auth/register" },
          refresh: { method: :post, path: "/auth/refresh" },
          logout: { method: :delete, path: "/auth/logout" },
          me: { method: :get, path: "/auth/me" }
        },
        oauth_providers: []
      ),
      resources: [
        Whoosh::ClientGen::IR::Resource.new(
          name: :tasks,
          endpoints: [
            Whoosh::ClientGen::IR::Endpoint.new(method: :get, path: "/tasks", action: :index, pagination: true),
            Whoosh::ClientGen::IR::Endpoint.new(method: :get, path: "/tasks/:id", action: :show),
            Whoosh::ClientGen::IR::Endpoint.new(method: :post, path: "/tasks", action: :create),
            Whoosh::ClientGen::IR::Endpoint.new(method: :put, path: "/tasks/:id", action: :update),
            Whoosh::ClientGen::IR::Endpoint.new(method: :delete, path: "/tasks/:id", action: :destroy)
          ],
          fields: [
            { name: :title, type: :string, required: true },
            { name: :description, type: :string, required: false },
            { name: :status, type: :string, required: false, enum: %w[pending in_progress done], default: "pending" },
            { name: :due_date, type: :string, required: false }
          ]
        )
      ],
      streaming: [],
      base_url: "http://localhost:9292"
    )
  end

  it "generates a complete React SPA project" do
    Dir.mktmpdir do |dir|
      described_class.new(ir: ir, output_dir: dir, platform: :typescript).generate

      # Config files
      expect(File.exist?(File.join(dir, "package.json"))).to be true
      expect(File.exist?(File.join(dir, "tsconfig.json"))).to be true
      expect(File.exist?(File.join(dir, "vite.config.ts"))).to be true
      expect(File.exist?(File.join(dir, "index.html"))).to be true
      expect(File.exist?(File.join(dir, ".env"))).to be true
    end
  end

  it "generates typed API client" do
    Dir.mktmpdir do |dir|
      described_class.new(ir: ir, output_dir: dir, platform: :typescript).generate

      client = File.read(File.join(dir, "src", "api", "client.ts"))
      expect(client).to include("API_URL")
      expect(client).to include("Authorization")
      expect(client).to include("Bearer")
    end
  end

  it "generates auth API module" do
    Dir.mktmpdir do |dir|
      described_class.new(ir: ir, output_dir: dir, platform: :typescript).generate

      auth = File.read(File.join(dir, "src", "api", "auth.ts"))
      expect(auth).to include("login")
      expect(auth).to include("register")
      expect(auth).to include("logout")
      expect(auth).to include("refresh")
    end
  end

  it "generates resource API module for tasks" do
    Dir.mktmpdir do |dir|
      described_class.new(ir: ir, output_dir: dir, platform: :typescript).generate

      tasks = File.read(File.join(dir, "src", "api", "tasks.ts"))
      expect(tasks).to include("listTasks")
      expect(tasks).to include("getTask")
      expect(tasks).to include("createTask")
      expect(tasks).to include("updateTask")
      expect(tasks).to include("deleteTask")
    end
  end

  it "generates TypeScript model interfaces" do
    Dir.mktmpdir do |dir|
      described_class.new(ir: ir, output_dir: dir, platform: :typescript).generate

      model = File.read(File.join(dir, "src", "models", "task.ts"))
      expect(model).to include("interface Task")
      expect(model).to include("title: string")
      expect(model).to include("status: string")
    end
  end

  it "generates React pages" do
    Dir.mktmpdir do |dir|
      described_class.new(ir: ir, output_dir: dir, platform: :typescript).generate

      expect(File.exist?(File.join(dir, "src", "pages", "Login.tsx"))).to be true
      expect(File.exist?(File.join(dir, "src", "pages", "Register.tsx"))).to be true
      expect(File.exist?(File.join(dir, "src", "pages", "TaskList.tsx"))).to be true
      expect(File.exist?(File.join(dir, "src", "pages", "TaskDetail.tsx"))).to be true
      expect(File.exist?(File.join(dir, "src", "pages", "TaskForm.tsx"))).to be true
    end
  end

  it "generates hooks" do
    Dir.mktmpdir do |dir|
      described_class.new(ir: ir, output_dir: dir, platform: :typescript).generate

      expect(File.exist?(File.join(dir, "src", "hooks", "useAuth.ts"))).to be true
      expect(File.exist?(File.join(dir, "src", "hooks", "useTasks.ts"))).to be true
    end
  end

  it "generates router, App, and main entry" do
    Dir.mktmpdir do |dir|
      described_class.new(ir: ir, output_dir: dir, platform: :typescript).generate

      expect(File.exist?(File.join(dir, "src", "router.tsx"))).to be true
      expect(File.exist?(File.join(dir, "src", "App.tsx"))).to be true
      expect(File.exist?(File.join(dir, "src", "main.tsx"))).to be true
    end
  end

  it "generates components" do
    Dir.mktmpdir do |dir|
      described_class.new(ir: ir, output_dir: dir, platform: :typescript).generate

      expect(File.exist?(File.join(dir, "src", "components", "Layout.tsx"))).to be true
      expect(File.exist?(File.join(dir, "src", "components", "ProtectedRoute.tsx"))).to be true
      expect(File.exist?(File.join(dir, "src", "components", "Pagination.tsx"))).to be true
    end
  end

  it "package.json includes correct dependencies" do
    Dir.mktmpdir do |dir|
      described_class.new(ir: ir, output_dir: dir, platform: :typescript).generate

      pkg = File.read(File.join(dir, "package.json"))
      expect(pkg).to include("react")
      expect(pkg).to include("react-router-dom")
      expect(pkg).to include("vite")
      expect(pkg).to include("typescript")
    end
  end

  it ".env contains API_URL" do
    Dir.mktmpdir do |dir|
      described_class.new(ir: ir, output_dir: dir, platform: :typescript).generate

      env = File.read(File.join(dir, ".env"))
      expect(env).to include("VITE_API_URL=http://localhost:9292")
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/whoosh/client_gen/generators/react_spa_spec.rb -v`
Expected: FAIL with "cannot load such file"

- [ ] **Step 3: Write the React SPA generator**

```ruby
# lib/whoosh/client_gen/generators/react_spa.rb
# frozen_string_literal: true

require "json"
require "whoosh/client_gen/base_generator"

module Whoosh
  module ClientGen
    module Generators
      class ReactSpa < BaseGenerator
        def generate
          generate_config_files
          generate_api_client
          generate_auth_api
          generate_models
          generate_resource_apis
          generate_hooks
          generate_pages
          generate_components
          generate_router
          generate_app
          generate_main
          generate_styles
        end

        private

        def generate_config_files
          write_file("package.json", package_json)
          write_file("tsconfig.json", tsconfig_json)
          write_file("vite.config.ts", vite_config)
          write_file("index.html", index_html)
          write_file(".env", "VITE_API_URL=#{ir.base_url}\n")
          write_file(".gitignore", "node_modules/\ndist/\n.env.local\n")
        end

        def generate_api_client
          write_file("src/api/client.ts", <<~TS)
            const API_URL = import.meta.env.VITE_API_URL || "http://localhost:9292";

            let accessToken: string | null = localStorage.getItem("access_token");
            let refreshToken: string | null = localStorage.getItem("refresh_token");

            export function setTokens(access: string, refresh: string) {
              accessToken = access;
              refreshToken = refresh;
              localStorage.setItem("access_token", access);
              localStorage.setItem("refresh_token", refresh);
            }

            export function clearTokens() {
              accessToken = null;
              refreshToken = null;
              localStorage.removeItem("access_token");
              localStorage.removeItem("refresh_token");
            }

            export function getAccessToken(): string | null {
              return accessToken;
            }

            async function refreshAccessToken(): Promise<boolean> {
              if (!refreshToken) return false;
              try {
                const res = await fetch(`${API_URL}/auth/refresh`, {
                  method: "POST",
                  headers: {
                    "Content-Type": "application/json",
                    "Authorization": `Bearer ${accessToken}`,
                  },
                });
                if (!res.ok) return false;
                const data = await res.json();
                setTokens(data.token, data.refresh_token);
                return true;
              } catch {
                return false;
              }
            }

            export async function apiRequest<T>(
              path: string,
              options: RequestInit = {}
            ): Promise<T> {
              const url = `${API_URL}${path}`;
              const headers: Record<string, string> = {
                "Content-Type": "application/json",
                ...(options.headers as Record<string, string>),
              };

              if (accessToken) {
                headers["Authorization"] = `Bearer ${accessToken}`;
              }

              let res = await fetch(url, { ...options, headers });

              if (res.status === 401 && refreshToken) {
                const refreshed = await refreshAccessToken();
                if (refreshed) {
                  headers["Authorization"] = `Bearer ${accessToken}`;
                  res = await fetch(url, { ...options, headers });
                } else {
                  clearTokens();
                  window.location.href = "/login";
                  throw new Error("Session expired");
                }
              }

              if (res.status === 422) {
                const error = await res.json();
                throw { status: 422, details: error.details || [], message: error.error };
              }

              if (!res.ok) {
                const error = await res.json().catch(() => ({ error: "Request failed" }));
                throw { status: res.status, message: error.error };
              }

              return res.json();
            }
          TS
        end

        def generate_auth_api
          write_file("src/api/auth.ts", <<~TS)
            import { apiRequest, setTokens, clearTokens } from "./client";

            interface TokenResponse {
              token: string;
              refresh_token: string;
            }

            interface User {
              id: number;
              name: string;
              email: string;
            }

            export async function login(email: string, password: string): Promise<TokenResponse> {
              const data = await apiRequest<TokenResponse>("/auth/login", {
                method: "POST",
                body: JSON.stringify({ email, password }),
              });
              setTokens(data.token, data.refresh_token);
              return data;
            }

            export async function register(name: string, email: string, password: string): Promise<TokenResponse> {
              const data = await apiRequest<TokenResponse>("/auth/register", {
                method: "POST",
                body: JSON.stringify({ name, email, password }),
              });
              setTokens(data.token, data.refresh_token);
              return data;
            }

            export async function logout(): Promise<void> {
              try {
                await apiRequest("/auth/logout", { method: "DELETE" });
              } finally {
                clearTokens();
              }
            }

            export async function refresh(): Promise<TokenResponse> {
              return apiRequest<TokenResponse>("/auth/refresh", { method: "POST" });
            }

            export async function getMe(): Promise<User> {
              return apiRequest<User>("/auth/me");
            }
          TS
        end

        def generate_models
          ir.resources.each do |resource|
            name = classify(resource.name)
            fields = resource.fields.map { |f|
              ts_type = type_for(f[:type])
              optional = f[:required] ? "" : "?"
              "  #{f[:name]}#{optional}: #{ts_type};"
            }.join("\n")

            write_file("src/models/#{singularize(resource.name.to_s)}.ts", <<~TS)
              export interface #{name} {
                id: number;
              #{fields}
                created_at?: string;
                updated_at?: string;
              }

              export interface Create#{name}Input {
              #{resource.fields.select { |f| f[:required] }.map { |f| "  #{f[:name]}: #{type_for(f[:type])};" }.join("\n")}
              #{resource.fields.reject { |f| f[:required] }.map { |f| "  #{f[:name]}?: #{type_for(f[:type])};" }.join("\n")}
              }

              export interface Update#{name}Input {
              #{resource.fields.map { |f| "  #{f[:name]}?: #{type_for(f[:type])};" }.join("\n")}
              }
            TS
          end
        end

        def generate_resource_apis
          ir.resources.each do |resource|
            name = classify(resource.name)
            singular = singularize(resource.name.to_s)
            plural = resource.name.to_s
            base_path = "/#{plural}"

            methods = []

            resource.endpoints.each do |ep|
              case ep.action
              when :index
                methods << <<~TS
                  export async function list#{name}s(cursor?: string, limit: number = 20): Promise<{ items: #{name}[]; next_cursor: string | null }> {
                    const params = new URLSearchParams();
                    if (cursor) params.set("cursor", cursor);
                    params.set("limit", String(limit));
                    return apiRequest(`#{base_path}?${params}`);
                  }
                TS
              when :show
                methods << <<~TS
                  export async function get#{name}(id: number | string): Promise<#{name}> {
                    return apiRequest(`#{base_path}/${id}`);
                  }
                TS
              when :create
                methods << <<~TS
                  export async function create#{name}(input: Create#{name}Input): Promise<#{name}> {
                    return apiRequest(`#{base_path}`, {
                      method: "POST",
                      body: JSON.stringify(input),
                    });
                  }
                TS
              when :update
                methods << <<~TS
                  export async function update#{name}(id: number | string, input: Update#{name}Input): Promise<#{name}> {
                    return apiRequest(`#{base_path}/${id}`, {
                      method: "PUT",
                      body: JSON.stringify(input),
                    });
                  }
                TS
              when :destroy
                methods << <<~TS
                  export async function delete#{name}(id: number | string): Promise<void> {
                    await apiRequest(`#{base_path}/${id}`, { method: "DELETE" });
                  }
                TS
              end
            end

            write_file("src/api/#{plural}.ts", <<~TS)
              import { apiRequest } from "./client";
              import type { #{name}, Create#{name}Input, Update#{name}Input } from "../models/#{singular}";

              #{methods.join("\n")}
            TS
          end
        end

        def generate_hooks
          write_file("src/hooks/useAuth.ts", <<~TS)
            import { createContext, useContext, useState, useCallback, useEffect } from "react";
            import type { ReactNode } from "react";
            import { login as apiLogin, register as apiRegister, logout as apiLogout, getMe } from "../api/auth";
            import { getAccessToken, clearTokens } from "../api/client";

            interface User {
              id: number;
              name: string;
              email: string;
            }

            interface AuthContextType {
              user: User | null;
              loading: boolean;
              login: (email: string, password: string) => Promise<void>;
              register: (name: string, email: string, password: string) => Promise<void>;
              logout: () => Promise<void>;
              isAuthenticated: boolean;
            }

            export const AuthContext = createContext<AuthContextType | null>(null);

            export function useAuth(): AuthContextType {
              const ctx = useContext(AuthContext);
              if (!ctx) throw new Error("useAuth must be used within AuthProvider");
              return ctx;
            }

            export function useAuthProvider(): AuthContextType {
              const [user, setUser] = useState<User | null>(null);
              const [loading, setLoading] = useState(true);

              useEffect(() => {
                if (getAccessToken()) {
                  getMe().then(setUser).catch(() => clearTokens()).finally(() => setLoading(false));
                } else {
                  setLoading(false);
                }
              }, []);

              const login = useCallback(async (email: string, password: string) => {
                await apiLogin(email, password);
                const me = await getMe();
                setUser(me);
              }, []);

              const register = useCallback(async (name: string, email: string, password: string) => {
                await apiRegister(name, email, password);
                const me = await getMe();
                setUser(me);
              }, []);

              const logout = useCallback(async () => {
                await apiLogout();
                setUser(null);
              }, []);

              return { user, loading, login, register, logout, isAuthenticated: !!user };
            }
          TS

          ir.resources.each do |resource|
            name = classify(resource.name)
            plural = resource.name.to_s
            singular = singularize(plural)

            write_file("src/hooks/use#{name}s.ts", <<~TS)
              import { useState, useCallback } from "react";
              import type { #{name}, Create#{name}Input, Update#{name}Input } from "../models/#{singular}";
              import { list#{name}s, get#{name}, create#{name}, update#{name}, delete#{name} } from "../api/#{plural}";

              export function use#{name}s() {
                const [items, setItems] = useState<#{name}[]>([]);
                const [loading, setLoading] = useState(false);
                const [error, setError] = useState<string | null>(null);
                const [cursor, setCursor] = useState<string | null>(null);

                const fetchAll = useCallback(async (nextCursor?: string) => {
                  setLoading(true);
                  setError(null);
                  try {
                    const data = await list#{name}s(nextCursor);
                    setItems(prev => nextCursor ? [...prev, ...data.items] : data.items);
                    setCursor(data.next_cursor);
                  } catch (e: any) {
                    setError(e.message || "Failed to load");
                  } finally {
                    setLoading(false);
                  }
                }, []);

                const create = useCallback(async (input: Create#{name}Input) => {
                  const item = await create#{name}(input);
                  setItems(prev => [item, ...prev]);
                  return item;
                }, []);

                const update = useCallback(async (id: number | string, input: Update#{name}Input) => {
                  const item = await update#{name}(id, input);
                  setItems(prev => prev.map(i => i.id === item.id ? item : i));
                  return item;
                }, []);

                const remove = useCallback(async (id: number | string) => {
                  await delete#{name}(id);
                  setItems(prev => prev.filter(i => i.id !== Number(id)));
                }, []);

                return { items, loading, error, cursor, fetchAll, create, update, remove };
              }
            TS
          end
        end

        def generate_pages
          generate_login_page
          generate_register_page

          ir.resources.each do |resource|
            generate_list_page(resource)
            generate_detail_page(resource)
            generate_form_page(resource)
          end
        end

        def generate_login_page
          write_file("src/pages/Login.tsx", <<~TSX)
            import { useState } from "react";
            import { useAuth } from "../hooks/useAuth";
            import { useNavigate, Link } from "react-router-dom";

            export default function Login() {
              const { login } = useAuth();
              const navigate = useNavigate();
              const [email, setEmail] = useState("");
              const [password, setPassword] = useState("");
              const [error, setError] = useState<string | null>(null);
              const [loading, setLoading] = useState(false);

              async function handleSubmit(e: React.FormEvent) {
                e.preventDefault();
                setLoading(true);
                setError(null);
                try {
                  await login(email, password);
                  navigate("/");
                } catch (err: any) {
                  setError(err.message || "Login failed");
                } finally {
                  setLoading(false);
                }
              }

              return (
                <div className="auth-page">
                  <h1>Login</h1>
                  {error && <div className="error">{error}</div>}
                  <form onSubmit={handleSubmit}>
                    <label>
                      Email
                      <input type="email" value={email} onChange={e => setEmail(e.target.value)} required />
                    </label>
                    <label>
                      Password
                      <input type="password" value={password} onChange={e => setPassword(e.target.value)} required />
                    </label>
                    <button type="submit" disabled={loading}>{loading ? "Logging in..." : "Login"}</button>
                  </form>
                  <p>Don't have an account? <Link to="/register">Register</Link></p>
                </div>
              );
            }
          TSX
        end

        def generate_register_page
          write_file("src/pages/Register.tsx", <<~TSX)
            import { useState } from "react";
            import { useAuth } from "../hooks/useAuth";
            import { useNavigate, Link } from "react-router-dom";

            export default function Register() {
              const { register } = useAuth();
              const navigate = useNavigate();
              const [name, setName] = useState("");
              const [email, setEmail] = useState("");
              const [password, setPassword] = useState("");
              const [error, setError] = useState<string | null>(null);
              const [fieldErrors, setFieldErrors] = useState<Record<string, string>>({});
              const [loading, setLoading] = useState(false);

              async function handleSubmit(e: React.FormEvent) {
                e.preventDefault();
                setLoading(true);
                setError(null);
                setFieldErrors({});
                try {
                  await register(name, email, password);
                  navigate("/");
                } catch (err: any) {
                  if (err.status === 422 && err.details) {
                    const errors: Record<string, string> = {};
                    err.details.forEach((d: any) => { errors[d.field] = d.message; });
                    setFieldErrors(errors);
                  } else {
                    setError(err.message || "Registration failed");
                  }
                } finally {
                  setLoading(false);
                }
              }

              return (
                <div className="auth-page">
                  <h1>Register</h1>
                  {error && <div className="error">{error}</div>}
                  <form onSubmit={handleSubmit}>
                    <label>
                      Name
                      <input type="text" value={name} onChange={e => setName(e.target.value)} required />
                      {fieldErrors.name && <span className="field-error">{fieldErrors.name}</span>}
                    </label>
                    <label>
                      Email
                      <input type="email" value={email} onChange={e => setEmail(e.target.value)} required />
                      {fieldErrors.email && <span className="field-error">{fieldErrors.email}</span>}
                    </label>
                    <label>
                      Password
                      <input type="password" value={password} onChange={e => setPassword(e.target.value)} required minLength={8} />
                      {fieldErrors.password && <span className="field-error">{fieldErrors.password}</span>}
                    </label>
                    <button type="submit" disabled={loading}>{loading ? "Registering..." : "Register"}</button>
                  </form>
                  <p>Already have an account? <Link to="/login">Login</Link></p>
                </div>
              );
            }
          TSX
        end

        def generate_list_page(resource)
          name = classify(resource.name)
          plural = resource.name.to_s
          singular = singularize(plural)

          write_file("src/pages/#{name}List.tsx", <<~TSX)
            import { useEffect } from "react";
            import { Link } from "react-router-dom";
            import { use#{name}s } from "../hooks/use#{name}s";
            import Pagination from "../components/Pagination";

            export default function #{name}List() {
              const { items, loading, error, cursor, fetchAll, remove } = use#{name}s();

              useEffect(() => { fetchAll(); }, [fetchAll]);

              if (loading && items.length === 0) return <p>Loading...</p>;
              if (error) return <p className="error">{error}</p>;

              return (
                <div>
                  <div className="list-header">
                    <h1>#{name}s</h1>
                    <Link to="/#{plural}/new" className="btn">New #{name}</Link>
                  </div>
                  {items.length === 0 ? (
                    <p>No #{plural} yet.</p>
                  ) : (
                    <ul className="resource-list">
                      {items.map(item => (
                        <li key={item.id}>
                          <Link to={`/#{plural}/${item.id}`}>{item.#{resource.fields.first&.dig(:name) || "id"}}</Link>
                          <button className="btn-danger" onClick={() => remove(item.id)}>Delete</button>
                        </li>
                      ))}
                    </ul>
                  )}
                  <Pagination cursor={cursor} loading={loading} onLoadMore={() => fetchAll(cursor!)} />
                </div>
              );
            }
          TSX
        end

        def generate_detail_page(resource)
          name = classify(resource.name)
          plural = resource.name.to_s
          singular = singularize(plural)

          field_display = resource.fields.map { |f|
            "            <dt>#{f[:name]}</dt>\n            <dd>{#{singular}.#{f[:name]} ?? \"-\"}</dd>"
          }.join("\n")

          write_file("src/pages/#{name}Detail.tsx", <<~TSX)
            import { useEffect, useState } from "react";
            import { useParams, Link, useNavigate } from "react-router-dom";
            import { get#{name}, delete#{name} } from "../api/#{plural}";
            import type { #{name} } from "../models/#{singular}";

            export default function #{name}Detail() {
              const { id } = useParams<{ id: string }>();
              const navigate = useNavigate();
              const [#{singular}, set#{name}] = useState<#{name} | null>(null);
              const [loading, setLoading] = useState(true);

              useEffect(() => {
                if (id) get#{name}(id).then(set#{name}).finally(() => setLoading(false));
              }, [id]);

              async function handleDelete() {
                if (id && confirm("Delete this #{singular}?")) {
                  await delete#{name}(id);
                  navigate("/#{plural}");
                }
              }

              if (loading) return <p>Loading...</p>;
              if (!#{singular}) return <p>Not found</p>;

              return (
                <div>
                  <h1>#{name} #{"{"}#{singular}.id{"}"}</h1>
                  <dl>
            #{field_display}
                  </dl>
                  <div className="actions">
                    <Link to={`/#{plural}/${id}/edit`} className="btn">Edit</Link>
                    <button className="btn-danger" onClick={handleDelete}>Delete</button>
                    <Link to="/#{plural}">Back to list</Link>
                  </div>
                </div>
              );
            }
          TSX
        end

        def generate_form_page(resource)
          name = classify(resource.name)
          plural = resource.name.to_s
          singular = singularize(plural)

          state_inits = resource.fields.map { |f|
            default = f[:default] ? "\"#{f[:default]}\"" : "\"\""
            "  const [#{f[:name]}, set#{camelize(f[:name].to_s)}] = useState(#{default});"
          }.join("\n")

          load_fields = resource.fields.map { |f|
            "        set#{camelize(f[:name].to_s)}(data.#{f[:name]} ?? \"\");"
          }.join("\n")

          form_fields = resource.fields.map { |f|
            if f[:enum]
              options = f[:enum].map { |v| "              <option value=\"#{v}\">#{v}</option>" }.join("\n")
              <<~TSX.strip
                          <label>
                            #{f[:name]}
                            <select value={#{f[:name]}} onChange={e => set#{camelize(f[:name].to_s)}(e.target.value)}>
                              <option value="">Select...</option>
                #{options}
                            </select>
                            {fieldErrors.#{f[:name]} && <span className="field-error">{fieldErrors.#{f[:name]}}</span>}
                          </label>
              TSX
            else
              input_type = f[:type] == :string && f[:name].to_s.include?("date") ? "date" : "text"
              required = f[:required] ? " required" : ""
              <<~TSX.strip
                          <label>
                            #{f[:name]}
                            <input type="#{input_type}" value={#{f[:name]}} onChange={e => set#{camelize(f[:name].to_s)}(e.target.value)}#{required} />
                            {fieldErrors.#{f[:name]} && <span className="field-error">{fieldErrors.#{f[:name]}}</span>}
                          </label>
              TSX
            end
          }.join("\n")

          body_fields = resource.fields.map { |f| "#{f[:name]}" }.join(", ")

          write_file("src/pages/#{name}Form.tsx", <<~TSX)
            import { useState, useEffect } from "react";
            import { useParams, useNavigate } from "react-router-dom";
            import { create#{name}, update#{name}, get#{name} } from "../api/#{plural}";

            export default function #{name}Form() {
              const { id } = useParams<{ id: string }>();
              const navigate = useNavigate();
              const isEditing = Boolean(id);
            #{state_inits}
              const [error, setError] = useState<string | null>(null);
              const [fieldErrors, setFieldErrors] = useState<Record<string, string>>({});
              const [loading, setLoading] = useState(false);

              useEffect(() => {
                if (id) {
                  get#{name}(id).then(data => {
            #{load_fields}
                  });
                }
              }, [id]);

              async function handleSubmit(e: React.FormEvent) {
                e.preventDefault();
                setLoading(true);
                setError(null);
                setFieldErrors({});
                try {
                  const body = { #{body_fields} };
                  if (isEditing) {
                    await update#{name}(id!, body);
                  } else {
                    await create#{name}(body);
                  }
                  navigate("/#{plural}");
                } catch (err: any) {
                  if (err.status === 422 && err.details) {
                    const errors: Record<string, string> = {};
                    err.details.forEach((d: any) => { errors[d.field] = d.message; });
                    setFieldErrors(errors);
                  } else {
                    setError(err.message || "Failed to save");
                  }
                } finally {
                  setLoading(false);
                }
              }

              return (
                <div>
                  <h1>{isEditing ? "Edit" : "New"} #{name}</h1>
                  {error && <div className="error">{error}</div>}
                  <form onSubmit={handleSubmit}>
            #{form_fields}
                    <button type="submit" disabled={loading}>{loading ? "Saving..." : "Save"}</button>
                  </form>
                </div>
              );
            }
          TSX
        end

        def generate_components
          write_file("src/components/Layout.tsx", <<~TSX)
            import { Outlet, Link } from "react-router-dom";
            import { useAuth } from "../hooks/useAuth";

            export default function Layout() {
              const { user, logout, isAuthenticated } = useAuth();

              return (
                <div className="layout">
                  <nav>
                    <Link to="/" className="brand">Whoosh App</Link>
                    {isAuthenticated && (
                      <div className="nav-links">
            #{ir.resources.map { |r| "              <Link to=\"/#{r.name}\">#{classify(r.name)}s</Link>" }.join("\n")}
                        <span>{user?.name}</span>
                        <button onClick={logout}>Logout</button>
                      </div>
                    )}
                  </nav>
                  <main>
                    <Outlet />
                  </main>
                </div>
              );
            }
          TSX

          write_file("src/components/ProtectedRoute.tsx", <<~TSX)
            import { Navigate } from "react-router-dom";
            import { useAuth } from "../hooks/useAuth";

            export default function ProtectedRoute({ children }: { children: React.ReactNode }) {
              const { isAuthenticated, loading } = useAuth();
              if (loading) return <p>Loading...</p>;
              if (!isAuthenticated) return <Navigate to="/login" replace />;
              return <>{children}</>;
            }
          TSX

          write_file("src/components/Pagination.tsx", <<~TSX)
            interface Props {
              cursor: string | null;
              loading: boolean;
              onLoadMore: () => void;
            }

            export default function Pagination({ cursor, loading, onLoadMore }: Props) {
              if (!cursor) return null;
              return (
                <div className="pagination">
                  <button onClick={onLoadMore} disabled={loading}>
                    {loading ? "Loading..." : "Load more"}
                  </button>
                </div>
              );
            }
          TSX
        end

        def generate_router
          resource_routes = ir.resources.flat_map { |r|
            name = classify(r.name)
            plural = r.name.to_s
            [
              "          <Route path=\"/#{plural}\" element={<ProtectedRoute><#{name}List /></ProtectedRoute>} />",
              "          <Route path=\"/#{plural}/new\" element={<ProtectedRoute><#{name}Form /></ProtectedRoute>} />",
              "          <Route path=\"/#{plural}/:id\" element={<ProtectedRoute><#{name}Detail /></ProtectedRoute>} />",
              "          <Route path=\"/#{plural}/:id/edit\" element={<ProtectedRoute><#{name}Form /></ProtectedRoute>} />"
            ]
          }.join("\n")

          page_imports = ir.resources.flat_map { |r|
            name = classify(r.name)
            [
              "import #{name}List from \"./pages/#{name}List\";",
              "import #{name}Detail from \"./pages/#{name}Detail\";",
              "import #{name}Form from \"./pages/#{name}Form\";"
            ]
          }.join("\n")

          first_resource = ir.resources.first
          home_redirect = first_resource ? "/#{first_resource.name}" : "/login"

          write_file("src/router.tsx", <<~TSX)
            import { BrowserRouter, Routes, Route, Navigate } from "react-router-dom";
            import Layout from "./components/Layout";
            import ProtectedRoute from "./components/ProtectedRoute";
            import Login from "./pages/Login";
            import Register from "./pages/Register";
            #{page_imports}

            export default function AppRouter() {
              return (
                <BrowserRouter>
                  <Routes>
                    <Route element={<Layout />}>
                      <Route path="/login" element={<Login />} />
                      <Route path="/register" element={<Register />} />
            #{resource_routes}
                      <Route path="/" element={<Navigate to="#{home_redirect}" replace />} />
                    </Route>
                  </Routes>
                </BrowserRouter>
              );
            }
          TSX
        end

        def generate_app
          write_file("src/App.tsx", <<~TSX)
            import { AuthContext, useAuthProvider } from "./hooks/useAuth";
            import AppRouter from "./router";

            export default function App() {
              const auth = useAuthProvider();

              return (
                <AuthContext.Provider value={auth}>
                  <AppRouter />
                </AuthContext.Provider>
              );
            }
          TSX
        end

        def generate_main
          write_file("src/main.tsx", <<~TSX)
            import { StrictMode } from "react";
            import { createRoot } from "react-dom/client";
            import App from "./App";
            import "./styles.css";

            createRoot(document.getElementById("root")!).render(
              <StrictMode>
                <App />
              </StrictMode>
            );
          TSX
        end

        def generate_styles
          write_file("src/styles.css", <<~CSS)
            * { box-sizing: border-box; margin: 0; padding: 0; }
            body { font-family: system-ui, -apple-system, sans-serif; line-height: 1.6; color: #1a1a1a; background: #f5f5f5; }
            .layout { max-width: 800px; margin: 0 auto; padding: 0 1rem; }
            nav { display: flex; justify-content: space-between; align-items: center; padding: 1rem 0; border-bottom: 1px solid #ddd; margin-bottom: 2rem; }
            .brand { font-weight: 700; font-size: 1.2rem; text-decoration: none; color: #1a1a1a; }
            .nav-links { display: flex; gap: 1rem; align-items: center; }
            .nav-links a { text-decoration: none; color: #4a4a4a; }
            h1 { margin-bottom: 1rem; }
            form { display: flex; flex-direction: column; gap: 1rem; max-width: 400px; }
            label { display: flex; flex-direction: column; gap: 0.25rem; font-weight: 500; }
            input, select { padding: 0.5rem; border: 1px solid #ccc; border-radius: 4px; font-size: 1rem; }
            button, .btn { padding: 0.5rem 1rem; border: none; border-radius: 4px; cursor: pointer; font-size: 1rem; background: #2563eb; color: white; text-decoration: none; display: inline-block; }
            button:disabled { opacity: 0.6; cursor: not-allowed; }
            .btn-danger { background: #dc2626; }
            .error { background: #fef2f2; color: #dc2626; padding: 0.75rem; border-radius: 4px; margin-bottom: 1rem; }
            .field-error { color: #dc2626; font-size: 0.875rem; }
            .list-header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 1rem; }
            .resource-list { list-style: none; }
            .resource-list li { display: flex; justify-content: space-between; align-items: center; padding: 0.75rem; background: white; border-radius: 4px; margin-bottom: 0.5rem; }
            .resource-list a { text-decoration: none; color: #2563eb; }
            dl { display: grid; grid-template-columns: auto 1fr; gap: 0.5rem 1rem; }
            dt { font-weight: 600; }
            .actions { display: flex; gap: 0.5rem; margin-top: 1rem; align-items: center; }
            .actions a { text-decoration: none; color: #4a4a4a; }
            .pagination { margin-top: 1rem; text-align: center; }
            .auth-page { max-width: 400px; margin: 2rem auto; }
          CSS
        end

        def package_json
          JSON.pretty_generate({
            name: "whoosh-client",
            private: true,
            version: "0.1.0",
            type: "module",
            scripts: {
              dev: "vite",
              build: "tsc && vite build",
              preview: "vite preview"
            },
            dependencies: {
              react: "^19.0.0",
              "react-dom": "^19.0.0",
              "react-router-dom": "^7.0.0"
            },
            devDependencies: {
              "@types/react": "^19.0.0",
              "@types/react-dom": "^19.0.0",
              "@vitejs/plugin-react": "^4.3.0",
              typescript: "^5.6.0",
              vite: "^6.0.0"
            }
          })
        end

        def tsconfig_json
          JSON.pretty_generate({
            compilerOptions: {
              target: "ES2020",
              useDefineForClassFields: true,
              lib: ["ES2020", "DOM", "DOM.Iterable"],
              module: "ESNext",
              skipLibCheck: true,
              moduleResolution: "bundler",
              allowImportingTsExtensions: true,
              isolatedModules: true,
              moduleDetection: "force",
              noEmit: true,
              jsx: "react-jsx",
              strict: true,
              noUnusedLocals: true,
              noUnusedParameters: true,
              noFallthroughCasesInSwitch: true,
              noUncheckedSideEffectImports: true
            },
            include: ["src"]
          })
        end

        def vite_config
          <<~TS
            import { defineConfig } from "vite";
            import react from "@vitejs/plugin-react";

            export default defineConfig({
              plugins: [react()],
              server: {
                port: 3000,
                proxy: {
                  "/api": {
                    target: process.env.VITE_API_URL || "http://localhost:9292",
                    changeOrigin: true,
                    rewrite: (path) => path.replace(/^\\/api/, ""),
                  },
                },
              },
            });
          TS
        end

        def index_html
          <<~HTML
            <!DOCTYPE html>
            <html lang="en">
              <head>
                <meta charset="UTF-8" />
                <meta name="viewport" content="width=device-width, initial-scale=1.0" />
                <title>Whoosh App</title>
              </head>
              <body>
                <div id="root"></div>
                <script type="module" src="/src/main.tsx"></script>
              </body>
            </html>
          HTML
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/whoosh/client_gen/generators/react_spa_spec.rb -v`
Expected: All 11 examples pass

- [ ] **Step 5: Commit**

```bash
git add lib/whoosh/client_gen/generators/react_spa.rb spec/whoosh/client_gen/generators/react_spa_spec.rb
git commit -m "feat: add React SPA client generator"
```

---

### Task 2: htmx Generator

**Files:**
- Create: `lib/whoosh/client_gen/generators/htmx.rb`
- Test: `spec/whoosh/client_gen/generators/htmx_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/whoosh/client_gen/generators/htmx_spec.rb
# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "whoosh/client_gen/ir"
require "whoosh/client_gen/generators/htmx"

RSpec.describe Whoosh::ClientGen::Generators::Htmx do
  let(:ir) do
    Whoosh::ClientGen::IR::AppSpec.new(
      auth: Whoosh::ClientGen::IR::Auth.new(
        type: :jwt,
        endpoints: {
          login: { method: :post, path: "/auth/login" },
          register: { method: :post, path: "/auth/register" }
        }
      ),
      resources: [
        Whoosh::ClientGen::IR::Resource.new(
          name: :tasks,
          endpoints: [
            Whoosh::ClientGen::IR::Endpoint.new(method: :get, path: "/tasks", action: :index),
            Whoosh::ClientGen::IR::Endpoint.new(method: :get, path: "/tasks/:id", action: :show),
            Whoosh::ClientGen::IR::Endpoint.new(method: :post, path: "/tasks", action: :create),
            Whoosh::ClientGen::IR::Endpoint.new(method: :put, path: "/tasks/:id", action: :update),
            Whoosh::ClientGen::IR::Endpoint.new(method: :delete, path: "/tasks/:id", action: :destroy)
          ],
          fields: [
            { name: :title, type: :string, required: true },
            { name: :status, type: :string, required: false, enum: %w[pending done] }
          ]
        )
      ],
      streaming: [],
      base_url: "http://localhost:9292"
    )
  end

  it "generates index.html with htmx script" do
    Dir.mktmpdir do |dir|
      described_class.new(ir: ir, output_dir: dir, platform: :html).generate

      index = File.read(File.join(dir, "index.html"))
      expect(index).to include("htmx")
      expect(index).to include("<!DOCTYPE html>")
    end
  end

  it "generates auth pages" do
    Dir.mktmpdir do |dir|
      described_class.new(ir: ir, output_dir: dir, platform: :html).generate

      expect(File.exist?(File.join(dir, "pages", "auth", "login.html"))).to be true
      expect(File.exist?(File.join(dir, "pages", "auth", "register.html"))).to be true

      login = File.read(File.join(dir, "pages", "auth", "login.html"))
      expect(login).to include("hx-post")
      expect(login).to include("/auth/login")
    end
  end

  it "generates resource pages" do
    Dir.mktmpdir do |dir|
      described_class.new(ir: ir, output_dir: dir, platform: :html).generate

      expect(File.exist?(File.join(dir, "pages", "tasks", "index.html"))).to be true
      expect(File.exist?(File.join(dir, "pages", "tasks", "form.html"))).to be true
    end
  end

  it "generates auth.js for token management" do
    Dir.mktmpdir do |dir|
      described_class.new(ir: ir, output_dir: dir, platform: :html).generate

      auth = File.read(File.join(dir, "js", "auth.js"))
      expect(auth).to include("localStorage")
      expect(auth).to include("Authorization")
    end
  end

  it "generates config.js with API_URL" do
    Dir.mktmpdir do |dir|
      described_class.new(ir: ir, output_dir: dir, platform: :html).generate

      config = File.read(File.join(dir, "config.js"))
      expect(config).to include("http://localhost:9292")
    end
  end

  it "generates css/style.css" do
    Dir.mktmpdir do |dir|
      described_class.new(ir: ir, output_dir: dir, platform: :html).generate

      expect(File.exist?(File.join(dir, "css", "style.css"))).to be true
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/whoosh/client_gen/generators/htmx_spec.rb -v`
Expected: FAIL with "cannot load such file"

- [ ] **Step 3: Write the htmx generator**

```ruby
# lib/whoosh/client_gen/generators/htmx.rb
# frozen_string_literal: true

require "whoosh/client_gen/base_generator"

module Whoosh
  module ClientGen
    module Generators
      class Htmx < BaseGenerator
        def generate
          generate_index
          generate_config
          generate_auth_js
          generate_api_js
          generate_styles
          generate_auth_pages
          generate_resource_pages
          generate_readme
        end

        private

        def generate_index
          nav_links = ir.resources.map { |r|
            "      <a href=\"pages/#{r.name}/index.html\">#{classify(r.name)}s</a>"
          }.join("\n")

          write_file("index.html", <<~HTML)
            <!DOCTYPE html>
            <html lang="en">
            <head>
              <meta charset="UTF-8">
              <meta name="viewport" content="width=device-width, initial-scale=1.0">
              <title>Whoosh App</title>
              <script src="https://unpkg.com/htmx.org@2.0.0"></script>
              <script src="config.js"></script>
              <script src="js/auth.js"></script>
              <script src="js/api.js"></script>
              <link rel="stylesheet" href="css/style.css">
            </head>
            <body>
              <nav>
                <a href="index.html" class="brand">Whoosh App</a>
                <div id="nav-links">
            #{nav_links}
                  <span id="user-name"></span>
                  <button onclick="handleLogout()">Logout</button>
                </div>
              </nav>
              <main id="content">
                <p>Redirecting...</p>
              </main>
              <script>
                if (!getToken()) {
                  window.location.href = "pages/auth/login.html";
                } else {
                  window.location.href = "pages/#{ir.resources.first&.name || "auth/login"}/index.html";
                }
              </script>
            </body>
            </html>
          HTML
        end

        def generate_config
          write_file("config.js", <<~JS)
            const API_URL = "#{ir.base_url}";
          JS
        end

        def generate_auth_js
          write_file("js/auth.js", <<~JS)
            function getToken() {
              return localStorage.getItem("access_token");
            }

            function setTokens(access, refresh) {
              localStorage.setItem("access_token", access);
              localStorage.setItem("refresh_token", refresh);
            }

            function clearTokens() {
              localStorage.removeItem("access_token");
              localStorage.removeItem("refresh_token");
            }

            function requireAuth() {
              if (!getToken()) {
                window.location.href = "/pages/auth/login.html";
              }
            }

            async function handleLogout() {
              try {
                await fetch(API_URL + "/auth/logout", {
                  method: "DELETE",
                  headers: { "Authorization": "Bearer " + getToken() }
                });
              } finally {
                clearTokens();
                window.location.href = "/pages/auth/login.html";
              }
            }

            document.addEventListener("htmx:configRequest", function(event) {
              const token = getToken();
              if (token) {
                event.detail.headers["Authorization"] = "Bearer " + token;
              }
              event.detail.headers["Content-Type"] = "application/json";
            });
          JS
        end

        def generate_api_js
          write_file("js/api.js", <<~JS)
            async function apiRequest(path, options = {}) {
              const url = API_URL + path;
              const headers = {
                "Content-Type": "application/json",
                ...(options.headers || {})
              };

              const token = getToken();
              if (token) {
                headers["Authorization"] = "Bearer " + token;
              }

              const res = await fetch(url, { ...options, headers });

              if (res.status === 401) {
                clearTokens();
                window.location.href = "/pages/auth/login.html";
                return;
              }

              return res.json();
            }

            async function handleLogin(event) {
              event.preventDefault();
              const form = event.target;
              const data = {
                email: form.email.value,
                password: form.password.value
              };

              try {
                const result = await apiRequest("/auth/login", {
                  method: "POST",
                  body: JSON.stringify(data)
                });
                if (result.token) {
                  setTokens(result.token, result.refresh_token);
                  window.location.href = "/index.html";
                }
              } catch (e) {
                document.getElementById("error").textContent = "Login failed";
              }
            }

            async function handleRegister(event) {
              event.preventDefault();
              const form = event.target;
              const data = {
                name: form.name.value,
                email: form.email.value,
                password: form.password.value
              };

              try {
                const result = await apiRequest("/auth/register", {
                  method: "POST",
                  body: JSON.stringify(data)
                });
                if (result.token) {
                  setTokens(result.token, result.refresh_token);
                  window.location.href = "/index.html";
                }
              } catch (e) {
                document.getElementById("error").textContent = "Registration failed";
              }
            }
          JS
        end

        def generate_styles
          write_file("css/style.css", <<~CSS)
            * { box-sizing: border-box; margin: 0; padding: 0; }
            body { font-family: system-ui, sans-serif; line-height: 1.6; color: #1a1a1a; background: #f5f5f5; max-width: 800px; margin: 0 auto; padding: 1rem; }
            nav { display: flex; justify-content: space-between; align-items: center; padding: 1rem 0; border-bottom: 1px solid #ddd; margin-bottom: 2rem; }
            .brand { font-weight: 700; font-size: 1.2rem; text-decoration: none; color: #1a1a1a; }
            #nav-links { display: flex; gap: 1rem; align-items: center; }
            #nav-links a { text-decoration: none; color: #4a4a4a; }
            h1 { margin-bottom: 1rem; }
            form { display: flex; flex-direction: column; gap: 1rem; max-width: 400px; }
            label { display: flex; flex-direction: column; gap: 0.25rem; font-weight: 500; }
            input, select { padding: 0.5rem; border: 1px solid #ccc; border-radius: 4px; font-size: 1rem; }
            button, .btn { padding: 0.5rem 1rem; border: none; border-radius: 4px; cursor: pointer; font-size: 1rem; background: #2563eb; color: white; text-decoration: none; }
            .btn-danger { background: #dc2626; }
            .error { background: #fef2f2; color: #dc2626; padding: 0.75rem; border-radius: 4px; margin-bottom: 1rem; }
            .list-header { display: flex; justify-content: space-between; align-items: center; }
            table { width: 100%; border-collapse: collapse; margin-top: 1rem; }
            th, td { text-align: left; padding: 0.5rem; border-bottom: 1px solid #ddd; }
            .actions { display: flex; gap: 0.5rem; margin-top: 1rem; }
          CSS
        end

        def generate_auth_pages
          write_file("pages/auth/login.html", <<~HTML)
            <!DOCTYPE html>
            <html lang="en">
            <head>
              <meta charset="UTF-8">
              <meta name="viewport" content="width=device-width, initial-scale=1.0">
              <title>Login</title>
              <script src="https://unpkg.com/htmx.org@2.0.0"></script>
              <script src="../../config.js"></script>
              <script src="../../js/auth.js"></script>
              <script src="../../js/api.js"></script>
              <link rel="stylesheet" href="../../css/style.css">
            </head>
            <body>
              <h1>Login</h1>
              <div id="error" class="error" style="display:none"></div>
              <form onsubmit="handleLogin(event)" hx-post="#{ir.base_url}/auth/login" hx-swap="none">
                <label>Email <input type="email" name="email" required></label>
                <label>Password <input type="password" name="password" required></label>
                <button type="submit">Login</button>
              </form>
              <p>Don't have an account? <a href="register.html">Register</a></p>
            </body>
            </html>
          HTML

          write_file("pages/auth/register.html", <<~HTML)
            <!DOCTYPE html>
            <html lang="en">
            <head>
              <meta charset="UTF-8">
              <meta name="viewport" content="width=device-width, initial-scale=1.0">
              <title>Register</title>
              <script src="https://unpkg.com/htmx.org@2.0.0"></script>
              <script src="../../config.js"></script>
              <script src="../../js/auth.js"></script>
              <script src="../../js/api.js"></script>
              <link rel="stylesheet" href="../../css/style.css">
            </head>
            <body>
              <h1>Register</h1>
              <div id="error" class="error" style="display:none"></div>
              <form onsubmit="handleRegister(event)">
                <label>Name <input type="text" name="name" required></label>
                <label>Email <input type="email" name="email" required></label>
                <label>Password <input type="password" name="password" required minlength="8"></label>
                <button type="submit">Register</button>
              </form>
              <p>Already have an account? <a href="login.html">Login</a></p>
            </body>
            </html>
          HTML
        end

        def generate_resource_pages
          ir.resources.each do |resource|
            generate_resource_index(resource)
            generate_resource_show(resource)
            generate_resource_form(resource)
          end
        end

        def generate_resource_index(resource)
          name = classify(resource.name)
          plural = resource.name.to_s

          headers = resource.fields.map { |f| "          <th>#{f[:name]}</th>" }.join("\n")
          cells = resource.fields.map { |f| "            <td>\${item.#{f[:name]} || \"-\"}</td>" }.join("\n")

          write_file("pages/#{plural}/index.html", <<~HTML)
            <!DOCTYPE html>
            <html lang="en">
            <head>
              <meta charset="UTF-8">
              <meta name="viewport" content="width=device-width, initial-scale=1.0">
              <title>#{name}s</title>
              <script src="https://unpkg.com/htmx.org@2.0.0"></script>
              <script src="../../config.js"></script>
              <script src="../../js/auth.js"></script>
              <script src="../../js/api.js"></script>
              <link rel="stylesheet" href="../../css/style.css">
            </head>
            <body>
              <script>requireAuth();</script>
              <div class="list-header">
                <h1>#{name}s</h1>
                <a href="form.html" class="btn">New #{name}</a>
              </div>
              <table>
                <thead>
                  <tr>
            #{headers}
                    <th>Actions</th>
                  </tr>
                </thead>
                <tbody id="items"></tbody>
              </table>
              <script>
                (async function() {
                  const data = await apiRequest("/#{plural}");
                  const items = data.items || data;
                  const tbody = document.getElementById("items");
                  tbody.innerHTML = items.map(item => `
                    <tr>
            #{cells}
                      <td>
                        <a href="form.html?id=\${item.id}">Edit</a>
                        <button class="btn-danger" onclick="deleteItem(\${item.id})">Delete</button>
                      </td>
                    </tr>
                  `).join("");
                })();

                async function deleteItem(id) {
                  if (confirm("Delete this #{singularize(plural)}?")) {
                    await apiRequest(`/#{plural}/${"\\" + "${id}"}`, { method: "DELETE" });
                    window.location.reload();
                  }
                }
              </script>
            </body>
            </html>
          HTML
        end

        def generate_resource_show(resource)
          name = classify(resource.name)
          plural = resource.name.to_s
          singular = singularize(plural)

          fields_display = resource.fields.map { |f|
            "          <dt>#{f[:name]}</dt><dd id=\"field-#{f[:name]}\"></dd>"
          }.join("\n")

          field_setters = resource.fields.map { |f|
            "        document.getElementById(\"field-#{f[:name]}\").textContent = data.#{f[:name]} || \"-\";"
          }.join("\n")

          write_file("pages/#{plural}/show.html", <<~HTML)
            <!DOCTYPE html>
            <html lang="en">
            <head>
              <meta charset="UTF-8">
              <meta name="viewport" content="width=device-width, initial-scale=1.0">
              <title>#{name} Detail</title>
              <script src="https://unpkg.com/htmx.org@2.0.0"></script>
              <script src="../../config.js"></script>
              <script src="../../js/auth.js"></script>
              <script src="../../js/api.js"></script>
              <link rel="stylesheet" href="../../css/style.css">
            </head>
            <body>
              <script>requireAuth();</script>
              <h1>#{name}</h1>
              <dl>
            #{fields_display}
              </dl>
              <div class="actions">
                <a href="index.html">Back to list</a>
              </div>
              <script>
                (async function() {
                  const params = new URLSearchParams(window.location.search);
                  const id = params.get("id");
                  if (!id) { window.location.href = "index.html"; return; }
                  const data = await apiRequest(`/#{plural}/${"\\" + "${id}"}`);
            #{field_setters}
                })();
              </script>
            </body>
            </html>
          HTML
        end

        def generate_resource_form(resource)
          name = classify(resource.name)
          plural = resource.name.to_s

          form_fields = resource.fields.map { |f|
            if f[:enum]
              options = f[:enum].map { |v| "            <option value=\"#{v}\">#{v}</option>" }.join("\n")
              "        <label>#{f[:name]}\n          <select name=\"#{f[:name]}\">\n            <option value=\"\">Select...</option>\n#{options}\n          </select>\n        </label>"
            else
              input_type = f[:name].to_s.include?("date") ? "date" : "text"
              required = f[:required] ? " required" : ""
              "        <label>#{f[:name]} <input type=\"#{input_type}\" name=\"#{f[:name]}\"#{required}></label>"
            end
          }.join("\n")

          load_fields = resource.fields.map { |f|
            "          form.#{f[:name]}.value = data.#{f[:name]} || \"\";"
          }.join("\n")

          body_fields = resource.fields.map { |f|
            "          #{f[:name]}: form.#{f[:name]}.value"
          }.join(",\n")

          write_file("pages/#{plural}/form.html", <<~HTML)
            <!DOCTYPE html>
            <html lang="en">
            <head>
              <meta charset="UTF-8">
              <meta name="viewport" content="width=device-width, initial-scale=1.0">
              <title>#{name} Form</title>
              <script src="https://unpkg.com/htmx.org@2.0.0"></script>
              <script src="../../config.js"></script>
              <script src="../../js/auth.js"></script>
              <script src="../../js/api.js"></script>
              <link rel="stylesheet" href="../../css/style.css">
            </head>
            <body>
              <script>requireAuth();</script>
              <h1 id="page-title">New #{name}</h1>
              <div id="error" class="error" style="display:none"></div>
              <form id="resource-form" onsubmit="handleSubmit(event)">
            #{form_fields}
                <button type="submit">Save</button>
              </form>
              <script>
                const params = new URLSearchParams(window.location.search);
                const editId = params.get("id");

                if (editId) {
                  document.getElementById("page-title").textContent = "Edit #{name}";
                  (async function() {
                    const data = await apiRequest(`/#{plural}/${"\\" + "${editId}"}`);
                    const form = document.getElementById("resource-form");
            #{load_fields}
                  })();
                }

                async function handleSubmit(event) {
                  event.preventDefault();
                  const form = event.target;
                  const body = {
            #{body_fields}
                  };

                  try {
                    if (editId) {
                      await apiRequest(`/#{plural}/${"\\" + "${editId}"}`, { method: "PUT", body: JSON.stringify(body) });
                    } else {
                      await apiRequest("/#{plural}", { method: "POST", body: JSON.stringify(body) });
                    }
                    window.location.href = "index.html";
                  } catch (e) {
                    document.getElementById("error").textContent = "Failed to save";
                    document.getElementById("error").style.display = "block";
                  }
                }
              </script>
            </body>
            </html>
          HTML
        end

        def generate_readme
          write_file("README.md", <<~MD)
            # Whoosh htmx Client

            A lightweight client using htmx — no build step required.

            ## Usage

            1. Open `index.html` in a browser, or serve with any static file server
            2. Update `config.js` to point to your Whoosh API

            ## Configuration

            Edit `config.js` to set `API_URL`.
          MD
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/whoosh/client_gen/generators/htmx_spec.rb -v`
Expected: All 6 examples pass

- [ ] **Step 5: Commit**

```bash
git add lib/whoosh/client_gen/generators/htmx.rb spec/whoosh/client_gen/generators/htmx_spec.rb
git commit -m "feat: add htmx client generator"
```

---

### Task 3: Telegram Mini App Generator

**Files:**
- Create: `lib/whoosh/client_gen/generators/telegram_mini_app.rb`
- Test: `spec/whoosh/client_gen/generators/telegram_mini_app_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/whoosh/client_gen/generators/telegram_mini_app_spec.rb
# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "whoosh/client_gen/ir"
require "whoosh/client_gen/generators/telegram_mini_app"

RSpec.describe Whoosh::ClientGen::Generators::TelegramMiniApp do
  let(:ir) do
    Whoosh::ClientGen::IR::AppSpec.new(
      auth: Whoosh::ClientGen::IR::Auth.new(
        type: :jwt,
        endpoints: {
          login: { method: :post, path: "/auth/login" },
          register: { method: :post, path: "/auth/register" }
        }
      ),
      resources: [
        Whoosh::ClientGen::IR::Resource.new(
          name: :tasks,
          endpoints: [
            Whoosh::ClientGen::IR::Endpoint.new(method: :get, path: "/tasks", action: :index),
            Whoosh::ClientGen::IR::Endpoint.new(method: :post, path: "/tasks", action: :create),
            Whoosh::ClientGen::IR::Endpoint.new(method: :delete, path: "/tasks/:id", action: :destroy)
          ],
          fields: [
            { name: :title, type: :string, required: true },
            { name: :status, type: :string, required: false, enum: %w[pending done] }
          ]
        )
      ],
      streaming: [],
      base_url: "http://localhost:9292"
    )
  end

  it "generates a complete Telegram Mini App project" do
    Dir.mktmpdir do |dir|
      described_class.new(ir: ir, output_dir: dir, platform: :typescript).generate

      expect(File.exist?(File.join(dir, "package.json"))).to be true
      expect(File.exist?(File.join(dir, "tsconfig.json"))).to be true
      expect(File.exist?(File.join(dir, "vite.config.ts"))).to be true
      expect(File.exist?(File.join(dir, "index.html"))).to be true
      expect(File.exist?(File.join(dir, ".env"))).to be true
    end
  end

  it "includes @twa-dev/sdk in package.json" do
    Dir.mktmpdir do |dir|
      described_class.new(ir: ir, output_dir: dir, platform: :typescript).generate

      pkg = File.read(File.join(dir, "package.json"))
      expect(pkg).to include("@twa-dev/sdk")
    end
  end

  it "generates useTelegram hook" do
    Dir.mktmpdir do |dir|
      described_class.new(ir: ir, output_dir: dir, platform: :typescript).generate

      hook = File.read(File.join(dir, "src", "hooks", "useTelegram.ts"))
      expect(hook).to include("WebApp")
      expect(hook).to include("initData")
    end
  end

  it "generates API client with initData auth" do
    Dir.mktmpdir do |dir|
      described_class.new(ir: ir, output_dir: dir, platform: :typescript).generate

      client = File.read(File.join(dir, "src", "api", "client.ts"))
      expect(client).to include("initData")
    end
  end

  it "generates MainButton component" do
    Dir.mktmpdir do |dir|
      described_class.new(ir: ir, output_dir: dir, platform: :typescript).generate

      expect(File.exist?(File.join(dir, "src", "components", "MainButton.tsx"))).to be true
    end
  end

  it "does not generate Login or Register pages" do
    Dir.mktmpdir do |dir|
      described_class.new(ir: ir, output_dir: dir, platform: :typescript).generate

      expect(File.exist?(File.join(dir, "src", "pages", "Login.tsx"))).to be false
      expect(File.exist?(File.join(dir, "src", "pages", "Register.tsx"))).to be false
    end
  end

  it ".env contains BOT_USERNAME" do
    Dir.mktmpdir do |dir|
      described_class.new(ir: ir, output_dir: dir, platform: :typescript).generate

      env = File.read(File.join(dir, ".env"))
      expect(env).to include("VITE_BOT_USERNAME")
      expect(env).to include("VITE_API_URL")
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/whoosh/client_gen/generators/telegram_mini_app_spec.rb -v`
Expected: FAIL with "cannot load such file"

- [ ] **Step 3: Write the Telegram Mini App generator**

The generator is structurally similar to ReactSpa but with these key differences:
- No login/register pages (auth via Telegram initData)
- Uses `@twa-dev/sdk` for Telegram WebApp integration
- Adapts to Telegram theme colors
- Uses Telegram's MainButton and BackButton

```ruby
# lib/whoosh/client_gen/generators/telegram_mini_app.rb
# frozen_string_literal: true

require "json"
require "whoosh/client_gen/base_generator"

module Whoosh
  module ClientGen
    module Generators
      class TelegramMiniApp < BaseGenerator
        def generate
          generate_config_files
          generate_api_client
          generate_models
          generate_resource_apis
          generate_hooks
          generate_pages
          generate_components
          generate_router
          generate_app
          generate_main
          generate_styles
        end

        private

        def generate_config_files
          write_file("package.json", package_json)
          write_file("tsconfig.json", tsconfig_json)
          write_file("vite.config.ts", vite_config)
          write_file("index.html", index_html)
          write_file(".env", "VITE_API_URL=#{ir.base_url}\nVITE_BOT_USERNAME=your_bot_username\n")
          write_file(".gitignore", "node_modules/\ndist/\n.env.local\n")
        end

        def generate_api_client
          write_file("src/api/client.ts", <<~TS)
            import WebApp from "@twa-dev/sdk";

            const API_URL = import.meta.env.VITE_API_URL || "http://localhost:9292";

            let jwtToken: string | null = null;

            export async function initAuth(): Promise<void> {
              const initData = WebApp.initData;
              if (!initData) return;

              try {
                const res = await fetch(`${API_URL}/auth/telegram`, {
                  method: "POST",
                  headers: { "Content-Type": "application/json" },
                  body: JSON.stringify({ initData }),
                });
                if (res.ok) {
                  const data = await res.json();
                  jwtToken = data.token;
                }
              } catch {
                console.error("Failed to authenticate with Telegram initData");
              }
            }

            export async function apiRequest<T>(
              path: string,
              options: RequestInit = {}
            ): Promise<T> {
              const url = `${API_URL}${path}`;
              const headers: Record<string, string> = {
                "Content-Type": "application/json",
                ...(options.headers as Record<string, string>),
              };

              if (jwtToken) {
                headers["Authorization"] = `Bearer ${jwtToken}`;
              }

              const res = await fetch(url, { ...options, headers });

              if (res.status === 422) {
                const error = await res.json();
                throw { status: 422, details: error.details || [], message: error.error };
              }

              if (!res.ok) {
                const error = await res.json().catch(() => ({ error: "Request failed" }));
                throw { status: res.status, message: error.error };
              }

              return res.json();
            }
          TS
        end

        def generate_models
          ir.resources.each do |resource|
            name = classify(resource.name)
            fields = resource.fields.map { |f|
              ts_type = type_for(f[:type])
              optional = f[:required] ? "" : "?"
              "  #{f[:name]}#{optional}: #{ts_type};"
            }.join("\n")

            write_file("src/models/#{singularize(resource.name.to_s)}.ts", <<~TS)
              export interface #{name} {
                id: number;
              #{fields}
                created_at?: string;
                updated_at?: string;
              }

              export interface Create#{name}Input {
              #{resource.fields.select { |f| f[:required] }.map { |f| "  #{f[:name]}: #{type_for(f[:type])};" }.join("\n")}
              #{resource.fields.reject { |f| f[:required] }.map { |f| "  #{f[:name]}?: #{type_for(f[:type])};" }.join("\n")}
              }

              export interface Update#{name}Input {
              #{resource.fields.map { |f| "  #{f[:name]}?: #{type_for(f[:type])};" }.join("\n")}
              }
            TS
          end
        end

        def generate_resource_apis
          ir.resources.each do |resource|
            name = classify(resource.name)
            singular = singularize(resource.name.to_s)
            plural = resource.name.to_s
            base_path = "/#{plural}"

            methods = []
            resource.endpoints.each do |ep|
              case ep.action
              when :index
                methods << "export async function list#{name}s(cursor?: string, limit = 20) {\n  const params = new URLSearchParams();\n  if (cursor) params.set(\"cursor\", cursor);\n  params.set(\"limit\", String(limit));\n  return apiRequest<{ items: #{name}[]; next_cursor: string | null }>(`#{base_path}?${params}`);\n}"
              when :show
                methods << "export async function get#{name}(id: number | string) {\n  return apiRequest<#{name}>(`#{base_path}/${id}`);\n}"
              when :create
                methods << "export async function create#{name}(input: Create#{name}Input) {\n  return apiRequest<#{name}>(`#{base_path}`, { method: \"POST\", body: JSON.stringify(input) });\n}"
              when :update
                methods << "export async function update#{name}(id: number | string, input: Update#{name}Input) {\n  return apiRequest<#{name}>(`#{base_path}/${id}`, { method: \"PUT\", body: JSON.stringify(input) });\n}"
              when :destroy
                methods << "export async function delete#{name}(id: number | string) {\n  await apiRequest(`#{base_path}/${id}`, { method: \"DELETE\" });\n}"
              end
            end

            write_file("src/api/#{plural}.ts", <<~TS)
              import { apiRequest } from "./client";
              import type { #{name}, Create#{name}Input, Update#{name}Input } from "../models/#{singular}";

              #{methods.join("\n\n")}
            TS
          end
        end

        def generate_hooks
          write_file("src/hooks/useTelegram.ts", <<~TS)
            import WebApp from "@twa-dev/sdk";

            export function useTelegram() {
              const initData = WebApp.initData;
              const user = WebApp.initDataUnsafe?.user;
              const colorScheme = WebApp.colorScheme;
              const themeParams = WebApp.themeParams;

              function showMainButton(text: string, onClick: () => void) {
                WebApp.MainButton.setText(text);
                WebApp.MainButton.onClick(onClick);
                WebApp.MainButton.show();
              }

              function hideMainButton() {
                WebApp.MainButton.hide();
              }

              function showBackButton(onClick: () => void) {
                WebApp.BackButton.onClick(onClick);
                WebApp.BackButton.show();
              }

              function hideBackButton() {
                WebApp.BackButton.hide();
              }

              function hapticFeedback(type: "impact" | "notification" | "selection") {
                if (type === "impact") WebApp.HapticFeedback.impactOccurred("medium");
                else if (type === "notification") WebApp.HapticFeedback.notificationOccurred("success");
                else WebApp.HapticFeedback.selectionChanged();
              }

              function close() {
                WebApp.close();
              }

              return {
                initData, user, colorScheme, themeParams,
                showMainButton, hideMainButton,
                showBackButton, hideBackButton,
                hapticFeedback, close
              };
            }
          TS

          write_file("src/hooks/useAuth.ts", <<~TS)
            import { useState, useEffect } from "react";
            import { initAuth } from "../api/client";

            export function useAuth() {
              const [ready, setReady] = useState(false);

              useEffect(() => {
                initAuth().finally(() => setReady(true));
              }, []);

              return { ready };
            }
          TS

          ir.resources.each do |resource|
            name = classify(resource.name)
            plural = resource.name.to_s
            singular = singularize(plural)

            write_file("src/hooks/use#{name}s.ts", <<~TS)
              import { useState, useCallback } from "react";
              import type { #{name}, Create#{name}Input, Update#{name}Input } from "../models/#{singular}";
              import { list#{name}s, create#{name}, delete#{name} } from "../api/#{plural}";

              export function use#{name}s() {
                const [items, setItems] = useState<#{name}[]>([]);
                const [loading, setLoading] = useState(false);
                const [error, setError] = useState<string | null>(null);

                const fetchAll = useCallback(async () => {
                  setLoading(true);
                  try {
                    const data = await list#{name}s();
                    setItems(data.items);
                  } catch (e: any) {
                    setError(e.message || "Failed to load");
                  } finally {
                    setLoading(false);
                  }
                }, []);

                const create = useCallback(async (input: Create#{name}Input) => {
                  const item = await create#{name}(input);
                  setItems(prev => [item, ...prev]);
                  return item;
                }, []);

                const remove = useCallback(async (id: number | string) => {
                  await delete#{name}(id);
                  setItems(prev => prev.filter(i => i.id !== Number(id)));
                }, []);

                return { items, loading, error, fetchAll, create, remove };
              }
            TS
          end
        end

        def generate_pages
          ir.resources.each do |resource|
            name = classify(resource.name)
            plural = resource.name.to_s

            write_file("src/pages/#{name}List.tsx", <<~TSX)
              import { useEffect } from "react";
              import { use#{name}s } from "../hooks/use#{name}s";
              import { useTelegram } from "../hooks/useTelegram";
              import { useNavigate } from "react-router-dom";

              export default function #{name}List() {
                const { items, loading, error, fetchAll, remove } = use#{name}s();
                const { showMainButton, hapticFeedback } = useTelegram();
                const navigate = useNavigate();

                useEffect(() => { fetchAll(); }, [fetchAll]);
                useEffect(() => {
                  showMainButton("New #{name}", () => navigate("/#{plural}/new"));
                  return () => {};
                }, []);

                if (loading && items.length === 0) return <p>Loading...</p>;
                if (error) return <p className="error">{error}</p>;

                return (
                  <div>
                    <h1>#{name}s</h1>
                    {items.length === 0 ? <p>No #{plural} yet.</p> : (
                      <ul className="resource-list">
                        {items.map(item => (
                          <li key={item.id} onClick={() => navigate(`/#{plural}/${item.id}`)}>
                            <span>{item.#{resource.fields.first&.dig(:name) || "id"}}</span>
                            <button className="btn-danger" onClick={e => { e.stopPropagation(); hapticFeedback("impact"); remove(item.id); }}>Delete</button>
                          </li>
                        ))}
                      </ul>
                    )}
                  </div>
                );
              }
            TSX

            write_file("src/pages/#{name}Detail.tsx", <<~TSX)
              import { useEffect, useState } from "react";
              import { useParams, useNavigate } from "react-router-dom";
              import { get#{name} } from "../api/#{plural}";
              import { useTelegram } from "../hooks/useTelegram";
              import type { #{name} } from "../models/#{singularize(plural)}";

              export default function #{name}Detail() {
                const { id } = useParams<{ id: string }>();
                const navigate = useNavigate();
                const { showBackButton, hideBackButton } = useTelegram();
                const [item, setItem] = useState<#{name} | null>(null);

                useEffect(() => {
                  showBackButton(() => navigate(-1));
                  return () => hideBackButton();
                }, []);

                useEffect(() => {
                  if (id) get#{name}(id).then(setItem);
                }, [id]);

                if (!item) return <p>Loading...</p>;

                return (
                  <div>
                    <h1>#{name}</h1>
                    <dl>
              #{resource.fields.map { |f| "        <dt>#{f[:name]}</dt><dd>{item.#{f[:name]} ?? \"-\"}</dd>" }.join("\n")}
                    </dl>
                  </div>
                );
              }
            TSX

            write_file("src/pages/#{name}Form.tsx", <<~TSX)
              import { useState, useEffect } from "react";
              import { useNavigate } from "react-router-dom";
              import { create#{name} } from "../api/#{plural}";
              import { useTelegram } from "../hooks/useTelegram";

              export default function #{name}Form() {
                const navigate = useNavigate();
                const { showBackButton, hideBackButton, showMainButton, hapticFeedback } = useTelegram();
              #{resource.fields.map { |f| "  const [#{f[:name]}, set#{camelize(f[:name].to_s)}] = useState(\"#{f[:default] || ""}\");" }.join("\n")}

                useEffect(() => {
                  showBackButton(() => navigate(-1));
                  return () => hideBackButton();
                }, []);

                useEffect(() => {
                  showMainButton("Save", handleSubmit);
                }, [#{resource.fields.map { |f| f[:name] }.join(", ")}]);

                async function handleSubmit() {
                  try {
                    await create#{name}({ #{resource.fields.map { |f| "#{f[:name]}" }.join(", ")} });
                    hapticFeedback("notification");
                    navigate("/#{plural}");
                  } catch (e) {
                    hapticFeedback("impact");
                  }
                }

                return (
                  <div>
                    <h1>New #{name}</h1>
                    <form onSubmit={e => { e.preventDefault(); handleSubmit(); }}>
              #{resource.fields.map { |f|
                if f[:enum]
                  options = f[:enum].map { |v| "            <option value=\"#{v}\">#{v}</option>" }.join("\n")
                  "        <label>#{f[:name]}\n          <select value={#{f[:name]}} onChange={e => set#{camelize(f[:name].to_s)}(e.target.value)}>\n            <option value=\"\">Select...</option>\n#{options}\n          </select>\n        </label>"
                else
                  "        <label>#{f[:name]} <input value={#{f[:name]}} onChange={e => set#{camelize(f[:name].to_s)}(e.target.value)} /></label>"
                end
              }.join("\n")}
                    </form>
                  </div>
                );
              }
            TSX
          end
        end

        def generate_components
          write_file("src/components/Layout.tsx", <<~TSX)
            import { Outlet } from "react-router-dom";
            import { useTelegram } from "../hooks/useTelegram";

            export default function Layout() {
              const { themeParams } = useTelegram();

              return (
                <div className="layout" style={{ background: themeParams?.bg_color, color: themeParams?.text_color }}>
                  <main><Outlet /></main>
                </div>
              );
            }
          TSX

          write_file("src/components/MainButton.tsx", <<~TSX)
            import { useEffect } from "react";
            import WebApp from "@twa-dev/sdk";

            interface Props {
              text: string;
              onClick: () => void;
              disabled?: boolean;
            }

            export default function MainButton({ text, onClick, disabled }: Props) {
              useEffect(() => {
                WebApp.MainButton.setText(text);
                WebApp.MainButton.onClick(onClick);
                if (disabled) {
                  WebApp.MainButton.disable();
                } else {
                  WebApp.MainButton.enable();
                }
                WebApp.MainButton.show();

                return () => {
                  WebApp.MainButton.hide();
                  WebApp.MainButton.offClick(onClick);
                };
              }, [text, onClick, disabled]);

              return null;
            }
          TSX
        end

        def generate_router
          resource_routes = ir.resources.flat_map { |r|
            name = classify(r.name)
            plural = r.name.to_s
            [
              "          <Route path=\"/#{plural}\" element={<#{name}List />} />",
              "          <Route path=\"/#{plural}/new\" element={<#{name}Form />} />",
              "          <Route path=\"/#{plural}/:id\" element={<#{name}Detail />} />"
            ]
          }.join("\n")

          page_imports = ir.resources.flat_map { |r|
            name = classify(r.name)
            ["import #{name}List from \"./pages/#{name}List\";", "import #{name}Detail from \"./pages/#{name}Detail\";", "import #{name}Form from \"./pages/#{name}Form\";"]
          }.join("\n")

          first_resource = ir.resources.first
          home_redirect = first_resource ? "/#{first_resource.name}" : "/"

          write_file("src/router.tsx", <<~TSX)
            import { BrowserRouter, Routes, Route, Navigate } from "react-router-dom";
            import Layout from "./components/Layout";
            #{page_imports}

            export default function AppRouter() {
              return (
                <BrowserRouter>
                  <Routes>
                    <Route element={<Layout />}>
            #{resource_routes}
                      <Route path="/" element={<Navigate to="#{home_redirect}" replace />} />
                    </Route>
                  </Routes>
                </BrowserRouter>
              );
            }
          TSX
        end

        def generate_app
          write_file("src/App.tsx", <<~TSX)
            import { useAuth } from "./hooks/useAuth";
            import AppRouter from "./router";

            export default function App() {
              const { ready } = useAuth();

              if (!ready) return <div className="loading">Loading...</div>;

              return <AppRouter />;
            }
          TSX
        end

        def generate_main
          write_file("src/main.tsx", <<~TSX)
            import { StrictMode } from "react";
            import { createRoot } from "react-dom/client";
            import App from "./App";
            import "./styles.css";

            createRoot(document.getElementById("root")!).render(
              <StrictMode>
                <App />
              </StrictMode>
            );
          TSX
        end

        def generate_styles
          write_file("src/styles.css", <<~CSS)
            * { box-sizing: border-box; margin: 0; padding: 0; }
            body { font-family: -apple-system, "SF Pro", system-ui, sans-serif; line-height: 1.5; }
            .layout { min-height: 100vh; padding: 1rem; }
            .loading { display: flex; align-items: center; justify-content: center; height: 100vh; }
            h1 { font-size: 1.5rem; margin-bottom: 1rem; }
            form { display: flex; flex-direction: column; gap: 1rem; }
            label { display: flex; flex-direction: column; gap: 0.25rem; font-weight: 500; font-size: 0.9rem; }
            input, select { padding: 0.75rem; border: 1px solid var(--tg-theme-hint-color, #ccc); border-radius: 8px; font-size: 1rem; background: var(--tg-theme-secondary-bg-color, #f5f5f5); color: var(--tg-theme-text-color, #1a1a1a); }
            .error { color: var(--tg-theme-destructive-text-color, #dc2626); padding: 0.75rem; }
            .resource-list { list-style: none; }
            .resource-list li { display: flex; justify-content: space-between; align-items: center; padding: 0.75rem; background: var(--tg-theme-secondary-bg-color, #f5f5f5); border-radius: 8px; margin-bottom: 0.5rem; cursor: pointer; }
            .btn-danger { background: var(--tg-theme-destructive-text-color, #dc2626); color: white; border: none; border-radius: 6px; padding: 0.25rem 0.5rem; font-size: 0.8rem; }
            dl { display: grid; grid-template-columns: auto 1fr; gap: 0.5rem 1rem; }
            dt { font-weight: 600; color: var(--tg-theme-hint-color, #888); font-size: 0.85rem; }
          CSS
        end

        def package_json
          JSON.pretty_generate({
            name: "whoosh-telegram-mini-app",
            private: true,
            version: "0.1.0",
            type: "module",
            scripts: {
              dev: "vite",
              build: "tsc && vite build",
              preview: "vite preview"
            },
            dependencies: {
              react: "^19.0.0",
              "react-dom": "^19.0.0",
              "react-router-dom": "^7.0.0",
              "@twa-dev/sdk": "^7.0.0"
            },
            devDependencies: {
              "@types/react": "^19.0.0",
              "@types/react-dom": "^19.0.0",
              "@vitejs/plugin-react": "^4.3.0",
              typescript: "^5.6.0",
              vite: "^6.0.0"
            }
          })
        end

        def tsconfig_json
          JSON.pretty_generate({
            compilerOptions: {
              target: "ES2020", useDefineForClassFields: true,
              lib: ["ES2020", "DOM", "DOM.Iterable"], module: "ESNext",
              skipLibCheck: true, moduleResolution: "bundler",
              allowImportingTsExtensions: true, isolatedModules: true,
              moduleDetection: "force", noEmit: true, jsx: "react-jsx",
              strict: true
            },
            include: ["src"]
          })
        end

        def vite_config
          <<~TS
            import { defineConfig } from "vite";
            import react from "@vitejs/plugin-react";

            export default defineConfig({
              plugins: [react()],
              server: { port: 3000 },
            });
          TS
        end

        def index_html
          <<~HTML
            <!DOCTYPE html>
            <html lang="en">
              <head>
                <meta charset="UTF-8" />
                <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no" />
                <title>Whoosh Mini App</title>
                <script src="https://telegram.org/js/telegram-web-app.js"></script>
              </head>
              <body>
                <div id="root"></div>
                <script type="module" src="/src/main.tsx"></script>
              </body>
            </html>
          HTML
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/whoosh/client_gen/generators/telegram_mini_app_spec.rb -v`
Expected: All 7 examples pass

- [ ] **Step 5: Commit**

```bash
git add lib/whoosh/client_gen/generators/telegram_mini_app.rb spec/whoosh/client_gen/generators/telegram_mini_app_spec.rb
git commit -m "feat: add Telegram Mini App client generator"
```

---

### Task 4: Web Clients Integration Test

**Files:**
- Create: `spec/whoosh/client_gen/generators/web_integration_spec.rb`

- [ ] **Step 1: Write the integration test**

```ruby
# spec/whoosh/client_gen/generators/web_integration_spec.rb
# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "whoosh/client_gen/ir"
require "whoosh/client_gen/generators/react_spa"
require "whoosh/client_gen/generators/htmx"
require "whoosh/client_gen/generators/telegram_mini_app"

RSpec.describe "Web Client Generators Integration" do
  let(:ir) do
    Whoosh::ClientGen::IR::AppSpec.new(
      auth: Whoosh::ClientGen::IR::Auth.new(
        type: :jwt,
        endpoints: {
          login: { method: :post, path: "/auth/login" },
          register: { method: :post, path: "/auth/register" },
          me: { method: :get, path: "/auth/me" }
        }
      ),
      resources: [
        Whoosh::ClientGen::IR::Resource.new(
          name: :tasks,
          endpoints: [
            Whoosh::ClientGen::IR::Endpoint.new(method: :get, path: "/tasks", action: :index, pagination: true),
            Whoosh::ClientGen::IR::Endpoint.new(method: :get, path: "/tasks/:id", action: :show),
            Whoosh::ClientGen::IR::Endpoint.new(method: :post, path: "/tasks", action: :create),
            Whoosh::ClientGen::IR::Endpoint.new(method: :put, path: "/tasks/:id", action: :update),
            Whoosh::ClientGen::IR::Endpoint.new(method: :delete, path: "/tasks/:id", action: :destroy)
          ],
          fields: [
            { name: :title, type: :string, required: true },
            { name: :description, type: :string, required: false },
            { name: :status, type: :string, required: false, enum: %w[pending in_progress done], default: "pending" }
          ]
        ),
        Whoosh::ClientGen::IR::Resource.new(
          name: :notes,
          endpoints: [
            Whoosh::ClientGen::IR::Endpoint.new(method: :get, path: "/notes", action: :index),
            Whoosh::ClientGen::IR::Endpoint.new(method: :post, path: "/notes", action: :create)
          ],
          fields: [
            { name: :body, type: :string, required: true }
          ]
        )
      ],
      streaming: [],
      base_url: "http://localhost:9292"
    )
  end

  %i[react_spa htmx telegram_mini_app].each do |client_type|
    describe "#{client_type} with multiple resources" do
      it "generates files for all resources" do
        Dir.mktmpdir do |dir|
          klass = case client_type
                  when :react_spa then Whoosh::ClientGen::Generators::ReactSpa
                  when :htmx then Whoosh::ClientGen::Generators::Htmx
                  when :telegram_mini_app then Whoosh::ClientGen::Generators::TelegramMiniApp
                  end
          platform = client_type == :htmx ? :html : :typescript

          klass.new(ir: ir, output_dir: dir, platform: platform).generate

          # Should have files for both resources
          files = Dir.glob("#{dir}/**/*").select { |f| File.file?(f) }
          file_names = files.map { |f| File.basename(f) }.join(" ")

          expect(file_names).to include("task")
          expect(file_names).to include("note")
        end
      end
    end
  end
end
```

- [ ] **Step 2: Run test to verify it passes**

Run: `bundle exec rspec spec/whoosh/client_gen/generators/web_integration_spec.rb -v`
Expected: All 3 examples pass

- [ ] **Step 3: Commit**

```bash
git add spec/whoosh/client_gen/generators/web_integration_spec.rb
git commit -m "test: add web client generators integration test"
```
