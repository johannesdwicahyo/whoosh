# Client Generator — Mobile & Bot Clients Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the `expo`, `ios`, `flutter`, and `telegram_bot` client generators that consume the IR from Plan 1.

**Architecture:** Each generator extends `BaseGenerator`, reads the IR, and writes a complete project. Expo and Telegram Bot share patterns with the web generators; iOS and Flutter are native platform generators.

**Tech Stack:** Ruby (generators), TypeScript/Expo (expo), Swift/SwiftUI (ios), Dart/Flutter (flutter), Ruby (telegram_bot)

**Depends on:** Plan 1 (Core Engine) must be completed first. Can run in parallel with Plan 2.

---

## File Structure

```
lib/whoosh/client_gen/generators/
├── expo.rb                      # Expo + React Native generator
├── ios.rb                       # Swift + SwiftUI generator
├── flutter.rb                   # Dart + Flutter generator
└── telegram_bot.rb              # Ruby Telegram bot generator
spec/whoosh/client_gen/generators/
├── expo_spec.rb
├── ios_spec.rb
├── flutter_spec.rb
└── telegram_bot_spec.rb
```

---

### Task 1: Expo Generator

**Files:**
- Create: `lib/whoosh/client_gen/generators/expo.rb`
- Test: `spec/whoosh/client_gen/generators/expo_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/whoosh/client_gen/generators/expo_spec.rb
# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "whoosh/client_gen/ir"
require "whoosh/client_gen/generators/expo"

RSpec.describe Whoosh::ClientGen::Generators::Expo do
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
        )
      ],
      streaming: [],
      base_url: "http://localhost:9292"
    )
  end

  it "generates a complete Expo project" do
    Dir.mktmpdir do |dir|
      described_class.new(ir: ir, output_dir: dir, platform: :typescript).generate

      expect(File.exist?(File.join(dir, "package.json"))).to be true
      expect(File.exist?(File.join(dir, "app.json"))).to be true
      expect(File.exist?(File.join(dir, "tsconfig.json"))).to be true
      expect(File.exist?(File.join(dir, ".env"))).to be true
    end
  end

  it "uses Expo Router file-based routing" do
    Dir.mktmpdir do |dir|
      described_class.new(ir: ir, output_dir: dir, platform: :typescript).generate

      expect(File.exist?(File.join(dir, "app", "_layout.tsx"))).to be true
      expect(File.exist?(File.join(dir, "app", "(auth)", "login.tsx"))).to be true
      expect(File.exist?(File.join(dir, "app", "(auth)", "register.tsx"))).to be true
      expect(File.exist?(File.join(dir, "app", "(app)", "tasks", "index.tsx"))).to be true
      expect(File.exist?(File.join(dir, "app", "(app)", "tasks", "[id].tsx"))).to be true
      expect(File.exist?(File.join(dir, "app", "(app)", "tasks", "form.tsx"))).to be true
    end
  end

  it "uses SecureStore for token storage" do
    Dir.mktmpdir do |dir|
      described_class.new(ir: ir, output_dir: dir, platform: :typescript).generate

      auth_store = File.read(File.join(dir, "src", "store", "auth.ts"))
      expect(auth_store).to include("SecureStore")
    end
  end

  it "generates typed API client" do
    Dir.mktmpdir do |dir|
      described_class.new(ir: ir, output_dir: dir, platform: :typescript).generate

      client = File.read(File.join(dir, "src", "api", "client.ts"))
      expect(client).to include("Authorization")
      expect(client).to include("Bearer")
    end
  end

  it "generates resource API and hooks" do
    Dir.mktmpdir do |dir|
      described_class.new(ir: ir, output_dir: dir, platform: :typescript).generate

      expect(File.exist?(File.join(dir, "src", "api", "tasks.ts"))).to be true
      expect(File.exist?(File.join(dir, "src", "hooks", "useTasks.ts"))).to be true
    end
  end

  it "package.json includes expo dependencies" do
    Dir.mktmpdir do |dir|
      described_class.new(ir: ir, output_dir: dir, platform: :typescript).generate

      pkg = File.read(File.join(dir, "package.json"))
      expect(pkg).to include("expo")
      expect(pkg).to include("expo-router")
      expect(pkg).to include("expo-secure-store")
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/whoosh/client_gen/generators/expo_spec.rb -v`
Expected: FAIL with "cannot load such file"

- [ ] **Step 3: Write the Expo generator**

The Expo generator follows the same pattern as ReactSpa but adapts for React Native:
- Uses Expo Router (file-based) instead of React Router
- Uses `expo-secure-store` instead of localStorage for tokens
- Uses React Native components (`View`, `Text`, `TextInput`, `Pressable`) instead of HTML elements
- Uses `StyleSheet.create` instead of CSS

