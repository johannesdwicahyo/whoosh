# frozen_string_literal: true

require "whoosh/client_gen/base_generator"

module Whoosh
  module ClientGen
    module Generators
      class Flutter < BaseGenerator
        def generate
          generate_pubspec
          generate_main
          generate_api_client
          generate_router

          if ir.has_auth?
            generate_auth_service
            generate_auth_provider
            generate_auth_screens
          end

          ir.resources.each do |resource|
            generate_model(resource)
            generate_resource_service(resource)
            generate_resource_provider(resource)
            generate_resource_screens(resource)
          end
        end

        private

        # ── pubspec.yaml ──────────────────────────────────────────────

        def generate_pubspec
          write_file("pubspec.yaml", <<~YAML)
            name: whoosh_app
            description: Generated Flutter app by Whoosh
            version: 1.0.0+1

            environment:
              sdk: ">=3.0.0 <4.0.0"
              flutter: ">=3.10.0"

            dependencies:
              flutter:
                sdk: flutter
              dio: ^5.4.0
              flutter_riverpod: ^2.5.1
              go_router: ^13.2.0
              flutter_secure_storage: ^9.0.0

            dev_dependencies:
              flutter_test:
                sdk: flutter
              flutter_lints: ^3.0.0

            flutter:
              uses-material-design: true
          YAML
        end

        # ── main.dart ─────────────────────────────────────────────────

        def generate_main
          first_resource = ir.resources.first
          home_route = first_resource ? "/#{first_resource.name}" : "/"

          write_file("lib/main.dart", <<~DART)
            import 'package:flutter/material.dart';
            import 'package:flutter_riverpod/flutter_riverpod.dart';
            import 'router.dart';

            void main() {
              runApp(const ProviderScope(child: WhooshApp()));
            }

            class WhooshApp extends ConsumerWidget {
              const WhooshApp({super.key});

              @override
              Widget build(BuildContext context, WidgetRef ref) {
                final router = ref.watch(routerProvider);
                return MaterialApp.router(
                  title: 'Whoosh App',
                  theme: ThemeData(
                    colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
                    useMaterial3: true,
                  ),
                  routerConfig: router,
                );
              }
            }
          DART
        end

        # ── API Client ────────────────────────────────────────────────

        def generate_api_client
          write_file("lib/api/client.dart", <<~DART)
            import 'package:dio/dio.dart';
            import 'package:flutter_secure_storage/flutter_secure_storage.dart';

            const String _baseUrl = '#{ir.base_url}';
            const _storage = FlutterSecureStorage();

            Dio createDioClient() {
              final dio = Dio(BaseOptions(baseUrl: _baseUrl));
              dio.interceptors.add(AuthInterceptor(dio));
              return dio;
            }

            final dio = createDioClient();

            class AuthInterceptor extends Interceptor {
              final Dio _dio;

              AuthInterceptor(this._dio);

              @override
              Future<void> onRequest(
                RequestOptions options,
                RequestInterceptorHandler handler,
              ) async {
                final token = await _storage.read(key: 'auth_token');
                if (token != null) {
                  options.headers['Authorization'] = 'Bearer $token';
                }
                handler.next(options);
              }

              @override
              void onError(DioException err, ErrorInterceptorHandler handler) {
                handler.next(err);
              }
            }
          DART
        end

        # ── Auth Service ──────────────────────────────────────────────

        def generate_auth_service
          write_file("lib/api/auth_service.dart", <<~DART)
            import 'package:flutter_secure_storage/flutter_secure_storage.dart';
            import 'client.dart';

            const _storage = FlutterSecureStorage();

            class AuthService {
              static Future<Map<String, dynamic>> login(String email, String password) async {
                final response = await dio.post('/auth/login', data: {
                  'email': email,
                  'password': password,
                });
                final token = response.data['token'] as String?;
                if (token != null) {
                  await _storage.write(key: 'auth_token', value: token);
                }
                return Map<String, dynamic>.from(response.data);
              }

              static Future<Map<String, dynamic>> register(String email, String password) async {
                final response = await dio.post('/auth/register', data: {
                  'email': email,
                  'password': password,
                });
                final token = response.data['token'] as String?;
                if (token != null) {
                  await _storage.write(key: 'auth_token', value: token);
                }
                return Map<String, dynamic>.from(response.data);
              }

              static Future<void> logout() async {
                await dio.delete('/auth/logout');
                await _storage.delete(key: 'auth_token');
              }

              static Future<bool> isLoggedIn() async {
                final token = await _storage.read(key: 'auth_token');
                return token != null;
              }
            }
          DART
        end

        # ── Auth Provider ─────────────────────────────────────────────

        def generate_auth_provider
          write_file("lib/providers/auth_provider.dart", <<~DART)
            import 'package:flutter_riverpod/flutter_riverpod.dart';
            import '../api/auth_service.dart';

            class AuthState {
              final bool isAuthenticated;
              final bool isLoading;
              final String? error;

              const AuthState({
                this.isAuthenticated = false,
                this.isLoading = false,
                this.error,
              });

              AuthState copyWith({
                bool? isAuthenticated,
                bool? isLoading,
                String? error,
              }) {
                return AuthState(
                  isAuthenticated: isAuthenticated ?? this.isAuthenticated,
                  isLoading: isLoading ?? this.isLoading,
                  error: error,
                );
              }
            }

            class AuthNotifier extends StateNotifier<AuthState> {
              AuthNotifier() : super(const AuthState()) {
                _checkAuth();
              }

              Future<void> _checkAuth() async {
                final loggedIn = await AuthService.isLoggedIn();
                state = state.copyWith(isAuthenticated: loggedIn);
              }

              Future<void> login(String email, String password) async {
                state = state.copyWith(isLoading: true);
                try {
                  await AuthService.login(email, password);
                  state = state.copyWith(isAuthenticated: true, isLoading: false);
                } catch (e) {
                  state = state.copyWith(isLoading: false, error: e.toString());
                }
              }

              Future<void> register(String email, String password) async {
                state = state.copyWith(isLoading: true);
                try {
                  await AuthService.register(email, password);
                  state = state.copyWith(isAuthenticated: true, isLoading: false);
                } catch (e) {
                  state = state.copyWith(isLoading: false, error: e.toString());
                }
              }

              Future<void> logout() async {
                await AuthService.logout();
                state = state.copyWith(isAuthenticated: false);
              }
            }

            final authProvider = StateNotifierProvider<AuthNotifier, AuthState>(
              (ref) => AuthNotifier(),
            );
          DART
        end

        # ── Auth Screens ──────────────────────────────────────────────

        def generate_auth_screens
          generate_login_screen
          generate_register_screen
        end

        def generate_login_screen
          write_file("lib/screens/auth/login_screen.dart", <<~DART)
            import 'package:flutter/material.dart';
            import 'package:flutter_riverpod/flutter_riverpod.dart';
            import 'package:go_router/go_router.dart';
            import '../../providers/auth_provider.dart';

            class LoginScreen extends ConsumerStatefulWidget {
              const LoginScreen({super.key});

              @override
              ConsumerState<LoginScreen> createState() => _LoginScreenState();
            }

            class _LoginScreenState extends ConsumerState<LoginScreen> {
              final _formKey = GlobalKey<FormState>();
              final _emailController = TextEditingController();
              final _passwordController = TextEditingController();

              @override
              void dispose() {
                _emailController.dispose();
                _passwordController.dispose();
                super.dispose();
              }

              Future<void> _submit() async {
                if (!_formKey.currentState!.validate()) return;
                await ref.read(authProvider.notifier).login(
                  _emailController.text,
                  _passwordController.text,
                );
              }

              @override
              Widget build(BuildContext context) {
                final auth = ref.watch(authProvider);
                return Scaffold(
                  appBar: AppBar(title: const Text('Login')),
                  body: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _emailController,
                            decoration: const InputDecoration(labelText: 'Email'),
                            keyboardType: TextInputType.emailAddress,
                            validator: (v) => v!.isEmpty ? 'Required' : null,
                          ),
                          TextFormField(
                            controller: _passwordController,
                            decoration: const InputDecoration(labelText: 'Password'),
                            obscureText: true,
                            validator: (v) => v!.isEmpty ? 'Required' : null,
                          ),
                          if (auth.error != null)
                            Text(auth.error!, style: const TextStyle(color: Colors.red)),
                          const SizedBox(height: 16),
                          auth.isLoading
                              ? const CircularProgressIndicator()
                              : ElevatedButton(
                                  onPressed: _submit,
                                  child: const Text('Login'),
                                ),
                          TextButton(
                            onPressed: () => context.go('/register'),
                            child: const Text("Don't have an account? Register"),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }
            }
          DART
        end

        def generate_register_screen
          write_file("lib/screens/auth/register_screen.dart", <<~DART)
            import 'package:flutter/material.dart';
            import 'package:flutter_riverpod/flutter_riverpod.dart';
            import 'package:go_router/go_router.dart';
            import '../../providers/auth_provider.dart';

            class RegisterScreen extends ConsumerStatefulWidget {
              const RegisterScreen({super.key});

              @override
              ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
            }

            class _RegisterScreenState extends ConsumerState<RegisterScreen> {
              final _formKey = GlobalKey<FormState>();
              final _emailController = TextEditingController();
              final _passwordController = TextEditingController();

              @override
              void dispose() {
                _emailController.dispose();
                _passwordController.dispose();
                super.dispose();
              }

              Future<void> _submit() async {
                if (!_formKey.currentState!.validate()) return;
                await ref.read(authProvider.notifier).register(
                  _emailController.text,
                  _passwordController.text,
                );
              }

              @override
              Widget build(BuildContext context) {
                final auth = ref.watch(authProvider);
                return Scaffold(
                  appBar: AppBar(title: const Text('Register')),
                  body: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _emailController,
                            decoration: const InputDecoration(labelText: 'Email'),
                            keyboardType: TextInputType.emailAddress,
                            validator: (v) => v!.isEmpty ? 'Required' : null,
                          ),
                          TextFormField(
                            controller: _passwordController,
                            decoration: const InputDecoration(labelText: 'Password'),
                            obscureText: true,
                            validator: (v) => v!.isEmpty ? 'Required' : null,
                          ),
                          if (auth.error != null)
                            Text(auth.error!, style: const TextStyle(color: Colors.red)),
                          const SizedBox(height: 16),
                          auth.isLoading
                              ? const CircularProgressIndicator()
                              : ElevatedButton(
                                  onPressed: _submit,
                                  child: const Text('Register'),
                                ),
                          TextButton(
                            onPressed: () => context.go('/login'),
                            child: const Text('Already have an account? Login'),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }
            }
          DART
        end

        # ── Models ────────────────────────────────────────────────────

        def generate_model(resource)
          name = classify(resource.name)
          singular = singularize(resource.name.to_s)
          fields = resource.fields || []

          field_declarations = fields.map do |f|
            fname = f[:name].to_s
            ftype = type_for(f[:type])
            ftype = "#{ftype}?" unless f[:required]
            "  final #{ftype} #{fname};"
          end.join("\n")

          constructor_params = fields.map do |f|
            fname = f[:name].to_s
            if f[:required]
              "    required this.#{fname},"
            else
              "    this.#{fname},"
            end
          end.join("\n")

          from_json_fields = fields.map do |f|
            fname = f[:name].to_s
            ftype = type_for(f[:type])
            if f[:required]
              "      #{fname}: json['#{fname}'] as #{ftype},"
            else
              "      #{fname}: json['#{fname}'] as #{ftype}?,"
            end
          end.join("\n")

          to_json_fields = fields.map do |f|
            fname = f[:name].to_s
            "      '#{fname}': #{fname},"
          end.join("\n")

          write_file("lib/models/#{singular}.dart", <<~DART)
            class #{name} {
              final int? id;
            #{field_declarations}

              const #{name}({
                this.id,
            #{constructor_params}
              });

              factory #{name}.fromJson(Map<String, dynamic> json) {
                return #{name}(
                  id: json['id'] as int?,
            #{from_json_fields}
                );
              }

              Map<String, dynamic> toJson() {
                return {
                  if (id != null) 'id': id,
            #{to_json_fields}
                };
              }
            }
          DART
        end

        # ── Resource Service ──────────────────────────────────────────

        def generate_resource_service(resource)
          name = classify(resource.name)
          plural = resource.name.to_s
          singular = singularize(plural)

          write_file("lib/api/#{singular}_service.dart", <<~DART)
            import '../models/#{singular}.dart';
            import 'client.dart';

            class #{name}Service {
              static Future<List<#{name}>> list() async {
                final response = await dio.get('/#{plural}');
                return (response.data as List)
                    .map((e) => #{name}.fromJson(Map<String, dynamic>.from(e)))
                    .toList();
              }

              static Future<#{name}> get(int id) async {
                final response = await dio.get('/#{plural}/$id');
                return #{name}.fromJson(Map<String, dynamic>.from(response.data));
              }

              static Future<#{name}> create(#{name} item) async {
                final response = await dio.post('/#{plural}', data: item.toJson());
                return #{name}.fromJson(Map<String, dynamic>.from(response.data));
              }

              static Future<#{name}> update(int id, #{name} item) async {
                final response = await dio.put('/#{plural}/$id', data: item.toJson());
                return #{name}.fromJson(Map<String, dynamic>.from(response.data));
              }

              static Future<void> delete(int id) async {
                await dio.delete('/#{plural}/$id');
              }
            }
          DART
        end

        # ── Resource Provider ─────────────────────────────────────────

        def generate_resource_provider(resource)
          name = classify(resource.name)
          plural = resource.name.to_s
          singular = singularize(plural)

          write_file("lib/providers/#{singular}_provider.dart", <<~DART)
            import 'package:flutter_riverpod/flutter_riverpod.dart';
            import '../models/#{singular}.dart';
            import '../api/#{singular}_service.dart';

            class #{name}Notifier extends StateNotifier<AsyncValue<List<#{name}>>> {
              #{name}Notifier() : super(const AsyncValue.loading()) {
                fetchAll();
              }

              Future<void> fetchAll() async {
                state = const AsyncValue.loading();
                state = await AsyncValue.guard(() => #{name}Service.list());
              }

              Future<void> create(#{name} item) async {
                final created = await #{name}Service.create(item);
                state.whenData((items) {
                  state = AsyncValue.data([...items, created]);
                });
              }

              Future<void> update(int id, #{name} item) async {
                final updated = await #{name}Service.update(id, item);
                state.whenData((items) {
                  state = AsyncValue.data(
                    items.map((i) => i.id == id ? updated : i).toList(),
                  );
                });
              }

              Future<void> delete(int id) async {
                await #{name}Service.delete(id);
                state.whenData((items) {
                  state = AsyncValue.data(items.where((i) => i.id != id).toList());
                });
              }
            }

            final #{singular}Provider = StateNotifierProvider<#{name}Notifier, AsyncValue<List<#{name}>>>(
              (ref) => #{name}Notifier(),
            );
          DART
        end

        # ── Resource Screens ──────────────────────────────────────────

        def generate_resource_screens(resource)
          name = classify(resource.name)
          plural = resource.name.to_s
          singular = singularize(plural)
          fields = resource.fields || []

          generate_list_screen(resource, name, plural, singular, fields)
          generate_detail_screen(resource, name, plural, singular, fields)
          generate_form_screen(resource, name, plural, singular, fields)
        end

        def generate_list_screen(resource, name, plural, singular, fields)
          display_field = fields.find { |f| f[:required] } || fields.first
          display_expr = display_field ? "item.#{display_field[:name]}.toString()" : "item.id.toString()"

          write_file("lib/screens/#{plural}/#{singular}_list_screen.dart", <<~DART)
            import 'package:flutter/material.dart';
            import 'package:flutter_riverpod/flutter_riverpod.dart';
            import 'package:go_router/go_router.dart';
            import '../../providers/#{singular}_provider.dart';

            class #{name}ListScreen extends ConsumerWidget {
              const #{name}ListScreen({super.key});

              @override
              Widget build(BuildContext context, WidgetRef ref) {
                final state = ref.watch(#{singular}Provider);
                return Scaffold(
                  appBar: AppBar(
                    title: const Text('#{name}s'),
                    actions: [
                      IconButton(
                        icon: const Icon(Icons.add),
                        onPressed: () => context.go('/#{plural}/new'),
                      ),
                    ],
                  ),
                  body: state.when(
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Center(child: Text('Error: $e')),
                    data: (items) => RefreshIndicator(
                      onRefresh: () => ref.read(#{singular}Provider.notifier).fetchAll(),
                      child: ListView.builder(
                        itemCount: items.length,
                        itemBuilder: (context, index) {
                          final item = items[index];
                          return ListTile(
                            title: Text(#{display_expr}),
                            onTap: () => context.go('/#{plural}/${item.id}'),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete),
                              onPressed: () => ref
                                  .read(#{singular}Provider.notifier)
                                  .delete(item.id!),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                );
              }
            }
          DART
        end

        def generate_detail_screen(resource, name, plural, singular, fields)
          field_rows = fields.map do |f|
            fname = f[:name].to_s
            label = fname.capitalize
            "            ListTile(title: Text('#{label}'), subtitle: Text(item.#{fname}?.toString() ?? '')),"
          end.join("\n")

          write_file("lib/screens/#{plural}/#{singular}_detail_screen.dart", <<~DART)
            import 'package:flutter/material.dart';
            import 'package:flutter_riverpod/flutter_riverpod.dart';
            import 'package:go_router/go_router.dart';
            import '../../providers/#{singular}_provider.dart';

            class #{name}DetailScreen extends ConsumerWidget {
              final int id;

              const #{name}DetailScreen({super.key, required this.id});

              @override
              Widget build(BuildContext context, WidgetRef ref) {
                final state = ref.watch(#{singular}Provider);
                return Scaffold(
                  appBar: AppBar(
                    title: const Text('#{name} Detail'),
                    actions: [
                      IconButton(
                        icon: const Icon(Icons.edit),
                        onPressed: () => context.go('/#{plural}/$id/edit'),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete),
                        onPressed: () async {
                          await ref.read(#{singular}Provider.notifier).delete(id);
                          if (context.mounted) context.go('/#{plural}');
                        },
                      ),
                    ],
                  ),
                  body: state.when(
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Center(child: Text('Error: $e')),
                    data: (items) {
                      final item = items.where((i) => i.id == id).firstOrNull;
                      if (item == null) return const Center(child: Text('Not found'));
                      return ListView(
                        children: [
            #{field_rows}
                        ],
                      );
                    },
                  ),
                );
              }
            }
          DART
        end

        def generate_form_screen(resource, name, plural, singular, fields)
          controller_decls = fields.map do |f|
            fname = f[:name].to_s
            "  final _#{fname}Controller = TextEditingController();"
          end.join("\n")

          dispose_calls = fields.map do |f|
            "    _#{f[:name]}Controller.dispose();"
          end.join("\n")

          form_fields = fields.map do |f|
            fname = f[:name].to_s
            label = fname.capitalize
            <<~DART.strip
              TextFormField(
                                controller: _#{fname}Controller,
                                decoration: const InputDecoration(labelText: '#{label}'),
                                validator: (v) => #{f[:required] ? "v!.isEmpty ? 'Required' : null" : "null"},
                              ),
            DART
          end.join("\n              ")

          build_item = fields.map do |f|
            fname = f[:name].to_s
            ftype = type_for(f[:type])
            if ftype == "int"
              "          #{fname}: int.tryParse(_#{fname}Controller.text),"
            elsif ftype == "double"
              "          #{fname}: double.tryParse(_#{fname}Controller.text),"
            elsif ftype == "bool"
              "          #{fname}: _#{fname}Controller.text.toLowerCase() == 'true',"
            else
              if f[:required]
                "          #{fname}: _#{fname}Controller.text,"
              else
                "          #{fname}: _#{fname}Controller.text.isEmpty ? null : _#{fname}Controller.text,"
              end
            end
          end.join("\n")

          write_file("lib/screens/#{plural}/#{singular}_form_screen.dart", <<~DART)
            import 'package:flutter/material.dart';
            import 'package:flutter_riverpod/flutter_riverpod.dart';
            import 'package:go_router/go_router.dart';
            import '../../models/#{singular}.dart';
            import '../../providers/#{singular}_provider.dart';

            class #{name}FormScreen extends ConsumerStatefulWidget {
              final int? existingId;

              const #{name}FormScreen({super.key, this.existingId});

              @override
              ConsumerState<#{name}FormScreen> createState() => _#{name}FormScreenState();
            }

            class _#{name}FormScreenState extends ConsumerState<#{name}FormScreen> {
              final _formKey = GlobalKey<FormState>();
            #{controller_decls}

              @override
              void dispose() {
            #{dispose_calls}
                super.dispose();
              }

              Future<void> _submit() async {
                if (!_formKey.currentState!.validate()) return;
                final item = #{name}(
            #{build_item}
                );
                final notifier = ref.read(#{singular}Provider.notifier);
                if (widget.existingId != null) {
                  await notifier.update(widget.existingId!, item);
                } else {
                  await notifier.create(item);
                }
                if (mounted) context.go('/#{plural}');
              }

              @override
              Widget build(BuildContext context) {
                return Scaffold(
                  appBar: AppBar(
                    title: Text(widget.existingId == null ? 'New #{name}' : 'Edit #{name}'),
                  ),
                  body: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          #{form_fields}
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: _submit,
                            child: Text(widget.existingId == null ? 'Create' : 'Update'),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }
            }
          DART
        end

        # ── GoRouter ──────────────────────────────────────────────────

        def generate_router
          resource_imports = ir.resources.map do |r|
            name = classify(r.name)
            plural = r.name.to_s
            singular = singularize(plural)
            [
              "import 'screens/#{plural}/#{singular}_list_screen.dart';",
              "import 'screens/#{plural}/#{singular}_detail_screen.dart';",
              "import 'screens/#{plural}/#{singular}_form_screen.dart';"
            ].join("\n")
          end.join("\n")

          auth_imports = if ir.has_auth?
            "import 'screens/auth/login_screen.dart';\nimport 'screens/auth/register_screen.dart';\nimport 'providers/auth_provider.dart';"
          else
            ""
          end

          resource_routes = ir.resources.map do |r|
            name = classify(r.name)
            plural = r.name.to_s
            singular = singularize(plural)
            <<~DART.chomp
                  GoRoute(
                    path: '/#{plural}',
                    builder: (context, state) => const #{name}ListScreen(),
                  ),
                  GoRoute(
                    path: '/#{plural}/new',
                    builder: (context, state) => const #{name}FormScreen(),
                  ),
                  GoRoute(
                    path: '/#{plural}/:id',
                    builder: (context, state) {
                      final id = int.parse(state.pathParameters['id']!);
                      return #{name}DetailScreen(id: id);
                    },
                  ),
                  GoRoute(
                    path: '/#{plural}/:id/edit',
                    builder: (context, state) {
                      final id = int.parse(state.pathParameters['id']!);
                      return #{name}FormScreen(existingId: id);
                    },
                  ),
            DART
          end.join("\n")

          auth_routes = if ir.has_auth?
            <<~DART.chomp
                  GoRoute(
                    path: '/login',
                    builder: (context, state) => const LoginScreen(),
                  ),
                  GoRoute(
                    path: '/register',
                    builder: (context, state) => const RegisterScreen(),
                  ),
            DART
          else
            ""
          end

          redirect_logic = if ir.has_auth?
            <<~DART.chomp
                  redirect: (context, state) {
                    // auth redirect handled by authProvider
                    return null;
                  },
            DART
          else
            ""
          end

          first_path = ir.resources.first ? "/#{ir.resources.first.name}" : "/"

          write_file("lib/router.dart", <<~DART)
            import 'package:flutter_riverpod/flutter_riverpod.dart';
            import 'package:go_router/go_router.dart';
            #{auth_imports}
            #{resource_imports}

            final routerProvider = Provider<GoRouter>((ref) {
              return GoRouter(
                initialLocation: '#{first_path}',
            #{redirect_logic}
                routes: [
            #{auth_routes}
            #{resource_routes}
                ],
              );
            });
          DART
        end
      end
    end
  end
end
