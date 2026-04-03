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
          generate_auth_api if ir.has_auth?
          ir.resources.each do |resource|
            generate_model(resource)
            generate_resource_api(resource)
            generate_resource_hook(resource)
            generate_resource_screens(resource)
          end
          generate_auth_hook if ir.has_auth?
          generate_root_layout
          generate_app_layout
          generate_auth_screens if ir.has_auth?
        end

        private

        # ── Config files ──────────────────────────────────────────────

        def generate_config_files
          write_file("package.json", package_json)
          write_file("app.json", app_json)
          write_file("tsconfig.json", tsconfig_json)
          write_file(".env", dot_env)
          write_file(".gitignore", gitignore)
        end

        def package_json
          pkg = {
            "name" => "app",
            "version" => "1.0.0",
            "main" => "expo-router/entry",
            "scripts" => {
              "start" => "expo start",
              "android" => "expo start --android",
              "ios" => "expo start --ios",
              "web" => "expo start --web"
            },
            "dependencies" => {
              "expo" => "~52.0.0",
              "expo-router" => "~4.0.0",
              "expo-secure-store" => "~14.0.0",
              "expo-status-bar" => "~2.0.0",
              "react" => "19.0.0",
              "react-native" => "0.76.0",
              "@react-native-async-storage/async-storage" => "^2.0.0"
            },
            "devDependencies" => {
              "@babel/core" => "^7.25.0",
              "@types/react" => "~19.0.0",
              "@types/react-native" => "~0.76.0",
              "typescript" => "^5.3.0"
            }
          }
          JSON.pretty_generate(pkg) + "\n"
        end

        def app_json
          config = {
            "expo" => {
              "name" => "App",
              "slug" => "app",
              "version" => "1.0.0",
              "orientation" => "portrait",
              "scheme" => "app",
              "userInterfaceStyle" => "automatic",
              "assetBundlePatterns" => ["**/*"],
              "ios" => { "supportsTablet" => true },
              "android" => { "adaptiveIcon" => { "backgroundColor" => "#ffffff" } },
              "web" => { "bundler" => "metro" },
              "plugins" => ["expo-router", "expo-secure-store"]
            }
          }
          JSON.pretty_generate(config) + "\n"
        end

        def tsconfig_json
          <<~JSON
            {
              "extends": "expo/tsconfig.base",
              "compilerOptions": {
                "strict": true,
                "paths": {
                  "@/*": ["./*"]
                }
              }
            }
          JSON
        end

        def dot_env
          "EXPO_PUBLIC_API_URL=#{ir.base_url}\n"
        end

        def gitignore
          <<~TXT
            node_modules
            .expo
            dist
            .env.local
          TXT
        end

        # ── Auth store (SecureStore) ───────────────────────────────────

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

            export async function setTokens(access: string, refresh?: string): Promise<void> {
              await SecureStore.setItemAsync(ACCESS_TOKEN_KEY, access);
              if (refresh) {
                await SecureStore.setItemAsync(REFRESH_TOKEN_KEY, refresh);
              }
            }

            export async function clearTokens(): Promise<void> {
              await SecureStore.deleteItemAsync(ACCESS_TOKEN_KEY);
              await SecureStore.deleteItemAsync(REFRESH_TOKEN_KEY);
            }
          TS
        end

        # ── API client ────────────────────────────────────────────────

        def generate_api_client
          write_file("src/api/client.ts", <<~TS)
            import { getAccessToken, getRefreshToken, setTokens } from "../store/auth";

            const API_URL = process.env.EXPO_PUBLIC_API_URL || "#{ir.base_url}";

            async function refreshAccessToken(): Promise<boolean> {
              const refresh = await getRefreshToken();
              if (!refresh) return false;
              try {
                const res = await fetch(`${API_URL}/auth/refresh`, {
                  method: "POST",
                  headers: { "Content-Type": "application/json" },
                  body: JSON.stringify({ refresh_token: refresh }),
                });
                if (!res.ok) return false;
                const data = await res.json();
                await setTokens(data.access_token, data.refresh_token);
                return true;
              } catch {
                return false;
              }
            }

            export async function apiRequest<T = any>(
              path: string,
              options: RequestInit = {}
            ): Promise<T> {
              const access = await getAccessToken();
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
                  const newAccess = await getAccessToken();
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
            import { apiRequest } from "./client";
            import { setTokens, clearTokens } from "../store/auth";

            export async function login(email: string, password: string) {
              const data = await apiRequest<{ access_token: string; refresh_token: string }>(
                "/auth/login",
                { method: "POST", body: JSON.stringify({ email, password }) }
              );
              await setTokens(data.access_token, data.refresh_token);
              return data;
            }

            export async function register(email: string, password: string) {
              const data = await apiRequest<{ access_token: string; refresh_token: string }>(
                "/auth/register",
                { method: "POST", body: JSON.stringify({ email, password }) }
              );
              await setTokens(data.access_token, data.refresh_token);
              return data;
            }

            export async function logout() {
              await apiRequest("/auth/logout", { method: "DELETE" });
              await clearTokens();
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
            import { getAccessToken, clearTokens } from "../store/auth";

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
                  await clearTokens();
                  setUser(null);
                } finally {
                  setLoading(false);
                }
              }, []);

              useEffect(() => {
                getAccessToken().then((token) => {
                  if (token) {
                    fetchMe();
                  } else {
                    setLoading(false);
                  }
                });
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

        # ── Root layout ───────────────────────────────────────────────

        def generate_root_layout
          write_file("app/_layout.tsx", <<~TSX)
            import { useEffect } from "react";
            import { Stack, useSegments, useRouter } from "expo-router";
            import { AuthContext, useAuthProvider } from "../src/hooks/useAuth";

            function RootLayoutNav() {
              const { user, loading } = useAuthProvider();
              const segments = useSegments();
              const router = useRouter();

              useEffect(() => {
                if (loading) return;
                const inAuthGroup = segments[0] === "(auth)";
                if (!user && !inAuthGroup) {
                  router.replace("/(auth)/login");
                } else if (user && inAuthGroup) {
                  router.replace("/(app)");
                }
              }, [user, loading, segments]);

              return (
                <Stack screenOptions={{ headerShown: false }}>
                  <Stack.Screen name="(auth)" />
                  <Stack.Screen name="(app)" />
                </Stack>
              );
            }

            export default function RootLayout() {
              const auth = useAuthProvider();
              return (
                <AuthContext.Provider value={auth}>
                  <RootLayoutNav />
                </AuthContext.Provider>
              );
            }
          TSX
        end

        # ── App layout ────────────────────────────────────────────────

        def generate_app_layout
          write_file("app/(app)/_layout.tsx", <<~TSX)
            import { Stack } from "expo-router";

            export default function AppLayout() {
              return (
                <Stack>
                  <Stack.Screen name="index" options={{ title: "Home" }} />
                </Stack>
              );
            }
          TSX
        end

        # ── Auth screens ──────────────────────────────────────────────

        def generate_auth_screens
          generate_login_screen
          generate_register_screen
        end

        def generate_login_screen
          write_file("app/(auth)/login.tsx", <<~TSX)
            import { useState } from "react";
            import {
              View, Text, TextInput, Pressable, Alert, StyleSheet, KeyboardAvoidingView, Platform
            } from "react-native";
            import { useRouter, Link } from "expo-router";
            import { useAuth } from "../../src/hooks/useAuth";

            export default function LoginScreen() {
              const { login } = useAuth();
              const router = useRouter();
              const [email, setEmail] = useState("");
              const [password, setPassword] = useState("");
              const [loading, setLoading] = useState(false);

              const handleLogin = async () => {
                if (!email || !password) {
                  Alert.alert("Error", "Please fill in all fields");
                  return;
                }
                setLoading(true);
                try {
                  await login(email, password);
                  router.replace("/(app)");
                } catch (err: any) {
                  Alert.alert("Login Failed", err.message || "Invalid credentials");
                } finally {
                  setLoading(false);
                }
              };

              return (
                <KeyboardAvoidingView
                  style={styles.container}
                  behavior={Platform.OS === "ios" ? "padding" : "height"}
                >
                  <View style={styles.form}>
                    <Text style={styles.title}>Login</Text>
                    <TextInput
                      style={styles.input}
                      placeholder="Email"
                      value={email}
                      onChangeText={setEmail}
                      autoCapitalize="none"
                      keyboardType="email-address"
                    />
                    <TextInput
                      style={styles.input}
                      placeholder="Password"
                      value={password}
                      onChangeText={setPassword}
                      secureTextEntry
                    />
                    <Pressable style={styles.button} onPress={handleLogin} disabled={loading}>
                      <Text style={styles.buttonText}>{loading ? "Logging in..." : "Login"}</Text>
                    </Pressable>
                    <Link href="/(auth)/register" style={styles.link}>
                      Don't have an account? Register
                    </Link>
                  </View>
                </KeyboardAvoidingView>
              );
            }

            const styles = StyleSheet.create({
              container: { flex: 1, backgroundColor: "#fff" },
              form: { flex: 1, justifyContent: "center", padding: 24, gap: 16 },
              title: { fontSize: 28, fontWeight: "700", marginBottom: 8 },
              input: {
                borderWidth: 1, borderColor: "#ddd", borderRadius: 8,
                padding: 12, fontSize: 16,
              },
              button: {
                backgroundColor: "#0066cc", borderRadius: 8,
                padding: 14, alignItems: "center",
              },
              buttonText: { color: "#fff", fontSize: 16, fontWeight: "600" },
              link: { color: "#0066cc", textAlign: "center", marginTop: 8 },
            });
          TSX
        end

        def generate_register_screen
          write_file("app/(auth)/register.tsx", <<~TSX)
            import { useState } from "react";
            import {
              View, Text, TextInput, Pressable, Alert, StyleSheet, KeyboardAvoidingView, Platform
            } from "react-native";
            import { useRouter, Link } from "expo-router";
            import { useAuth } from "../../src/hooks/useAuth";

            export default function RegisterScreen() {
              const { register } = useAuth();
              const router = useRouter();
              const [email, setEmail] = useState("");
              const [password, setPassword] = useState("");
              const [loading, setLoading] = useState(false);

              const handleRegister = async () => {
                if (!email || !password) {
                  Alert.alert("Error", "Please fill in all fields");
                  return;
                }
                setLoading(true);
                try {
                  await register(email, password);
                  router.replace("/(app)");
                } catch (err: any) {
                  Alert.alert("Registration Failed", err.message || "Could not register");
                } finally {
                  setLoading(false);
                }
              };

              return (
                <KeyboardAvoidingView
                  style={styles.container}
                  behavior={Platform.OS === "ios" ? "padding" : "height"}
                >
                  <View style={styles.form}>
                    <Text style={styles.title}>Register</Text>
                    <TextInput
                      style={styles.input}
                      placeholder="Email"
                      value={email}
                      onChangeText={setEmail}
                      autoCapitalize="none"
                      keyboardType="email-address"
                    />
                    <TextInput
                      style={styles.input}
                      placeholder="Password"
                      value={password}
                      onChangeText={setPassword}
                      secureTextEntry
                    />
                    <Pressable style={styles.button} onPress={handleRegister} disabled={loading}>
                      <Text style={styles.buttonText}>{loading ? "Registering..." : "Register"}</Text>
                    </Pressable>
                    <Link href="/(auth)/login" style={styles.link}>
                      Already have an account? Login
                    </Link>
                  </View>
                </KeyboardAvoidingView>
              );
            }

            const styles = StyleSheet.create({
              container: { flex: 1, backgroundColor: "#fff" },
              form: { flex: 1, justifyContent: "center", padding: 24, gap: 16 },
              title: { fontSize: 28, fontWeight: "700", marginBottom: 8 },
              input: {
                borderWidth: 1, borderColor: "#ddd", borderRadius: 8,
                padding: 12, fontSize: 16,
              },
              button: {
                backgroundColor: "#0066cc", borderRadius: 8,
                padding: 14, alignItems: "center",
              },
              buttonText: { color: "#fff", fontSize: 16, fontWeight: "600" },
              link: { color: "#0066cc", textAlign: "center", marginTop: 8 },
            });
          TSX
        end

        # ── Resource screens ──────────────────────────────────────────

        def generate_resource_screens(resource)
          plural = resource.name.to_s
          singular = singularize(plural)
          name = classify(resource.name)
          fields = resource.fields || []
          has_pagination = resource.endpoints.any? { |e| e.pagination }

          generate_index_screen(name, plural, singular, fields, has_pagination)
          generate_detail_screen(name, plural, singular, fields)
          generate_form_screen(name, plural, singular, fields)
        end

        def generate_index_screen(name, plural, singular, fields, has_pagination)
          display_fields = fields.first(2)
          field_texts = display_fields.map do |f|
            "          <Text style={styles.itemSubtext}>{String(item.#{f[:name]} ?? \"\")}</Text>"
          end.join("\n")

          write_file("app/(app)/#{plural}/index.tsx", <<~TSX)
            import { useEffect, useCallback } from "react";
            import {
              View, Text, FlatList, Pressable, StyleSheet, ActivityIndicator, RefreshControl
            } from "react-native";
            import { useRouter } from "expo-router";
            import { use#{name}s } from "../../../src/hooks/use#{name}s";
            import type { #{name} } from "../../../src/models/#{singular}";

            export default function #{name}ListScreen() {
              const { items, loading, error, fetchAll, remove#{has_pagination ? ', cursor' : ''} } = use#{name}s();
              const router = useRouter();

              useEffect(() => { fetchAll(); }, []);

              const onRefresh = useCallback(() => { fetchAll(); }, [fetchAll]);

              const renderItem = ({ item }: { item: #{name} }) => (
                <Pressable
                  style={styles.item}
                  onPress={() => router.push(`/(app)/#{plural}/${String("${item.id}")}`)}
                >
                  <View style={styles.itemContent}>
                    <Text style={styles.itemTitle}>{item.id}</Text>
            #{field_texts}
                  </View>
                  <Pressable onPress={() => remove(item.id)} style={styles.deleteButton}>
                    <Text style={styles.deleteText}>Delete</Text>
                  </Pressable>
                </Pressable>
              );

              if (loading && items.length === 0) {
                return (
                  <View style={styles.center}>
                    <ActivityIndicator size="large" />
                  </View>
                );
              }

              if (error) {
                return (
                  <View style={styles.center}>
                    <Text style={styles.error}>{error}</Text>
                  </View>
                );
              }

              return (
                <View style={styles.container}>
                  <Pressable style={styles.createButton} onPress={() => router.push("/(app)/#{plural}/form")}>
                    <Text style={styles.createButtonText}>+ New #{name}</Text>
                  </Pressable>
                  <FlatList
                    data={items}
                    keyExtractor={(item) => item.id}
                    renderItem={renderItem}
                    refreshControl={<RefreshControl refreshing={loading} onRefresh={onRefresh} />}
                    #{has_pagination ? 'onEndReached={() => cursor && fetchAll(cursor)}' : ''}
                    #{has_pagination ? 'onEndReachedThreshold={0.5}' : ''}
                    contentContainerStyle={styles.list}
                  />
                </View>
              );
            }

            const styles = StyleSheet.create({
              container: { flex: 1, backgroundColor: "#f5f5f5" },
              center: { flex: 1, justifyContent: "center", alignItems: "center" },
              list: { padding: 16, gap: 8 },
              createButton: {
                margin: 16, backgroundColor: "#0066cc", borderRadius: 8,
                padding: 12, alignItems: "center",
              },
              createButtonText: { color: "#fff", fontWeight: "600", fontSize: 16 },
              item: {
                backgroundColor: "#fff", borderRadius: 8, padding: 16,
                flexDirection: "row", alignItems: "center",
                shadowColor: "#000", shadowOffset: { width: 0, height: 1 },
                shadowOpacity: 0.1, shadowRadius: 2, elevation: 2,
              },
              itemContent: { flex: 1 },
              itemTitle: { fontSize: 16, fontWeight: "600" },
              itemSubtext: { fontSize: 14, color: "#666", marginTop: 2 },
              deleteButton: { padding: 8 },
              deleteText: { color: "#cc0000", fontWeight: "500" },
              error: { color: "#cc0000", fontSize: 16 },
            });
          TSX
        end

        def generate_detail_screen(name, plural, singular, fields)
          field_rows = fields.map do |f|
            <<~TSX.chomp
                    <View style={styles.row}>
                      <Text style={styles.label}>#{camelize(f[:name].to_s)}</Text>
                      <Text style={styles.value}>{String(item.#{f[:name]} ?? "—")}</Text>
                    </View>
            TSX
          end.join("\n")

          write_file("app/(app)/#{plural}/[id].tsx", <<~TSX)
            import { useEffect, useState } from "react";
            import {
              View, Text, Pressable, StyleSheet, ActivityIndicator, Alert, ScrollView
            } from "react-native";
            import { useLocalSearchParams, useRouter } from "expo-router";
            import { get#{name}, delete#{name} } from "../../../src/api/#{plural}";
            import type { #{name} } from "../../../src/models/#{singular}";

            export default function #{name}DetailScreen() {
              const { id } = useLocalSearchParams<{ id: string }>();
              const router = useRouter();
              const [item, setItem] = useState<#{name} | null>(null);
              const [loading, setLoading] = useState(true);

              useEffect(() => {
                if (id) {
                  get#{name}(id)
                    .then(setItem)
                    .finally(() => setLoading(false));
                }
              }, [id]);

              const handleDelete = () => {
                Alert.alert("Confirm Delete", "Are you sure you want to delete this item?", [
                  { text: "Cancel", style: "cancel" },
                  {
                    text: "Delete", style: "destructive",
                    onPress: async () => {
                      if (id) {
                        await delete#{name}(id);
                        router.back();
                      }
                    },
                  },
                ]);
              };

              if (loading) {
                return (
                  <View style={styles.center}>
                    <ActivityIndicator size="large" />
                  </View>
                );
              }

              if (!item) {
                return (
                  <View style={styles.center}>
                    <Text>Item not found</Text>
                  </View>
                );
              }

              return (
                <ScrollView style={styles.container} contentContainerStyle={styles.content}>
            #{field_rows}
                  <View style={styles.actions}>
                    <Pressable
                      style={styles.editButton}
                      onPress={() => router.push(`/(app)/#{plural}/form?id=${String("${item.id}")}`)}
                    >
                      <Text style={styles.editButtonText}>Edit</Text>
                    </Pressable>
                    <Pressable style={styles.deleteButton} onPress={handleDelete}>
                      <Text style={styles.deleteButtonText}>Delete</Text>
                    </Pressable>
                  </View>
                </ScrollView>
              );
            }

            const styles = StyleSheet.create({
              container: { flex: 1, backgroundColor: "#fff" },
              center: { flex: 1, justifyContent: "center", alignItems: "center" },
              content: { padding: 24, gap: 16 },
              row: { borderBottomWidth: 1, borderBottomColor: "#eee", paddingBottom: 12 },
              label: { fontSize: 12, color: "#666", fontWeight: "500", textTransform: "uppercase" },
              value: { fontSize: 16, marginTop: 4 },
              actions: { flexDirection: "row", gap: 12, marginTop: 16 },
              editButton: {
                flex: 1, backgroundColor: "#0066cc", borderRadius: 8,
                padding: 14, alignItems: "center",
              },
              editButtonText: { color: "#fff", fontWeight: "600" },
              deleteButton: {
                flex: 1, backgroundColor: "#cc0000", borderRadius: 8,
                padding: 14, alignItems: "center",
              },
              deleteButtonText: { color: "#fff", fontWeight: "600" },
            });
          TSX
        end

        def generate_form_screen(name, plural, singular, fields)
          state_lines = fields.map do |f|
            default_val = f[:default] ? "\"#{f[:default]}\"" : "\"\""
            "  const [#{f[:name]}, set#{camelize(f[:name].to_s)}] = useState(#{default_val});"
          end.join("\n")

          load_lines = fields.map do |f|
            "    set#{camelize(f[:name].to_s)}(String(data.#{f[:name]} ?? \"\"));"
          end.join("\n")

          input_fields = fields.map do |f|
            fname = f[:name].to_s
            setter = "set#{camelize(fname)}"
            if f[:enum]
              options = f[:enum].map do |v|
                "        <Pressable\n          key=\"#{v}\"\n          style={[styles.option, #{fname} === \"#{v}\" && styles.optionSelected]}\n          onPress={() => #{setter}(\"#{v}\")}\n        >\n          <Text style={#{fname} === \"#{v}\" ? styles.optionTextSelected : styles.optionText}>#{v}</Text>\n        </Pressable>"
              end.join("\n")
              <<~FIELD.chomp
                <View style={styles.field}>
                    <Text style={styles.label}>#{camelize(fname)}</Text>
                    <View style={styles.options}>
                #{options}
                    </View>
                  </View>
              FIELD
            else
              <<~FIELD.chomp
                <View style={styles.field}>
                    <Text style={styles.label}>#{camelize(fname)}</Text>
                    <TextInput
                      style={styles.input}
                      value={#{fname}}
                      onChangeText={#{setter}}
                      placeholder="Enter #{fname}"
                    />
                  </View>
              FIELD
            end
          end.join("\n          ")

          body_fields = fields.map { |f| "#{f[:name]}" }.join(", ")

          write_file("app/(app)/#{plural}/form.tsx", <<~TSX)
            import { useState, useEffect } from "react";
            import {
              View, Text, TextInput, Pressable, StyleSheet, Alert, ScrollView, ActivityIndicator
            } from "react-native";
            import { useLocalSearchParams, useRouter } from "expo-router";
            import { get#{name}, create#{name}, update#{name} } from "../../../src/api/#{plural}";

            export default function #{name}FormScreen() {
              const { id } = useLocalSearchParams<{ id?: string }>();
              const router = useRouter();
              const isEdit = Boolean(id);
              const [loading, setLoading] = useState(false);
            #{state_lines}

              useEffect(() => {
                if (id) {
                  get#{name}(id).then((data) => {
            #{load_lines}
                  });
                }
              }, [id]);

              const handleSubmit = async () => {
                setLoading(true);
                try {
                  const body = { #{body_fields} };
                  if (isEdit && id) {
                    await update#{name}(id, body);
                  } else {
                    await create#{name}(body);
                  }
                  router.back();
                } catch (err: any) {
                  Alert.alert("Error", err.message || "Save failed");
                } finally {
                  setLoading(false);
                }
              };

              return (
                <ScrollView style={styles.container} contentContainerStyle={styles.content}>
                  <Text style={styles.title}>{isEdit ? "Edit" : "New"} #{name}</Text>
                  #{input_fields}
                  <Pressable style={styles.button} onPress={handleSubmit} disabled={loading}>
                    {loading ? (
                      <ActivityIndicator color="#fff" />
                    ) : (
                      <Text style={styles.buttonText}>{isEdit ? "Update" : "Create"}</Text>
                    )}
                  </Pressable>
                </ScrollView>
              );
            }

            const styles = StyleSheet.create({
              container: { flex: 1, backgroundColor: "#fff" },
              content: { padding: 24, gap: 16 },
              title: { fontSize: 24, fontWeight: "700", marginBottom: 8 },
              field: { gap: 6 },
              label: { fontSize: 14, fontWeight: "500", color: "#333" },
              input: {
                borderWidth: 1, borderColor: "#ddd", borderRadius: 8,
                padding: 12, fontSize: 16,
              },
              options: { flexDirection: "row", flexWrap: "wrap", gap: 8 },
              option: {
                borderWidth: 1, borderColor: "#ddd", borderRadius: 6,
                paddingHorizontal: 12, paddingVertical: 8,
              },
              optionSelected: { backgroundColor: "#0066cc", borderColor: "#0066cc" },
              optionText: { color: "#333" },
              optionTextSelected: { color: "#fff" },
              button: {
                backgroundColor: "#0066cc", borderRadius: 8,
                padding: 14, alignItems: "center", marginTop: 8,
              },
              buttonText: { color: "#fff", fontSize: 16, fontWeight: "600" },
            });
          TSX
        end
      end
    end
  end
end