```ruby
# lib/whoosh/client_gen/generators/expo.rb
# frozen_string_literal: true

require "json"
require "whoosh/client_gen/base_generator"

module Whoosh
  module ClientGen
    module Generators
      class Expo < BaseGenerator
        def generate
          generate_config_files
          generate_auth_store
          generate_api_client
          generate_auth_api
          generate_models
          generate_resource_apis
          generate_hooks
          generate_layouts
          generate_auth_screens
          generate_resource_screens
        end

        private

        def generate_config_files
          write_file("package.json", package_json)
          write_file("app.json", app_json)
          write_file("tsconfig.json", tsconfig_json)
          write_file(".env", "API_URL=#{ir.base_url}\n")
          write_file(".gitignore", "node_modules/\n.expo/\ndist/\n.env.local\n")
        end

        def generate_auth_store
          write_file("src/store/auth.ts", <<~TS)
            import * as SecureStore from "expo-secure-store";

            const ACCESS_TOKEN_KEY = "access_token";
            const REFRESH_TOKEN_KEY = "refresh_token";

            export async function getAccessToken(): Promise<string | null> {
              return SecureStore.getItemAsync(ACCESS_TOKEN_KEY);
            }

            export async function getRefreshToken(): Promise<string | null> {
              return SecureStore.getItemAsync(REFRESH_TOKEN_KEY);
            }

            export async function setTokens(access: string, refresh: string): Promise<void> {
              await SecureStore.setItemAsync(ACCESS_TOKEN_KEY, access);
              await SecureStore.setItemAsync(REFRESH_TOKEN_KEY, refresh);
            }

            export async function clearTokens(): Promise<void> {
              await SecureStore.deleteItemAsync(ACCESS_TOKEN_KEY);
              await SecureStore.deleteItemAsync(REFRESH_TOKEN_KEY);
            }
          TS
        end

        def generate_api_client
          write_file("src/api/client.ts", <<~TS)
            import { getAccessToken, getRefreshToken, setTokens, clearTokens } from "../store/auth";

            const API_URL = process.env.API_URL || "http://localhost:9292";

            async function refreshAccessToken(): Promise<boolean> {
              const refreshToken = await getRefreshToken();
              const accessToken = await getAccessToken();
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
                await setTokens(data.token, data.refresh_token);
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
              const token = await getAccessToken();
              const headers: Record<string, string> = {
                "Content-Type": "application/json",
                ...(options.headers as Record<string, string>),
              };

              if (token) {
                headers["Authorization"] = `Bearer ${token}`;
              }

              let res = await fetch(url, { ...options, headers });

              if (res.status === 401) {
                const refreshed = await refreshAccessToken();
                if (refreshed) {
                  const newToken = await getAccessToken();
                  headers["Authorization"] = `Bearer ${newToken}`;
                  res = await fetch(url, { ...options, headers });
                } else {
                  await clearTokens();
                  throw { status: 401, message: "Session expired" };
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
            import { apiRequest } from "./client";
            import { setTokens, clearTokens } from "../store/auth";

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
              await setTokens(data.token, data.refresh_token);
              return data;
            }

            export async function register(name: string, email: string, password: string): Promise<TokenResponse> {
              const data = await apiRequest<TokenResponse>("/auth/register", {
                method: "POST",
                body: JSON.stringify({ name, email, password }),
              });
              await setTokens(data.token, data.refresh_token);
              return data;
            }

            export async function logout(): Promise<void> {
              try {
                await apiRequest("/auth/logout", { method: "DELETE" });
              } finally {
                await clearTokens();
              }
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
          write_file("src/hooks/useAuth.ts", <<~TS)
            import { useState, useCallback, useEffect } from "react";
            import { login as apiLogin, register as apiRegister, logout as apiLogout, getMe } from "../api/auth";
            import { getAccessToken, clearTokens } from "../store/auth";

            interface User { id: number; name: string; email: string; }

            export function useAuth() {
              const [user, setUser] = useState<User | null>(null);
              const [loading, setLoading] = useState(true);

              useEffect(() => {
                (async () => {
                  const token = await getAccessToken();
                  if (token) {
                    try { setUser(await getMe()); } catch { await clearTokens(); }
                  }
                  setLoading(false);
                })();
              }, []);

              const login = useCallback(async (email: string, password: string) => {
                await apiLogin(email, password);
                setUser(await getMe());
              }, []);

              const register = useCallback(async (name: string, email: string, password: string) => {
                await apiRegister(name, email, password);
                setUser(await getMe());
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
              import { list#{name}s, create#{name}, update#{name}, delete#{name} } from "../api/#{plural}";

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

                const update = useCallback(async (id: number | string, input: Update#{name}Input) => {
                  const item = await update#{name}(id, input);
                  setItems(prev => prev.map(i => i.id === item.id ? item : i));
                  return item;
                }, []);

                const remove = useCallback(async (id: number | string) => {
                  await delete#{name}(id);
                  setItems(prev => prev.filter(i => i.id !== Number(id)));
                }, []);

                return { items, loading, error, fetchAll, create, update, remove };
              }
            TS
          end
        end

        def generate_layouts
          write_file("app/_layout.tsx", <<~TSX)
            import { useEffect, useState } from "react";
            import { Slot, useRouter, useSegments } from "expo-router";
            import { useAuth } from "../src/hooks/useAuth";

            export default function RootLayout() {
              const { isAuthenticated, loading } = useAuth();
              const segments = useSegments();
              const router = useRouter();

              useEffect(() => {
                if (loading) return;
                const inAuth = segments[0] === "(auth)";

                if (!isAuthenticated && !inAuth) {
                  router.replace("/(auth)/login");
                } else if (isAuthenticated && inAuth) {
                  router.replace("/(app)/#{ir.resources.first&.name || "index"}");
                }
              }, [isAuthenticated, loading, segments]);

              if (loading) return null;

              return <Slot />;
            }
          TSX

          write_file("app/(app)/_layout.tsx", <<~TSX)
            import { Stack } from "expo-router";

            export default function AppLayout() {
              return <Stack screenOptions={{ headerShown: true }} />;
            }
          TSX
        end

        def generate_auth_screens
          write_file("app/(auth)/login.tsx", <<~TSX)
            import { useState } from "react";
            import { View, Text, TextInput, Pressable, StyleSheet, Alert } from "react-native";
            import { Link } from "expo-router";
            import { useAuth } from "../../src/hooks/useAuth";

            export default function LoginScreen() {
              const { login } = useAuth();
              const [email, setEmail] = useState("");
              const [password, setPassword] = useState("");
              const [loading, setLoading] = useState(false);

              async function handleLogin() {
                setLoading(true);
                try {
                  await login(email, password);
                } catch (err: any) {
                  Alert.alert("Error", err.message || "Login failed");
                } finally {
                  setLoading(false);
                }
              }

              return (
                <View style={styles.container}>
                  <Text style={styles.title}>Login</Text>
                  <TextInput style={styles.input} placeholder="Email" value={email} onChangeText={setEmail} keyboardType="email-address" autoCapitalize="none" />
                  <TextInput style={styles.input} placeholder="Password" value={password} onChangeText={setPassword} secureTextEntry />
                  <Pressable style={styles.button} onPress={handleLogin} disabled={loading}>
                    <Text style={styles.buttonText}>{loading ? "Logging in..." : "Login"}</Text>
                  </Pressable>
                  <Link href="/(auth)/register" style={styles.link}>Don't have an account? Register</Link>
                </View>
              );
            }

            const styles = StyleSheet.create({
              container: { flex: 1, padding: 24, justifyContent: "center" },
              title: { fontSize: 28, fontWeight: "bold", marginBottom: 24 },
              input: { borderWidth: 1, borderColor: "#ccc", borderRadius: 8, padding: 12, marginBottom: 12, fontSize: 16 },
              button: { backgroundColor: "#2563eb", padding: 14, borderRadius: 8, alignItems: "center", marginBottom: 12 },
              buttonText: { color: "white", fontSize: 16, fontWeight: "600" },
              link: { color: "#2563eb", textAlign: "center" },
            });
          TSX

          write_file("app/(auth)/register.tsx", <<~TSX)
            import { useState } from "react";
            import { View, Text, TextInput, Pressable, StyleSheet, Alert } from "react-native";
            import { Link } from "expo-router";
            import { useAuth } from "../../src/hooks/useAuth";

            export default function RegisterScreen() {
              const { register } = useAuth();
              const [name, setName] = useState("");
              const [email, setEmail] = useState("");
              const [password, setPassword] = useState("");
              const [loading, setLoading] = useState(false);

              async function handleRegister() {
                setLoading(true);
                try {
                  await register(name, email, password);
                } catch (err: any) {
                  Alert.alert("Error", err.message || "Registration failed");
                } finally {
                  setLoading(false);
                }
              }

              return (
                <View style={styles.container}>
                  <Text style={styles.title}>Register</Text>
                  <TextInput style={styles.input} placeholder="Name" value={name} onChangeText={setName} />
                  <TextInput style={styles.input} placeholder="Email" value={email} onChangeText={setEmail} keyboardType="email-address" autoCapitalize="none" />
                  <TextInput style={styles.input} placeholder="Password" value={password} onChangeText={setPassword} secureTextEntry />
                  <Pressable style={styles.button} onPress={handleRegister} disabled={loading}>
                    <Text style={styles.buttonText}>{loading ? "Registering..." : "Register"}</Text>
                  </Pressable>
                  <Link href="/(auth)/login" style={styles.link}>Already have an account? Login</Link>
                </View>
              );
            }

            const styles = StyleSheet.create({
              container: { flex: 1, padding: 24, justifyContent: "center" },
              title: { fontSize: 28, fontWeight: "bold", marginBottom: 24 },
              input: { borderWidth: 1, borderColor: "#ccc", borderRadius: 8, padding: 12, marginBottom: 12, fontSize: 16 },
              button: { backgroundColor: "#2563eb", padding: 14, borderRadius: 8, alignItems: "center", marginBottom: 12 },
              buttonText: { color: "white", fontSize: 16, fontWeight: "600" },
              link: { color: "#2563eb", textAlign: "center" },
            });
          TSX
        end

        def generate_resource_screens
          ir.resources.each do |resource|
            name = classify(resource.name)
            plural = resource.name.to_s
            singular = singularize(plural)
            first_field = resource.fields.first&.dig(:name) || "id"

            write_file("app/(app)/#{plural}/index.tsx", <<~TSX)
              import { useEffect } from "react";
              import { View, Text, FlatList, Pressable, StyleSheet } from "react-native";
              import { useRouter } from "expo-router";
              import { use#{name}s } from "../../../src/hooks/use#{name}s";

              export default function #{name}ListScreen() {
                const { items, loading, fetchAll, remove } = use#{name}s();
                const router = useRouter();

                useEffect(() => { fetchAll(); }, []);

                return (
                  <View style={styles.container}>
                    <Pressable style={styles.addButton} onPress={() => router.push("/(app)/#{plural}/form")}>
                      <Text style={styles.addButtonText}>+ New #{name}</Text>
                    </Pressable>
                    <FlatList
                      data={items}
                      keyExtractor={item => String(item.id)}
                      refreshing={loading}
                      onRefresh={fetchAll}
                      renderItem={({ item }) => (
                        <Pressable style={styles.item} onPress={() => router.push(`/(app)/#{plural}/${item.id}`)}>
                          <Text style={styles.itemTitle}>{item.#{first_field}}</Text>
                          <Pressable onPress={() => remove(item.id)}>
                            <Text style={styles.deleteText}>Delete</Text>
                          </Pressable>
                        </Pressable>
                      )}
                      ListEmptyComponent={<Text style={styles.empty}>No #{plural} yet</Text>}
                    />
                  </View>
                );
              }

              const styles = StyleSheet.create({
                container: { flex: 1, padding: 16 },
                addButton: { backgroundColor: "#2563eb", padding: 12, borderRadius: 8, alignItems: "center", marginBottom: 16 },
                addButtonText: { color: "white", fontWeight: "600" },
                item: { flexDirection: "row", justifyContent: "space-between", alignItems: "center", padding: 16, backgroundColor: "#f9f9f9", borderRadius: 8, marginBottom: 8 },
                itemTitle: { fontSize: 16 },
                deleteText: { color: "#dc2626", fontWeight: "600" },
                empty: { textAlign: "center", color: "#888", marginTop: 24 },
              });
            TSX

            write_file("app/(app)/#{plural}/[id].tsx", <<~TSX)
              import { useEffect, useState } from "react";
              import { View, Text, StyleSheet, Alert, Pressable } from "react-native";
              import { useLocalSearchParams, useRouter } from "expo-router";
              import { get#{name}, delete#{name} } from "../../../src/api/#{plural}";
              import type { #{name} } from "../../../src/models/#{singular}";

              export default function #{name}DetailScreen() {
                const { id } = useLocalSearchParams<{ id: string }>();
                const router = useRouter();
                const [item, setItem] = useState<#{name} | null>(null);

                useEffect(() => {
                  if (id) get#{name}(id).then(setItem);
                }, [id]);

                function handleDelete() {
                  Alert.alert("Delete", "Are you sure?", [
                    { text: "Cancel" },
                    { text: "Delete", style: "destructive", onPress: async () => {
                      if (id) { await delete#{name}(id); router.back(); }
                    }},
                  ]);
                }

                if (!item) return <View style={styles.container}><Text>Loading...</Text></View>;

                return (
                  <View style={styles.container}>
              #{resource.fields.map { |f| "      <View style={styles.field}>\n        <Text style={styles.label}>#{f[:name]}</Text>\n        <Text>{item.#{f[:name]} ?? \"-\"}</Text>\n      </View>" }.join("\n")}
                    <View style={styles.actions}>
                      <Pressable style={styles.editButton} onPress={() => router.push({ pathname: "/(app)/#{plural}/form", params: { id } })}>
                        <Text style={styles.editButtonText}>Edit</Text>
                      </Pressable>
                      <Pressable style={styles.deleteButton} onPress={handleDelete}>
                        <Text style={styles.deleteButtonText}>Delete</Text>
                      </Pressable>
                    </View>
                  </View>
                );
              }

              const styles = StyleSheet.create({
                container: { flex: 1, padding: 16 },
                field: { marginBottom: 16 },
                label: { fontWeight: "600", color: "#666", marginBottom: 4, fontSize: 13 },
                actions: { flexDirection: "row", gap: 12, marginTop: 24 },
                editButton: { backgroundColor: "#2563eb", padding: 12, borderRadius: 8, flex: 1, alignItems: "center" },
                editButtonText: { color: "white", fontWeight: "600" },
                deleteButton: { backgroundColor: "#dc2626", padding: 12, borderRadius: 8, flex: 1, alignItems: "center" },
                deleteButtonText: { color: "white", fontWeight: "600" },
              });
            TSX

            state_inits = resource.fields.map { |f|
              "  const [#{f[:name]}, set#{camelize(f[:name].to_s)}] = useState(\"#{f[:default] || ""}\");"
            }.join("\n")

            load_fields = resource.fields.map { |f|
              "        set#{camelize(f[:name].to_s)}(data.#{f[:name]} ?? \"\");"
            }.join("\n")

            form_fields = resource.fields.map { |f|
              "      <Text style={styles.label}>#{f[:name]}</Text>\n      <TextInput style={styles.input} value={#{f[:name]}} onChangeText={set#{camelize(f[:name].to_s)}} placeholder=\"#{f[:name]}\" />"
            }.join("\n")

            body_fields = resource.fields.map { |f| "#{f[:name]}" }.join(", ")

            write_file("app/(app)/#{plural}/form.tsx", <<~TSX)
              import { useState, useEffect } from "react";
              import { View, Text, TextInput, Pressable, StyleSheet, Alert } from "react-native";
              import { useLocalSearchParams, useRouter } from "expo-router";
              import { create#{name}, update#{name}, get#{name} } from "../../../src/api/#{plural}";

              export default function #{name}FormScreen() {
                const { id } = useLocalSearchParams<{ id?: string }>();
                const router = useRouter();
                const isEditing = Boolean(id);
              #{state_inits}
                const [loading, setLoading] = useState(false);

                useEffect(() => {
                  if (id) {
                    get#{name}(id).then(data => {
              #{load_fields}
                    });
                  }
                }, [id]);

                async function handleSubmit() {
                  setLoading(true);
                  try {
                    const body = { #{body_fields} };
                    if (isEditing) {
                      await update#{name}(id!, body);
                    } else {
                      await create#{name}(body);
                    }
                    router.back();
                  } catch (err: any) {
                    Alert.alert("Error", err.message || "Failed to save");
                  } finally {
                    setLoading(false);
                  }
                }

                return (
                  <View style={styles.container}>
                    <Text style={styles.title}>{isEditing ? "Edit" : "New"} #{name}</Text>
              #{form_fields}
                    <Pressable style={styles.button} onPress={handleSubmit} disabled={loading}>
                      <Text style={styles.buttonText}>{loading ? "Saving..." : "Save"}</Text>
                    </Pressable>
                  </View>
                );
              }

              const styles = StyleSheet.create({
                container: { flex: 1, padding: 16 },
                title: { fontSize: 24, fontWeight: "bold", marginBottom: 24 },
                label: { fontWeight: "600", color: "#666", marginBottom: 4, marginTop: 12, fontSize: 13 },
                input: { borderWidth: 1, borderColor: "#ccc", borderRadius: 8, padding: 12, fontSize: 16 },
                button: { backgroundColor: "#2563eb", padding: 14, borderRadius: 8, alignItems: "center", marginTop: 24 },
                buttonText: { color: "white", fontSize: 16, fontWeight: "600" },
              });
            TSX
          end
        end

        def package_json
          JSON.pretty_generate({
            name: "whoosh-expo-client",
            version: "1.0.0",
            main: "expo-router/entry",
            scripts: {
              start: "expo start",
              android: "expo start --android",
              ios: "expo start --ios",
              web: "expo start --web"
            },
            dependencies: {
              expo: "~52.0.0",
              "expo-router": "~4.0.0",
              "expo-secure-store": "~14.0.0",
              "expo-status-bar": "~2.0.0",
              react: "19.0.0",
              "react-native": "0.76.0",
              "react-dom": "19.0.0",
              "react-native-web": "~0.19.0",
              "react-native-safe-area-context": "4.12.0",
              "react-native-screens": "~4.1.0"
            },
            devDependencies: {
              "@types/react": "~19.0.0",
              typescript: "~5.6.0"
            }
          })
        end

        def app_json
          JSON.pretty_generate({
            expo: {
              name: "whoosh-client",
              slug: "whoosh-client",
              version: "1.0.0",
              scheme: "whoosh",
              platforms: ["ios", "android"],
              ios: { bundleIdentifier: "com.whoosh.client" },
              android: { package: "com.whoosh.client" },
              plugins: ["expo-router", "expo-secure-store"]
            }
          })
        end

        def tsconfig_json
          JSON.pretty_generate({
            extends: "expo/tsconfig.base",
            compilerOptions: { strict: true, paths: { "@/*": ["./src/*"] } }
          })
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/whoosh/client_gen/generators/expo_spec.rb -v`
Expected: All 6 examples pass

- [ ] **Step 5: Commit**

```bash
git add lib/whoosh/client_gen/generators/expo.rb spec/whoosh/client_gen/generators/expo_spec.rb
git commit -m "feat: add Expo React Native client generator"
```

---

### Task 2: iOS Swift Generator

**Files:**
- Create: `lib/whoosh/client_gen/generators/ios.rb`
- Test: `spec/whoosh/client_gen/generators/ios_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/whoosh/client_gen/generators/ios_spec.rb
# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "whoosh/client_gen/ir"
require "whoosh/client_gen/generators/ios"

RSpec.describe Whoosh::ClientGen::Generators::Ios do
  let(:ir) do
    Whoosh::ClientGen::IR::AppSpec.new(
      auth: Whoosh::ClientGen::IR::Auth.new(
        type: :jwt,
        endpoints: {
          login: { method: :post, path: "/auth/login" },
          register: { method: :post, path: "/auth/register" },
          logout: { method: :delete, path: "/auth/logout" },
          me: { method: :get, path: "/auth/me" }
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
            { name: :description, type: :string, required: false },
            { name: :status, type: :string, required: false, enum: %w[pending in_progress done] }
          ]
        )
      ],
      streaming: [],
      base_url: "http://localhost:9292"
    )
  end

  it "generates a complete iOS project" do
    Dir.mktmpdir do |dir|
      described_class.new(ir: ir, output_dir: dir, platform: :swift).generate

      expect(File.exist?(File.join(dir, "WhooshApp", "App.swift"))).to be true
      expect(File.exist?(File.join(dir, "WhooshApp.xcodeproj", "project.pbxproj"))).to be true
    end
  end

  it "generates Codable model structs" do
    Dir.mktmpdir do |dir|
      described_class.new(ir: ir, output_dir: dir, platform: :swift).generate

      model = File.read(File.join(dir, "WhooshApp", "Models", "Task.swift"))
      expect(model).to include("struct Task")
      expect(model).to include("Codable")
      expect(model).to include("var title: String")
    end
  end

  it "generates APIClient with auth interceptor" do
    Dir.mktmpdir do |dir|
      described_class.new(ir: ir, output_dir: dir, platform: :swift).generate

      client = File.read(File.join(dir, "WhooshApp", "API", "APIClient.swift"))
      expect(client).to include("URLSession")
      expect(client).to include("Authorization")
      expect(client).to include("Bearer")
    end
  end

  it "generates KeychainHelper" do
    Dir.mktmpdir do |dir|
      described_class.new(ir: ir, output_dir: dir, platform: :swift).generate

      keychain = File.read(File.join(dir, "WhooshApp", "Keychain", "KeychainHelper.swift"))
      expect(keychain).to include("SecItemAdd")
      expect(keychain).to include("kSecClass")
    end
  end

  it "generates SwiftUI views" do
    Dir.mktmpdir do |dir|
      described_class.new(ir: ir, output_dir: dir, platform: :swift).generate

      expect(File.exist?(File.join(dir, "WhooshApp", "Views", "Auth", "LoginView.swift"))).to be true
      expect(File.exist?(File.join(dir, "WhooshApp", "Views", "Auth", "RegisterView.swift"))).to be true
      expect(File.exist?(File.join(dir, "WhooshApp", "Views", "Tasks", "TaskListView.swift"))).to be true
      expect(File.exist?(File.join(dir, "WhooshApp", "Views", "Tasks", "TaskDetailView.swift"))).to be true
      expect(File.exist?(File.join(dir, "WhooshApp", "Views", "Tasks", "TaskFormView.swift"))).to be true
    end
  end

  it "generates ViewModels" do
    Dir.mktmpdir do |dir|
      described_class.new(ir: ir, output_dir: dir, platform: :swift).generate

      expect(File.exist?(File.join(dir, "WhooshApp", "ViewModels", "AuthViewModel.swift"))).to be true
      expect(File.exist?(File.join(dir, "WhooshApp", "ViewModels", "TaskViewModel.swift"))).to be true
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/whoosh/client_gen/generators/ios_spec.rb -v`
Expected: FAIL with "cannot load such file"

- [ ] **Step 3: Write the iOS generator**

This is a large file. The generator creates a complete SwiftUI project with MVVM architecture, Keychain token storage, and URLSession-based API client. Due to the size, create it in `lib/whoosh/client_gen/generators/ios.rb` with these key methods:

- `generate` — orchestrates all file generation
- `generate_xcode_project` — writes a minimal `project.pbxproj`
- `generate_app_entry` — SwiftUI `@main` App struct with auth state
- `generate_api_client` — URLSession wrapper with async/await, auth headers, token refresh
- `generate_keychain_helper` — Keychain Services wrapper for token storage
- `generate_auth_service` — login/register/logout API calls
- `generate_resource_services` — CRUD API calls per resource
- `generate_models` — Codable structs from IR fields
- `generate_view_models` — ObservableObject classes for auth and each resource
- `generate_auth_views` — LoginView, RegisterView with form bindings
- `generate_resource_views` — ListView (List + NavigationLink), DetailView, FormView per resource

Each Swift file should use:
- `async/await` for all API calls
- `@Published` properties in ViewModels
- `@StateObject` / `@EnvironmentObject` for state management
- Navigation via `NavigationStack` + `NavigationLink`

The implementation follows the same pattern as the other generators — string templates written via `write_file`. The full implementation is ~500 lines of Ruby generating Swift code.

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/whoosh/client_gen/generators/ios_spec.rb -v`
Expected: All 6 examples pass

