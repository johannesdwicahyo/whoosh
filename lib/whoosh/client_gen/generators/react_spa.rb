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
          generate_auth_api if ir.has_auth?
          ir.resources.each do |resource|
            generate_model(resource)
            generate_resource_api(resource)
            generate_resource_hook(resource)
            generate_resource_pages(resource)
          end
          generate_auth_hook if ir.has_auth?
          generate_components
          generate_router
          generate_app
          generate_main
          generate_styles
        end

        private

        # ── Config files ──────────────────────────────────────────────

        def generate_config_files
          write_file("package.json", package_json)
          write_file("tsconfig.json", tsconfig_json)
          write_file("vite.config.ts", vite_config)
          write_file("index.html", index_html)
          write_file(".env", dot_env)
          write_file(".gitignore", gitignore)
        end

        def package_json
          pkg = {
            name: "app",
            private: true,
            version: "0.1.0",
            type: "module",
            scripts: {
              dev: "vite",
              build: "tsc && vite build",
              preview: "vite preview"
            },
            dependencies: {
              "react" => "^19.0.0",
              "react-dom" => "^19.0.0",
              "react-router-dom" => "^7.0.0"
            },
            devDependencies: {
              "@types/react" => "^19.0.0",
              "@types/react-dom" => "^19.0.0",
              "@vitejs/plugin-react" => "^4.3.0",
              "typescript" => "^5.6.0",
              "vite" => "^6.0.0"
            }
          }
          JSON.pretty_generate(pkg) + "\n"
        end

        def tsconfig_json
          <<~JSON
            {
              "compilerOptions": {
                "target": "ES2020",
                "useDefineForClassFields": true,
                "lib": ["ES2020", "DOM", "DOM.Iterable"],
                "module": "ESNext",
                "skipLibCheck": true,
                "moduleResolution": "bundler",
                "allowImportingTsExtensions": true,
                "isolatedModules": true,
                "moduleDetection": "force",
                "noEmit": true,
                "jsx": "react-jsx",
                "strict": true,
                "noUnusedLocals": false,
                "noUnusedParameters": false,
                "noFallthroughCasesInSwitch": true,
                "forceConsistentCasingInFileNames": true
              },
              "include": ["src"]
            }
          JSON
        end

        def vite_config
          <<~TS
            import { defineConfig } from "vite";
            import react from "@vitejs/plugin-react";

            export default defineConfig({
              plugins: [react()],
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
                <title>App</title>
              </head>
              <body>
                <div id="root"></div>
                <script type="module" src="/src/main.tsx"></script>
              </body>
            </html>
          HTML
        end

        def dot_env
          "VITE_API_URL=#{ir.base_url}\n"
        end

        def gitignore
          <<~TXT
            node_modules
            dist
            .env.local
          TXT
        end

        # ── API client ────────────────────────────────────────────────

        def generate_api_client
          write_file("src/api/client.ts", <<~TS)
            const API_URL = import.meta.env.VITE_API_URL || "#{ir.base_url}";

            export function getTokens() {
              return {
                access: localStorage.getItem("access_token"),
                refresh: localStorage.getItem("refresh_token"),
              };
            }

            export function setTokens(access: string, refresh?: string) {
              localStorage.setItem("access_token", access);
              if (refresh) localStorage.setItem("refresh_token", refresh);
            }

            export function clearTokens() {
              localStorage.removeItem("access_token");
              localStorage.removeItem("refresh_token");
            }

            async function refreshAccessToken(): Promise<boolean> {
              const { refresh } = getTokens();
              if (!refresh) return false;
              try {
                const res = await fetch(`${API_URL}/auth/refresh`, {
                  method: "POST",
                  headers: { "Content-Type": "application/json" },
                  body: JSON.stringify({ refresh_token: refresh }),
                });
                if (!res.ok) return false;
                const data = await res.json();
                setTokens(data.access_token, data.refresh_token);
                return true;
              } catch {
                return false;
              }
            }

            export async function apiRequest<T = any>(
              path: string,
              options: RequestInit = {}
            ): Promise<T> {
              const { access } = getTokens();
              const headers: Record<string, string> = {
                "Content-Type": "application/json",
                ...(options.headers as Record<string, string>),
              };
              if (access) {
                headers["Authorization"] = `Bearer ${access}`;
              }

              let res = await fetch(`${API_URL}${path}`, { ...options, headers });

              if (res.status === 401) {
                const refreshed = await refreshAccessToken();
                if (refreshed) {
                  const { access: newAccess } = getTokens();
                  headers["Authorization"] = `Bearer ${newAccess}`;
                  res = await fetch(`${API_URL}${path}`, { ...options, headers });
                }
              }

              if (!res.ok) {
                const err = await res.json().catch(() => ({}));
                throw { status: res.status, ...err };
              }

              if (res.status === 204) return undefined as T;
              return res.json();
            }
          TS
        end

        # ── Auth API ──────────────────────────────────────────────────

        def generate_auth_api
          write_file("src/api/auth.ts", <<~TS)
            import { apiRequest, setTokens, clearTokens } from "./client";

            export async function login(email: string, password: string) {
              const data = await apiRequest<{ access_token: string; refresh_token: string }>(
                "/auth/login",
                { method: "POST", body: JSON.stringify({ email, password }) }
              );
              setTokens(data.access_token, data.refresh_token);
              return data;
            }

            export async function register(email: string, password: string) {
              const data = await apiRequest<{ access_token: string; refresh_token: string }>(
                "/auth/register",
                { method: "POST", body: JSON.stringify({ email, password }) }
              );
              setTokens(data.access_token, data.refresh_token);
              return data;
            }

            export async function refresh() {
              const data = await apiRequest<{ access_token: string; refresh_token: string }>(
                "/auth/refresh",
                { method: "POST" }
              );
              setTokens(data.access_token, data.refresh_token);
              return data;
            }

            export async function logout() {
              await apiRequest("/auth/logout", { method: "DELETE" });
              clearTokens();
            }

            export async function getMe() {
              return apiRequest<{ id: string; email: string }>("/auth/me");
            }
          TS
        end

        # ── Models ────────────────────────────────────────────────────

        def generate_model(resource)
          name = classify(resource.name)
          singular = singularize(resource.name.to_s)
          fields = resource.fields || []

          lines = fields.map do |f|
            fname = f[:name].to_s
            ftype = type_for(f[:type])
            "  #{fname}: #{ftype};"
          end

          create_lines = fields.select { |f| f[:required] }.map do |f|
            "  #{f[:name]}: #{type_for(f[:type])};"
          end
          create_optional = fields.reject { |f| f[:required] }.map do |f|
            "  #{f[:name]}?: #{type_for(f[:type])};"
          end

          update_lines = fields.map do |f|
            "  #{f[:name]}?: #{type_for(f[:type])};"
          end

          write_file("src/models/#{singular}.ts", <<~TS)
            export interface #{name} {
              id: string;
            #{lines.join("\n")}
              created_at?: string;
              updated_at?: string;
            }

            export interface Create#{name}Input {
            #{(create_lines + create_optional).join("\n")}
            }

            export interface Update#{name}Input {
            #{update_lines.join("\n")}
            }
          TS
        end

        # ── Resource API ──────────────────────────────────────────────

        def generate_resource_api(resource)
          plural = resource.name.to_s
          singular = singularize(plural)
          name = classify(resource.name)
          has_pagination = resource.endpoints.any? { |e| e.pagination }

          list_return = has_pagination ? "Promise<{ data: #{name}[]; cursor?: string }>" : "Promise<#{name}[]>"
          list_params = has_pagination ? "cursor?: string" : ""
          list_query = has_pagination ? 'const query = cursor ? `?cursor=${cursor}` : "";\n  ' : ""
          list_path = has_pagination ? "\"/#{plural}${query}\"" : "\"/#{plural}\""

          write_file("src/api/#{plural}.ts", <<~TS)
            import { apiRequest } from "./client";
            import type { #{name}, Create#{name}Input, Update#{name}Input } from "../models/#{singular}";

            export async function list#{name}s(#{list_params}): #{list_return} {
              #{list_query}return apiRequest(#{list_path});
            }

            export async function get#{name}(id: string): Promise<#{name}> {
              return apiRequest(`/#{plural}/${String("${id}")}`);
            }

            export async function create#{name}(input: Create#{name}Input): Promise<#{name}> {
              return apiRequest("/#{plural}", {
                method: "POST",
                body: JSON.stringify(input),
              });
            }

            export async function update#{name}(id: string, input: Update#{name}Input): Promise<#{name}> {
              return apiRequest(`/#{plural}/${String("${id}")}`, {
                method: "PUT",
                body: JSON.stringify(input),
              });
            }

            export async function delete#{name}(id: string): Promise<void> {
              return apiRequest(`/#{plural}/${String("${id}")}`, { method: "DELETE" });
            }
          TS
        end

        # ── Hooks ─────────────────────────────────────────────────────

        def generate_auth_hook
          write_file("src/hooks/useAuth.ts", <<~TS)
            import { createContext, useContext, useState, useEffect, useCallback } from "react";
            import * as authApi from "../api/auth";
            import { getTokens, clearTokens } from "../api/client";

            interface User {
              id: string;
              email: string;
            }

            interface AuthContextValue {
              user: User | null;
              loading: boolean;
              login: (email: string, password: string) => Promise<void>;
              register: (email: string, password: string) => Promise<void>;
              logout: () => Promise<void>;
            }

            export const AuthContext = createContext<AuthContextValue | null>(null);

            export function useAuth(): AuthContextValue {
              const ctx = useContext(AuthContext);
              if (!ctx) throw new Error("useAuth must be inside AuthProvider");
              return ctx;
            }

            export function useAuthProvider(): AuthContextValue {
              const [user, setUser] = useState<User | null>(null);
              const [loading, setLoading] = useState(true);

              const fetchMe = useCallback(async () => {
                try {
                  const me = await authApi.getMe();
                  setUser(me);
                } catch {
                  clearTokens();
                  setUser(null);
                } finally {
                  setLoading(false);
                }
              }, []);

              useEffect(() => {
                const { access } = getTokens();
                if (access) {
                  fetchMe();
                } else {
                  setLoading(false);
                }
              }, [fetchMe]);

              const login = async (email: string, password: string) => {
                await authApi.login(email, password);
                await fetchMe();
              };

              const register = async (email: string, password: string) => {
                await authApi.register(email, password);
                await fetchMe();
              };

              const logout = async () => {
                await authApi.logout();
                setUser(null);
              };

              return { user, loading, login, register, logout };
            }
          TS
        end

        def generate_resource_hook(resource)
          plural = resource.name.to_s
          singular = singularize(plural)
          name = classify(resource.name)
          has_pagination = resource.endpoints.any? { |e| e.pagination }

          write_file("src/hooks/use#{name}s.ts", <<~TS)
            import { useState, useCallback } from "react";
            import * as api from "../api/#{plural}";
            import type { #{name}, Create#{name}Input, Update#{name}Input } from "../models/#{singular}";

            export function use#{name}s() {
              const [items, setItems] = useState<#{name}[]>([]);
              const [loading, setLoading] = useState(false);
              const [error, setError] = useState<string | null>(null);
              #{has_pagination ? 'const [cursor, setCursor] = useState<string | undefined>();' : ''}

              const fetchAll = useCallback(async (#{has_pagination ? 'nextCursor?: string' : ''}) => {
                setLoading(true);
                setError(null);
                try {
                  #{if has_pagination
                      "const result = await api.list#{name}s(nextCursor);\n" \
                      "      if (nextCursor) {\n" \
                      "        setItems((prev) => [...prev, ...result.data]);\n" \
                      "      } else {\n" \
                      "        setItems(result.data);\n" \
                      "      }\n" \
                      "      setCursor(result.cursor);"
                    else
                      "const data = await api.list#{name}s();\n      setItems(data);"
                    end}
                } catch (e: any) {
                  setError(e.message || "Failed to load");
                } finally {
                  setLoading(false);
                }
              }, []);

              const create = async (input: Create#{name}Input) => {
                const item = await api.create#{name}(input);
                setItems((prev) => [...prev, item]);
                return item;
              };

              const update = async (id: string, input: Update#{name}Input) => {
                const item = await api.update#{name}(id, input);
                setItems((prev) => prev.map((i) => (i.id === id ? item : i)));
                return item;
              };

              const remove = async (id: string) => {
                await api.delete#{name}(id);
                setItems((prev) => prev.filter((i) => i.id !== id));
              };

              return { items, loading, error, fetchAll, create, update, remove#{has_pagination ? ', cursor' : ''} };
            }
          TS
        end

        # ── Pages ─────────────────────────────────────────────────────

        def generate_resource_pages(resource)
          plural = resource.name.to_s
          singular = singularize(plural)
          name = classify(resource.name)
          fields = resource.fields || []
          has_pagination = resource.endpoints.any? { |e| e.pagination }

          generate_list_page(name, plural, fields, has_pagination)
          generate_detail_page(name, plural, singular, fields)
          generate_form_page(name, plural, singular, fields)
          generate_login_page if ir.has_auth?
          generate_register_page if ir.has_auth?
        end

        def generate_login_page
          write_file("src/pages/Login.tsx", <<~TSX)
            import { useState, FormEvent } from "react";
            import { useAuth } from "../hooks/useAuth";
            import { useNavigate, Link } from "react-router-dom";

            export default function Login() {
              const { login } = useAuth();
              const navigate = useNavigate();
              const [email, setEmail] = useState("");
              const [password, setPassword] = useState("");
              const [error, setError] = useState<string | null>(null);

              const handleSubmit = async (e: FormEvent) => {
                e.preventDefault();
                setError(null);
                try {
                  await login(email, password);
                  navigate("/");
                } catch (err: any) {
                  setError(err.message || "Login failed");
                }
              };

              return (
                <div className="auth-page">
                  <h1>Login</h1>
                  {error && <p className="error">{error}</p>}
                  <form onSubmit={handleSubmit}>
                    <input type="email" placeholder="Email" value={email} onChange={(e) => setEmail(e.target.value)} required />
                    <input type="password" placeholder="Password" value={password} onChange={(e) => setPassword(e.target.value)} required />
                    <button type="submit">Login</button>
                  </form>
                  <p>Don't have an account? <Link to="/register">Register</Link></p>
                </div>
              );
            }
          TSX
        end

        def generate_register_page
          write_file("src/pages/Register.tsx", <<~TSX)
            import { useState, FormEvent } from "react";
            import { useAuth } from "../hooks/useAuth";
            import { useNavigate, Link } from "react-router-dom";

            export default function Register() {
              const { register } = useAuth();
              const navigate = useNavigate();
              const [email, setEmail] = useState("");
              const [password, setPassword] = useState("");
              const [error, setError] = useState<string | null>(null);

              const handleSubmit = async (e: FormEvent) => {
                e.preventDefault();
                setError(null);
                try {
                  await register(email, password);
                  navigate("/");
                } catch (err: any) {
                  setError(err.message || "Registration failed");
                }
              };

              return (
                <div className="auth-page">
                  <h1>Register</h1>
                  {error && <p className="error">{error}</p>}
                  <form onSubmit={handleSubmit}>
                    <input type="email" placeholder="Email" value={email} onChange={(e) => setEmail(e.target.value)} required />
                    <input type="password" placeholder="Password" value={password} onChange={(e) => setPassword(e.target.value)} required />
                    <button type="submit">Register</button>
                  </form>
                  <p>Already have an account? <Link to="/login">Login</Link></p>
                </div>
              );
            }
          TSX
        end

        def generate_list_page(name, plural, fields, has_pagination)
          display_fields = fields.first(3)
          field_headers = display_fields.map { |f| "<th>#{camelize(f[:name].to_s)}</th>" }.join("\n              ")
          field_cells = display_fields.map { |f| "<td>{item.#{f[:name]}}</td>" }.join("\n              ")

          write_file("src/pages/#{name}List.tsx", <<~TSX)
            import { useEffect } from "react";
            import { Link } from "react-router-dom";
            import { use#{name}s } from "../hooks/use#{name}s";
            #{has_pagination ? 'import Pagination from "../components/Pagination";' : ''}

            export default function #{name}List() {
              const { items, loading, error, fetchAll, remove#{has_pagination ? ', cursor' : ''} } = use#{name}s();

              useEffect(() => { fetchAll(); }, [fetchAll]);

              if (loading && items.length === 0) return <p>Loading...</p>;
              if (error) return <p className="error">{error}</p>;

              return (
                <div>
                  <h1>#{name}s</h1>
                  <Link to="/#{plural}/new" className="btn">Create #{name}</Link>
                  <table>
                    <thead>
                      <tr>
                        #{field_headers}
                        <th>Actions</th>
                      </tr>
                    </thead>
                    <tbody>
                      {items.map((item) => (
                        <tr key={item.id}>
                          #{field_cells}
                          <td>
                            <Link to={`/#{plural}/${String("${item.id}")}`}>View</Link>
                            {" | "}
                            <button onClick={() => remove(item.id)}>Delete</button>
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                  #{has_pagination ? "<Pagination cursor={cursor} onLoadMore={() => fetchAll(cursor)} loading={loading} />" : ''}
                </div>
              );
            }
          TSX
        end

        def generate_detail_page(name, plural, singular, fields)
          field_rows = fields.map { |f| "<p><strong>#{camelize(f[:name].to_s)}:</strong> {item.#{f[:name]} ?? \"—\"}</p>" }.join("\n          ")

          write_file("src/pages/#{name}Detail.tsx", <<~TSX)
            import { useEffect, useState } from "react";
            import { useParams, useNavigate, Link } from "react-router-dom";
            import { get#{name}, delete#{name} } from "../api/#{plural}";
            import type { #{name} } from "../models/#{singular}";

            export default function #{name}Detail() {
              const { id } = useParams<{ id: string }>();
              const navigate = useNavigate();
              const [item, setItem] = useState<#{name} | null>(null);

              useEffect(() => {
                if (id) get#{name}(id).then(setItem);
              }, [id]);

              if (!item) return <p>Loading...</p>;

              const handleDelete = async () => {
                await delete#{name}(item.id);
                navigate("/#{plural}");
              };

              return (
                <div>
                  <h1>#{name} Detail</h1>
                  #{field_rows}
                  <Link to={`/#{plural}/${String("${item.id}")}/edit`} className="btn">Edit</Link>
                  {" "}
                  <button onClick={handleDelete} className="btn-danger">Delete</button>
                  <br />
                  <Link to="/#{plural}">Back to list</Link>
                </div>
              );
            }
          TSX
        end

        def generate_form_page(name, plural, singular, fields)
          state_lines = fields.map do |f|
            default_val = f[:default] ? "\"#{f[:default]}\"" : "\"\""
            "const [#{f[:name]}, set#{camelize(f[:name].to_s)}] = useState(#{default_val});"
          end.join("\n  ")

          load_lines = fields.map { |f| "set#{camelize(f[:name].to_s)}(data.#{f[:name]} ?? \"\");" }.join("\n        ")

          input_fields = fields.map do |f|
            fname = f[:name].to_s
            setter = "set#{camelize(fname)}"
            if f[:enum]
              options = f[:enum].map { |v| "<option value=\"#{v}\">#{v}</option>" }.join("\n              ")
              <<~FIELD.strip
                <label>#{camelize(fname)}
                    <select value={#{fname}} onChange={(e) => #{setter}(e.target.value)}>
                      <option value="">Select...</option>
                      #{options}
                    </select>
                  </label>
              FIELD
            else
              required_attr = f[:required] ? " required" : ""
              <<~FIELD.strip
                <label>#{camelize(fname)}
                    <input value={#{fname}} onChange={(e) => #{setter}(e.target.value)}#{required_attr} />
                  </label>
              FIELD
            end
          end.join("\n          ")

          body_fields = fields.map { |f| "#{f[:name]}" }.join(", ")

          write_file("src/pages/#{name}Form.tsx", <<~TSX)
            import { useState, useEffect, FormEvent } from "react";
            import { useParams, useNavigate } from "react-router-dom";
            import { get#{name}, create#{name}, update#{name} } from "../api/#{plural}";

            export default function #{name}Form() {
              const { id } = useParams<{ id: string }>();
              const navigate = useNavigate();
              const isEdit = Boolean(id);
              #{state_lines}
              const [error, setError] = useState<string | null>(null);

              useEffect(() => {
                if (id) {
                  get#{name}(id).then((data) => {
                    #{load_lines}
                  });
                }
              }, [id]);

              const handleSubmit = async (e: FormEvent) => {
                e.preventDefault();
                setError(null);
                try {
                  const body = { #{body_fields} };
                  if (isEdit && id) {
                    await update#{name}(id, body);
                  } else {
                    await create#{name}(body);
                  }
                  navigate("/#{plural}");
                } catch (err: any) {
                  setError(err.message || "Save failed");
                }
              };

              return (
                <div>
                  <h1>{isEdit ? "Edit" : "New"} #{name}</h1>
                  {error && <p className="error">{error}</p>}
                  <form onSubmit={handleSubmit}>
                    #{input_fields}
                    <button type="submit">{isEdit ? "Update" : "Create"}</button>
                  </form>
                </div>
              );
            }
          TSX
        end

        # ── Components ────────────────────────────────────────────────

        def generate_components
          generate_layout
          generate_protected_route
          generate_pagination
        end

        def generate_layout
          resource_links = ir.resources.map do |r|
            plural = r.name.to_s
            name = classify(r.name)
            "<Link to=\"/#{plural}\">#{name}s</Link>"
          end.join("\n            ")

          write_file("src/components/Layout.tsx", <<~TSX)
            import { Outlet, Link } from "react-router-dom";
            import { useAuth } from "../hooks/useAuth";

            export default function Layout() {
              const { user, logout } = useAuth();

              return (
                <div className="layout">
                  <nav>
                    <Link to="/">Home</Link>
                    #{resource_links}
                    {user ? (
                      <>
                        <span>{user.email}</span>
                        <button onClick={logout}>Logout</button>
                      </>
                    ) : (
                      <Link to="/login">Login</Link>
                    )}
                  </nav>
                  <main>
                    <Outlet />
                  </main>
                </div>
              );
            }
          TSX
        end

        def generate_protected_route
          write_file("src/components/ProtectedRoute.tsx", <<~TSX)
            import { Navigate, Outlet } from "react-router-dom";
            import { useAuth } from "../hooks/useAuth";

            export default function ProtectedRoute() {
              const { user, loading } = useAuth();
              if (loading) return <p>Loading...</p>;
              if (!user) return <Navigate to="/login" replace />;
              return <Outlet />;
            }
          TSX
        end

        def generate_pagination
          write_file("src/components/Pagination.tsx", <<~TSX)
            interface Props {
              cursor?: string;
              onLoadMore: () => void;
              loading: boolean;
            }

            export default function Pagination({ cursor, onLoadMore, loading }: Props) {
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

        # ── Router / App / Main ───────────────────────────────────────

        def generate_router
          resource_imports = ir.resources.map do |r|
            name = classify(r.name)
            plural = r.name.to_s
            <<~TS.chomp
              import #{name}List from "./pages/#{name}List";
              import #{name}Detail from "./pages/#{name}Detail";
              import #{name}Form from "./pages/#{name}Form";
            TS
          end.join("\n")

          resource_routes = ir.resources.map do |r|
            name = classify(r.name)
            plural = r.name.to_s
            <<~TSX.chomp
                      <Route path="/#{plural}" element={<#{name}List />} />
                      <Route path="/#{plural}/new" element={<#{name}Form />} />
                      <Route path="/#{plural}/:id" element={<#{name}Detail />} />
                      <Route path="/#{plural}/:id/edit" element={<#{name}Form />} />
            TSX
          end.join("\n")

          write_file("src/router.tsx", <<~TSX)
            import { BrowserRouter, Routes, Route } from "react-router-dom";
            import Layout from "./components/Layout";
            import ProtectedRoute from "./components/ProtectedRoute";
            import Login from "./pages/Login";
            import Register from "./pages/Register";
            #{resource_imports}

            export default function AppRouter() {
              return (
                <BrowserRouter>
                  <Routes>
                    <Route element={<Layout />}>
                      <Route path="/login" element={<Login />} />
                      <Route path="/register" element={<Register />} />
                      <Route element={<ProtectedRoute />}>
            #{resource_routes}
                      </Route>
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
            body { font-family: system-ui, sans-serif; line-height: 1.6; color: #333; }
            .layout { max-width: 960px; margin: 0 auto; padding: 1rem; }
            nav { display: flex; gap: 1rem; align-items: center; padding: 1rem 0; border-bottom: 1px solid #ddd; margin-bottom: 1rem; }
            nav a { text-decoration: none; color: #0066cc; }
            table { width: 100%; border-collapse: collapse; margin: 1rem 0; }
            th, td { padding: 0.5rem; border: 1px solid #ddd; text-align: left; }
            th { background: #f5f5f5; }
            form { display: flex; flex-direction: column; gap: 0.75rem; max-width: 400px; }
            label { display: flex; flex-direction: column; gap: 0.25rem; }
            input, select { padding: 0.5rem; border: 1px solid #ccc; border-radius: 4px; }
            button, .btn { padding: 0.5rem 1rem; background: #0066cc; color: #fff; border: none; border-radius: 4px; cursor: pointer; text-decoration: none; display: inline-block; }
            button:hover, .btn:hover { background: #0052a3; }
            .btn-danger { background: #cc0000; }
            .btn-danger:hover { background: #990000; }
            .error { color: #cc0000; margin: 0.5rem 0; }
            .auth-page { max-width: 400px; margin: 2rem auto; }
            .pagination { margin: 1rem 0; }
          CSS
        end
      end
    end
  end
end