- [ ] **Step 5: Commit**

```bash
git add lib/whoosh/client_gen/generators/ios.rb spec/whoosh/client_gen/generators/ios_spec.rb
git commit -m "feat: add iOS SwiftUI client generator"
```

---

### Task 3: Flutter Generator

**Files:**
- Create: `lib/whoosh/client_gen/generators/flutter.rb`
- Test: `spec/whoosh/client_gen/generators/flutter_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/whoosh/client_gen/generators/flutter_spec.rb
# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "whoosh/client_gen/ir"
require "whoosh/client_gen/generators/flutter"

RSpec.describe Whoosh::ClientGen::Generators::Flutter do
  let(:ir) do
    Whoosh::ClientGen::IR::AppSpec.new(
      auth: Whoosh::ClientGen::IR::Auth.new(
        type: :jwt,
        endpoints: {
          login: { method: :post, path: "/auth/login" },
          register: { method: :post, path: "/auth/register" },
          logout: { method: :delete, path: "/auth/logout" }
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

  it "generates a complete Flutter project" do
    Dir.mktmpdir do |dir|
      described_class.new(ir: ir, output_dir: dir, platform: :dart).generate

      expect(File.exist?(File.join(dir, "pubspec.yaml"))).to be true
      expect(File.exist?(File.join(dir, "lib", "main.dart"))).to be true
    end
  end

  it "generates Dart model classes" do
    Dir.mktmpdir do |dir|
      described_class.new(ir: ir, output_dir: dir, platform: :dart).generate

      model = File.read(File.join(dir, "lib", "models", "task.dart"))
      expect(model).to include("class Task")
      expect(model).to include("String title")
      expect(model).to include("fromJson")
      expect(model).to include("toJson")
    end
  end

  it "generates API client with Dio" do
    Dir.mktmpdir do |dir|
      described_class.new(ir: ir, output_dir: dir, platform: :dart).generate

      client = File.read(File.join(dir, "lib", "api", "client.dart"))
      expect(client).to include("Dio")
      expect(client).to include("Authorization")
    end
  end

  it "generates auth and resource services" do
    Dir.mktmpdir do |dir|
      described_class.new(ir: ir, output_dir: dir, platform: :dart).generate

      expect(File.exist?(File.join(dir, "lib", "api", "auth_service.dart"))).to be true
      expect(File.exist?(File.join(dir, "lib", "api", "task_service.dart"))).to be true
    end
  end

  it "generates screen files" do
    Dir.mktmpdir do |dir|
      described_class.new(ir: ir, output_dir: dir, platform: :dart).generate

      expect(File.exist?(File.join(dir, "lib", "screens", "auth", "login_screen.dart"))).to be true
      expect(File.exist?(File.join(dir, "lib", "screens", "auth", "register_screen.dart"))).to be true
      expect(File.exist?(File.join(dir, "lib", "screens", "tasks", "task_list_screen.dart"))).to be true
    end
  end

  it "generates providers" do
    Dir.mktmpdir do |dir|
      described_class.new(ir: ir, output_dir: dir, platform: :dart).generate

      expect(File.exist?(File.join(dir, "lib", "providers", "auth_provider.dart"))).to be true
      expect(File.exist?(File.join(dir, "lib", "providers", "task_provider.dart"))).to be true
    end
  end

  it "generates GoRouter configuration" do
    Dir.mktmpdir do |dir|
      described_class.new(ir: ir, output_dir: dir, platform: :dart).generate

      router = File.read(File.join(dir, "lib", "router.dart"))
      expect(router).to include("GoRouter")
      expect(router).to include("/tasks")
      expect(router).to include("/login")
    end
  end

  it "pubspec.yaml includes correct dependencies" do
    Dir.mktmpdir do |dir|
      described_class.new(ir: ir, output_dir: dir, platform: :dart).generate

      pubspec = File.read(File.join(dir, "pubspec.yaml"))
      expect(pubspec).to include("dio:")
      expect(pubspec).to include("flutter_riverpod:")
      expect(pubspec).to include("go_router:")
      expect(pubspec).to include("flutter_secure_storage:")
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/whoosh/client_gen/generators/flutter_spec.rb -v`
Expected: FAIL with "cannot load such file"

- [ ] **Step 3: Write the Flutter generator**

The Flutter generator creates a complete Dart project with:
- Dio HTTP client with auth interceptor
- Riverpod for state management
- GoRouter for navigation
- flutter_secure_storage for tokens
- Model classes with `fromJson` / `toJson`
- Screen widgets for auth and CRUD

Create `lib/whoosh/client_gen/generators/flutter.rb` following the same BaseGenerator pattern. Key methods:

- `generate_pubspec` — YAML pubspec with dependencies
- `generate_main` — main.dart with ProviderScope and MaterialApp.router
- `generate_router` — GoRouter config with auth redirect
- `generate_api_client` — Dio instance with interceptor for JWT
- `generate_auth_service` — login/register/logout
- `generate_resource_services` — CRUD per resource
- `generate_models` — Dart classes with fromJson/toJson
- `generate_providers` — Riverpod StateNotifierProviders
- `generate_screens` — login, register, list, detail, form per resource

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/whoosh/client_gen/generators/flutter_spec.rb -v`
Expected: All 8 examples pass

- [ ] **Step 5: Commit**

```bash
git add lib/whoosh/client_gen/generators/flutter.rb spec/whoosh/client_gen/generators/flutter_spec.rb
git commit -m "feat: add Flutter client generator"
```

---

### Task 4: Telegram Bot Generator

**Files:**
- Create: `lib/whoosh/client_gen/generators/telegram_bot.rb`
- Test: `spec/whoosh/client_gen/generators/telegram_bot_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/whoosh/client_gen/generators/telegram_bot_spec.rb
# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "whoosh/client_gen/ir"
require "whoosh/client_gen/generators/telegram_bot"

RSpec.describe Whoosh::ClientGen::Generators::TelegramBot do
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

  it "generates a complete Telegram bot project" do
    Dir.mktmpdir do |dir|
      described_class.new(ir: ir, output_dir: dir, platform: :ruby).generate

      expect(File.exist?(File.join(dir, "bot.rb"))).to be true
      expect(File.exist?(File.join(dir, "Gemfile"))).to be true
      expect(File.exist?(File.join(dir, "config.yml"))).to be true
    end
  end

  it "generates API client" do
    Dir.mktmpdir do |dir|
      described_class.new(ir: ir, output_dir: dir, platform: :ruby).generate

      client = File.read(File.join(dir, "lib", "api", "client.rb"))
      expect(client).to include("Net::HTTP")
      expect(client).to include("Authorization")
      expect(client).to include("Bearer")
    end
  end

  it "generates command handlers" do
    Dir.mktmpdir do |dir|
      described_class.new(ir: ir, output_dir: dir, platform: :ruby).generate

      expect(File.exist?(File.join(dir, "lib", "handlers", "start_handler.rb"))).to be true
      expect(File.exist?(File.join(dir, "lib", "handlers", "auth_handler.rb"))).to be true
      expect(File.exist?(File.join(dir, "lib", "handlers", "task_handler.rb"))).to be true

      task_handler = File.read(File.join(dir, "lib", "handlers", "task_handler.rb"))
      expect(task_handler).to include("/tasks")
      expect(task_handler).to include("/new")
    end
  end

  it "generates session store" do
    Dir.mktmpdir do |dir|
      described_class.new(ir: ir, output_dir: dir, platform: :ruby).generate

      store = File.read(File.join(dir, "lib", "session", "store.rb"))
      expect(store).to include("token")
    end
  end

  it "generates inline keyboards" do
    Dir.mktmpdir do |dir|
      described_class.new(ir: ir, output_dir: dir, platform: :ruby).generate

      keyboards = File.read(File.join(dir, "lib", "keyboards", "inline_keyboards.rb"))
      expect(keyboards).to include("InlineKeyboardButton")
    end
  end

  it "Gemfile includes telegram-bot-ruby" do
    Dir.mktmpdir do |dir|
      described_class.new(ir: ir, output_dir: dir, platform: :ruby).generate

      gemfile = File.read(File.join(dir, "Gemfile"))
      expect(gemfile).to include("telegram-bot-ruby")
    end
  end

  it "config.yml contains BOT_TOKEN and API_URL" do
    Dir.mktmpdir do |dir|
      described_class.new(ir: ir, output_dir: dir, platform: :ruby).generate

      config = File.read(File.join(dir, "config.yml"))
      expect(config).to include("bot_token")
      expect(config).to include("api_url")
      expect(config).to include("http://localhost:9292")
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/whoosh/client_gen/generators/telegram_bot_spec.rb -v`
Expected: FAIL with "cannot load such file"

- [ ] **Step 3: Write the Telegram Bot generator**

```ruby
# lib/whoosh/client_gen/generators/telegram_bot.rb
# frozen_string_literal: true

require "whoosh/client_gen/base_generator"

module Whoosh
  module ClientGen
    module Generators
      class TelegramBot < BaseGenerator
        def generate
          generate_config_files
          generate_api_client
          generate_auth_service
          generate_resource_services
          generate_session_store
          generate_keyboards
          generate_handlers
          generate_bot_entry
          generate_readme
        end

        private

        def generate_config_files
          write_file("Gemfile", <<~RUBY)
            source "https://rubygems.org"

            gem "telegram-bot-ruby", "~> 2.0"
            gem "net-http"
            gem "json"
            gem "yaml"
          RUBY

          write_file("config.yml", <<~YAML)
            bot_token: <%= ENV.fetch("BOT_TOKEN", "your-bot-token-here") %>
            api_url: #{ir.base_url}
          YAML

          write_file(".gitignore", ".env\n")
          write_file(".env", "BOT_TOKEN=your-bot-token-here\n")
        end

        def generate_api_client
          write_file("lib/api/client.rb", <<~RUBY)
            # frozen_string_literal: true

            require "net/http"
            require "json"
            require "uri"

            class APIClient
              def initialize(base_url:, token: nil)
                @base_url = base_url
                @token = token
              end

              attr_accessor :token

              def get(path)
                request(Net::HTTP::Get, path)
              end

              def post(path, body = {})
                request(Net::HTTP::Post, path, body)
              end

              def put(path, body = {})
                request(Net::HTTP::Put, path, body)
              end

              def delete(path)
                request(Net::HTTP::Delete, path)
              end

              private

              def request(method_class, path, body = nil)
                uri = URI.parse("\#{@base_url}\#{path}")
                http = Net::HTTP.new(uri.host, uri.port)
                http.use_ssl = uri.scheme == "https"

                req = method_class.new(uri.request_uri)
                req["Content-Type"] = "application/json"
                req["Authorization"] = "Bearer \#{@token}" if @token
                req.body = JSON.generate(body) if body

                response = http.request(req)
                JSON.parse(response.body, symbolize_names: true)
              rescue JSON::ParserError
                { error: "Invalid response" }
              end
            end
          RUBY
        end

        def generate_auth_service
          write_file("lib/api/auth_service.rb", <<~RUBY)
            # frozen_string_literal: true

            class AuthService
              def initialize(client)
                @client = client
              end

              def login(email:, password:)
                result = @client.post("/auth/login", { email: email, password: password })
                if result[:token]
                  @client.token = result[:token]
                end
                result
              end

              def register(name:, email:, password:)
                result = @client.post("/auth/register", { name: name, email: email, password: password })
                if result[:token]
                  @client.token = result[:token]
                end
                result
              end
            end
          RUBY
        end

        def generate_resource_services
          ir.resources.each do |resource|
            name = classify(resource.name)
            plural = resource.name.to_s
            singular = singularize(plural)

            methods = []
            resource.endpoints.each do |ep|
              case ep.action
              when :index
                methods << "  def list\n    @client.get(\"/#{plural}\")\n  end"
              when :show
                methods << "  def get(id)\n    @client.get(\"/#{plural}/\#{id}\")\n  end"
              when :create
                methods << "  def create(attrs)\n    @client.post(\"/#{plural}\", attrs)\n  end"
              when :update
                methods << "  def update(id, attrs)\n    @client.put(\"/#{plural}/\#{id}\", attrs)\n  end"
              when :destroy
                methods << "  def delete(id)\n    @client.delete(\"/#{plural}/\#{id}\")\n  end"
              end
            end

            write_file("lib/api/#{singular}_service.rb", <<~RUBY)
              # frozen_string_literal: true

              class #{name}Service
                def initialize(client)
                  @client = client
                end

              #{methods.join("\n\n")}
              end
            RUBY
          end
        end

        def generate_session_store
          write_file("lib/session/store.rb", <<~RUBY)
            # frozen_string_literal: true

            class SessionStore
              def initialize
                @sessions = {}
              end

              def get(chat_id)
                @sessions[chat_id] ||= { state: :idle, token: nil, data: {} }
              end

              def set_token(chat_id, token)
                get(chat_id)[:token] = token
              end

              def get_token(chat_id)
                get(chat_id)[:token]
              end

              def set_state(chat_id, state, data = {})
                session = get(chat_id)
                session[:state] = state
                session[:data] = data
              end

              def clear(chat_id)
                @sessions.delete(chat_id)
              end
            end
          RUBY
        end

        def generate_keyboards
          resource_buttons = ir.resources.map { |r|
            name = classify(r.name)
            "    Telegram::Bot::Types::InlineKeyboardButton.new(text: \"#{name}s\", callback_data: \"list_#{r.name}\")"
          }.join(",\n")

          write_file("lib/keyboards/inline_keyboards.rb", <<~RUBY)
            # frozen_string_literal: true

            module Keyboards
              def self.main_menu
                Telegram::Bot::Types::InlineKeyboardMarkup.new(
                  inline_keyboard: [
                    [
              #{resource_buttons}
                    ]
                  ]
                )
              end
          #{ir.resources.map { |r|
            name = classify(r.name)
            singular = singularize(r.name.to_s)
            <<~KB
              def self.#{singular}_actions(id)
                Telegram::Bot::Types::InlineKeyboardMarkup.new(
                  inline_keyboard: [
                    [
                      Telegram::Bot::Types::InlineKeyboardButton.new(text: "Delete", callback_data: "delete_#{singular}_\#{id}"),
                      Telegram::Bot::Types::InlineKeyboardButton.new(text: "Back", callback_data: "list_#{r.name}")
                    ]
                  ]
                )
              end
            KB
          }.join("\n")}
            end
          RUBY
        end

        def generate_handlers
          write_file("lib/handlers/start_handler.rb", <<~RUBY)
            # frozen_string_literal: true

            module Handlers
              class StartHandler
                def initialize(bot, sessions)
                  @bot = bot
                  @sessions = sessions
                end

                def handle(message)
                  chat_id = message.chat.id
                  token = @sessions.get_token(chat_id)

                  if token
                    @bot.api.send_message(
                      chat_id: chat_id,
                      text: "Welcome back! What would you like to do?",
                      reply_markup: Keyboards.main_menu
                    )
                  else
                    @bot.api.send_message(
                      chat_id: chat_id,
                      text: "Welcome! Please login first.\\nUse /login <email> <password>"
                    )
                  end
                end
              end
            end
          RUBY

          write_file("lib/handlers/auth_handler.rb", <<~RUBY)
            # frozen_string_literal: true

            module Handlers
              class AuthHandler
                def initialize(bot, sessions, auth_service)
                  @bot = bot
                  @sessions = sessions
                  @auth_service = auth_service
                end

                def handle_login(message)
                  chat_id = message.chat.id
                  parts = message.text.split(" ")

                  if parts.length < 3
                    @bot.api.send_message(chat_id: chat_id, text: "Usage: /login <email> <password>")
                    return
                  end

                  email = parts[1]
                  password = parts[2]
                  result = @auth_service.login(email: email, password: password)

                  if result[:token]
                    @sessions.set_token(chat_id, result[:token])
                    @bot.api.send_message(
                      chat_id: chat_id,
                      text: "Logged in successfully!",
                      reply_markup: Keyboards.main_menu
                    )
                  else
                    @bot.api.send_message(chat_id: chat_id, text: "Login failed: \#{result[:error] || "Invalid credentials"}")
                  end
                end

                def handle_register(message)
                  chat_id = message.chat.id
                  parts = message.text.split(" ")

                  if parts.length < 4
                    @bot.api.send_message(chat_id: chat_id, text: "Usage: /register <name> <email> <password>")
                    return
                  end

                  name = parts[1]
                  email = parts[2]
                  password = parts[3]
                  result = @auth_service.register(name: name, email: email, password: password)

                  if result[:token]
                    @sessions.set_token(chat_id, result[:token])
                    @bot.api.send_message(
                      chat_id: chat_id,
                      text: "Registered successfully!",
                      reply_markup: Keyboards.main_menu
                    )
                  else
                    @bot.api.send_message(chat_id: chat_id, text: "Registration failed: \#{result[:error] || "Error"}")
                  end
                end
              end
            end
          RUBY

          ir.resources.each do |resource|
            name = classify(resource.name)
            plural = resource.name.to_s
            singular = singularize(plural)
            first_field = resource.fields.first&.dig(:name) || "id"

            write_file("lib/handlers/#{singular}_handler.rb", <<~RUBY)
              # frozen_string_literal: true

              module Handlers
                class #{name}Handler
                  def initialize(bot, sessions, #{singular}_service)
                    @bot = bot
                    @sessions = sessions
                    @service = #{singular}_service
                  end

                  def handle_list(chat_id)
                    ensure_auth!(chat_id) or return
                    result = @service.list

                    items = result[:items] || result
                    if items.empty?
                      @bot.api.send_message(chat_id: chat_id, text: "No #{plural} found.")
                      return
                    end

                    text = items.map { |item| "• \#{item[:#{first_field}]} (ID: \#{item[:id]})" }.join("\\n")
                    @bot.api.send_message(chat_id: chat_id, text: "#{name}s:\\n\#{text}")
                  end

                  def handle_new(message)
                    chat_id = message.chat.id
                    ensure_auth!(chat_id) or return

                    parts = message.text.split(" ", 2)
                    if parts.length < 2
                      @bot.api.send_message(chat_id: chat_id, text: "Usage: /new <#{first_field}>")
                      return
                    end

                    result = @service.create({ #{first_field}: parts[1] })
                    if result[:id]
                      @bot.api.send_message(chat_id: chat_id, text: "Created #{singular} #\#{result[:id]}: \#{result[:#{first_field}]}")
                    else
                      @bot.api.send_message(chat_id: chat_id, text: "Failed: \#{result[:error] || "Error"}")
                    end
                  end

                  def handle_delete(chat_id, id)
                    ensure_auth!(chat_id) or return
                    @service.delete(id)
                    @bot.api.send_message(chat_id: chat_id, text: "Deleted #{singular} #\#{id}")
                  end

                  private

                  def ensure_auth!(chat_id)
                    token = @sessions.get_token(chat_id)
                    unless token
                      @bot.api.send_message(chat_id: chat_id, text: "Please /login first.")
                      return false
                    end
                    @service.instance_variable_get(:@client).token = token
                    true
                  end
                end
              end
            RUBY
          end
        end

        def generate_bot_entry
          require_handlers = ir.resources.map { |r|
            singular = singularize(r.name.to_s)
            "require_relative \"lib/handlers/#{singular}_handler\""
          }.join("\n")

          service_inits = ir.resources.map { |r|
            name = classify(r.name)
            singular = singularize(r.name.to_s)
            "#{singular}_service = #{name}Service.new(api_client)"
          }.join("\n")

          handler_inits = ir.resources.map { |r|
            name = classify(r.name)
            singular = singularize(r.name.to_s)
            "  #{singular}_handler = Handlers::#{name}Handler.new(bot, sessions, #{singular}_service)"
          }.join("\n")

          command_cases = []
          ir.resources.each do |r|
            singular = singularize(r.name.to_s)
            plural = r.name.to_s
            command_cases << "      when /\\A\\/#{plural}/\n        #{singular}_handler.handle_list(message.chat.id)"
            command_cases << "      when /\\A\\/new/\n        #{singular}_handler.handle_new(message)"
          end

          callback_cases = ir.resources.flat_map { |r|
            singular = singularize(r.name.to_s)
            [
              "      when /\\Alist_#{r.name}/\n        #{singular}_handler.handle_list(callback.message.chat.id)",
              "      when /\\Adelete_#{singular}_(\\d+)/\n        #{singular}_handler.handle_delete(callback.message.chat.id, $1)"
            ]
          }

          write_file("bot.rb", <<~RUBY)
            # frozen_string_literal: true

            require "telegram/bot"
            require "yaml"
            require "erb"

            require_relative "lib/api/client"
            require_relative "lib/api/auth_service"
            #{ir.resources.map { |r| "require_relative \"lib/api/#{singularize(r.name.to_s)}_service\"" }.join("\n")}
            require_relative "lib/session/store"
            require_relative "lib/keyboards/inline_keyboards"
            require_relative "lib/handlers/start_handler"
            require_relative "lib/handlers/auth_handler"
            #{require_handlers}

            config = YAML.safe_load(ERB.new(File.read("config.yml")).result, permitted_classes: [Symbol])
            token = config["bot_token"] || ENV["BOT_TOKEN"]
            api_url = config["api_url"] || "#{ir.base_url}"

            api_client = APIClient.new(base_url: api_url)
            auth_service = AuthService.new(api_client)
            #{service_inits}
            sessions = SessionStore.new

            Telegram::Bot::Client.run(token) do |bot|
              start_handler = Handlers::StartHandler.new(bot, sessions)
              auth_handler = Handlers::AuthHandler.new(bot, sessions, auth_service)
            #{handler_inits}

              bot.listen do |update|
                case update
                when Telegram::Bot::Types::Message
                  message = update
                  case message.text
                  when "/start"
                    start_handler.handle(message)
                  when /\\A\\/login/
                    auth_handler.handle_login(message)
                  when /\\A\\/register/
                    auth_handler.handle_register(message)
            #{command_cases.join("\n")}
                  end

                when Telegram::Bot::Types::CallbackQuery
                  callback = update
                  case callback.data
            #{callback_cases.join("\n")}
                  end
                end
              end
            end
          RUBY
        end

        def generate_readme
          commands = ["/start — Welcome message", "/login <email> <password> — Login", "/register <name> <email> <password> — Register"]
          ir.resources.each do |r|
            name = classify(r.name)
            commands << "/#{r.name} — List all #{r.name}"
            commands << "/new <#{r.fields.first&.dig(:name) || "value"}> — Create new #{singularize(r.name.to_s)}"
          end

          write_file("README.md", <<~MD)
            # Whoosh Telegram Bot

            A Telegram bot client for your Whoosh API.

            ## Setup

            1. Create a bot via [@BotFather](https://t.me/botfather)
            2. Copy the token to `.env`: `BOT_TOKEN=your-token`
            3. Run: `bundle install && ruby bot.rb`

            ## Commands

            #{commands.map { |c| "- `#{c}`" }.join("\n")}
          MD
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/whoosh/client_gen/generators/telegram_bot_spec.rb -v`
Expected: All 7 examples pass

- [ ] **Step 5: Commit**

```bash
git add lib/whoosh/client_gen/generators/telegram_bot.rb spec/whoosh/client_gen/generators/telegram_bot_spec.rb
git commit -m "feat: add Telegram Bot client generator"
```

---

### Task 5: Mobile & Bot Integration Test

**Files:**
- Create: `spec/whoosh/client_gen/generators/mobile_integration_spec.rb`

- [ ] **Step 1: Write the integration test**

```ruby
# spec/whoosh/client_gen/generators/mobile_integration_spec.rb
# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "whoosh/client_gen/ir"
require "whoosh/client_gen/generators/expo"
require "whoosh/client_gen/generators/ios"
require "whoosh/client_gen/generators/flutter"
require "whoosh/client_gen/generators/telegram_bot"

RSpec.describe "Mobile & Bot Client Generators Integration" do
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
            { name: :status, type: :string, required: false }
          ]
        ),
        Whoosh::ClientGen::IR::Resource.new(
          name: :comments,
          endpoints: [
            Whoosh::ClientGen::IR::Endpoint.new(method: :get, path: "/comments", action: :index),
            Whoosh::ClientGen::IR::Endpoint.new(method: :post, path: "/comments", action: :create)
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

  { expo: :typescript, ios: :swift, flutter: :dart, telegram_bot: :ruby }.each do |client_type, platform|
    describe "#{client_type} with multiple resources" do
      it "generates files for all resources" do
        Dir.mktmpdir do |dir|
          klass = Whoosh::ClientGen::Generators.const_get(
            client_type.to_s.split("_").map(&:capitalize).join
          )
          klass.new(ir: ir, output_dir: dir, platform: platform).generate

          files = Dir.glob("#{dir}/**/*").select { |f| File.file?(f) }
          file_names = files.map { |f| File.basename(f) }.join(" ")

          expect(file_names).to include("task")
          expect(file_names).to include("comment")
        end
      end
    end
  end
end
```

- [ ] **Step 2: Run test to verify it passes**

Run: `bundle exec rspec spec/whoosh/client_gen/generators/mobile_integration_spec.rb -v`
Expected: All 4 examples pass

- [ ] **Step 3: Commit**

```bash
git add spec/whoosh/client_gen/generators/mobile_integration_spec.rb
git commit -m "test: add mobile and bot client generators integration test"
```
