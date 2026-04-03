# frozen_string_literal: true

require "whoosh/client_gen/base_generator"

module Whoosh
  module ClientGen
    module Generators
      class Ios < BaseGenerator
        APP = "WhooshApp"

        def generate
          generate_app_swift
          generate_api_client
          generate_keychain_helper
          generate_xcode_project

          if ir.has_auth?
            generate_auth_service
            generate_auth_view_model
            generate_auth_views
          end

          ir.resources.each do |resource|
            generate_model(resource)
            generate_resource_service(resource)
            generate_resource_view_model(resource)
            generate_resource_views(resource)
          end
        end

        private

        # ── App.swift ─────────────────────────────────────────────────

        def generate_app_swift
          write_file("#{APP}/App.swift", <<~SWIFT)
            import SwiftUI

            @main
            struct WhooshApp: App {
                @StateObject private var authViewModel = AuthViewModel()

                var body: some Scene {
                    WindowGroup {
                        NavigationStack {
                            if authViewModel.isAuthenticated {
                                ContentView()
                            } else {
                                LoginView()
                            }
                        }
                        .environmentObject(authViewModel)
                    }
                }
            }

            struct ContentView: View {
                var body: some View {
                    #{content_view_body}
                }
            }
          SWIFT
        end

        def content_view_body
          if ir.resources.empty?
            "Text(\"Welcome to WhooshApp\")"
          else
            res = ir.resources.first
            name = classify(res.name)
            "#{name}ListView()"
          end
        end

        # ── API Client ────────────────────────────────────────────────

        def generate_api_client
          write_file("#{APP}/API/APIClient.swift", <<~SWIFT)
            import Foundation

            actor APIClient {
                static let shared = APIClient()

                let baseURL: String = "#{ir.base_url}"

                func request<T: Decodable>(
                    method: String,
                    path: String,
                    body: Encodable? = nil
                ) async throws -> T {
                    guard let url = URL(string: baseURL + path) else {
                        throw URLError(.badURL)
                    }

                    var request = URLRequest(url: url)
                    request.httpMethod = method
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

                    if let token = KeychainHelper.shared.read(key: "auth_token") {
                        request.setValue("Bearer \\(token)", forHTTPHeaderField: "Authorization")
                    }

                    if let body = body {
                        request.httpBody = try JSONEncoder().encode(body)
                    }

                    let (data, response) = try await URLSession.shared.data(for: request)

                    guard let httpResponse = response as? HTTPURLResponse,
                          (200...299).contains(httpResponse.statusCode) else {
                        throw URLError(.badServerResponse)
                    }

                    let decoder = JSONDecoder()
                    decoder.keyDecodingStrategy = .convertFromSnakeCase
                    return try decoder.decode(T.self, from: data)
                }

                func requestVoid(
                    method: String,
                    path: String,
                    body: Encodable? = nil
                ) async throws {
                    guard let url = URL(string: baseURL + path) else {
                        throw URLError(.badURL)
                    }

                    var request = URLRequest(url: url)
                    request.httpMethod = method
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

                    if let token = KeychainHelper.shared.read(key: "auth_token") {
                        request.setValue("Bearer \\(token)", forHTTPHeaderField: "Authorization")
                    }

                    if let body = body {
                        request.httpBody = try JSONEncoder().encode(body)
                    }

                    let (_, response) = try await URLSession.shared.data(for: request)

                    guard let httpResponse = response as? HTTPURLResponse,
                          (200...299).contains(httpResponse.statusCode) else {
                        throw URLError(.badServerResponse)
                    }
                }
            }
          SWIFT
        end

        # ── Keychain Helper ───────────────────────────────────────────

        def generate_keychain_helper
          write_file("#{APP}/Keychain/KeychainHelper.swift", <<~SWIFT)
            import Foundation
            import Security

            final class KeychainHelper {
                static let shared = KeychainHelper()
                private init() {}

                func save(key: String, value: String) {
                    guard let data = value.data(using: .utf8) else { return }
                    delete(key: key)

                    let query: [String: Any] = [
                        kSecClass as String: kSecClassGenericPassword,
                        kSecAttrAccount as String: key,
                        kSecValueData as String: data
                    ]

                    SecItemAdd(query as CFDictionary, nil)
                }

                func read(key: String) -> String? {
                    let query: [String: Any] = [
                        kSecClass as String: kSecClassGenericPassword,
                        kSecAttrAccount as String: key,
                        kSecReturnData as String: true,
                        kSecMatchLimit as String: kSecMatchLimitOne
                    ]

                    var result: AnyObject?
                    let status = SecItemCopyMatching(query as CFDictionary, &result)

                    guard status == errSecSuccess, let data = result as? Data else { return nil }
                    return String(data: data, encoding: .utf8)
                }

                func delete(key: String) {
                    let query: [String: Any] = [
                        kSecClass as String: kSecClassGenericPassword,
                        kSecAttrAccount as String: key
                    ]

                    SecItemDelete(query as CFDictionary)
                }
            }
          SWIFT
        end

        # ── Auth Service ──────────────────────────────────────────────

        def generate_auth_service
          write_file("#{APP}/API/AuthService.swift", <<~SWIFT)
            import Foundation

            struct LoginRequest: Codable {
                let email: String
                let password: String
            }

            struct RegisterRequest: Codable {
                let email: String
                let password: String
                let name: String
            }

            struct AuthResponse: Codable {
                let token: String
                let user: User?
            }

            struct User: Codable, Identifiable {
                let id: Int
                let email: String
                let name: String?
            }

            enum AuthService {
                static func login(email: String, password: String) async throws -> AuthResponse {
                    try await APIClient.shared.request(
                        method: "POST",
                        path: "/auth/login",
                        body: LoginRequest(email: email, password: password)
                    )
                }

                static func register(email: String, password: String, name: String) async throws -> AuthResponse {
                    try await APIClient.shared.request(
                        method: "POST",
                        path: "/auth/register",
                        body: RegisterRequest(email: email, password: password, name: name)
                    )
                }

                static func logout() async throws {
                    try await APIClient.shared.requestVoid(method: "DELETE", path: "/auth/logout")
                }

                static func getMe() async throws -> User {
                    try await APIClient.shared.request(method: "GET", path: "/auth/me")
                }
            }
          SWIFT
        end

        # ── Models ────────────────────────────────────────────────────

        def generate_model(resource)
          name = classify(resource.name)
          fields = resource.fields || []

          props = fields.map do |f|
            fname = camel_case(f[:name])
            ftype = type_for(f[:type])
            ftype = "#{ftype}?" unless f[:required]
            "    var #{fname}: #{ftype}"
          end.join("\n")

          coding_keys = fields.map do |f|
            cc = camel_case(f[:name])
            orig = f[:name].to_s
            if cc != orig
              "        case #{cc} = \"#{orig}\""
            else
              "        case #{cc}"
            end
          end.join("\n")

          write_file("#{APP}/Models/#{name}.swift", <<~SWIFT)
            import Foundation

            struct #{name}: Codable, Identifiable {
                var id: Int?
            #{props}

                enum CodingKeys: String, CodingKey {
                    case id
            #{coding_keys}
                }
            }
          SWIFT
        end

        # ── Resource Service ──────────────────────────────────────────

        def generate_resource_service(resource)
          name = classify(resource.name)
          plural = resource.name.to_s
          path = "/#{plural}"

          write_file("#{APP}/API/#{name}Service.swift", <<~SWIFT)
            import Foundation

            enum #{name}Service {
                static func list() async throws -> [#{name}] {
                    try await APIClient.shared.request(method: "GET", path: "#{path}")
                }

                static func get(id: Int) async throws -> #{name} {
                    try await APIClient.shared.request(method: "GET", path: "#{path}/\\(id)")
                }

                static func create(_ item: #{name}) async throws -> #{name} {
                    try await APIClient.shared.request(method: "POST", path: "#{path}", body: item)
                }

                static func update(_ item: #{name}) async throws -> #{name} {
                    try await APIClient.shared.request(method: "PUT", path: "#{path}/\\(item.id ?? 0)", body: item)
                }

                static func delete(id: Int) async throws {
                    try await APIClient.shared.requestVoid(method: "DELETE", path: "#{path}/\\(id)")
                }
            }
          SWIFT
        end

        # ── ViewModels ───────────────────────────────────────────────

        def generate_auth_view_model
          write_file("#{APP}/ViewModels/AuthViewModel.swift", <<~SWIFT)
            import Foundation
            import SwiftUI

            @MainActor
            class AuthViewModel: ObservableObject {
                @Published var user: User?
                @Published var isAuthenticated = false
                @Published var errorMessage: String?
                @Published var isLoading = false

                init() {
                    if KeychainHelper.shared.read(key: "auth_token") != nil {
                        isAuthenticated = true
                        Task { await fetchMe() }
                    }
                }

                func login(email: String, password: String) async {
                    isLoading = true
                    errorMessage = nil
                    do {
                        let response = try await AuthService.login(email: email, password: password)
                        KeychainHelper.shared.save(key: "auth_token", value: response.token)
                        user = response.user
                        isAuthenticated = true
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                    isLoading = false
                }

                func register(email: String, password: String, name: String) async {
                    isLoading = true
                    errorMessage = nil
                    do {
                        let response = try await AuthService.register(email: email, password: password, name: name)
                        KeychainHelper.shared.save(key: "auth_token", value: response.token)
                        user = response.user
                        isAuthenticated = true
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                    isLoading = false
                }

                func logout() async {
                    do {
                        try await AuthService.logout()
                    } catch {}
                    KeychainHelper.shared.delete(key: "auth_token")
                    user = nil
                    isAuthenticated = false
                }

                func fetchMe() async {
                    do {
                        user = try await AuthService.getMe()
                    } catch {
                        isAuthenticated = false
                        KeychainHelper.shared.delete(key: "auth_token")
                    }
                }
            }
          SWIFT
        end

        def generate_resource_view_model(resource)
          name = classify(resource.name)

          write_file("#{APP}/ViewModels/#{name}ViewModel.swift", <<~SWIFT)
            import Foundation
            import SwiftUI

            @MainActor
            class #{name}ViewModel: ObservableObject {
                @Published var items: [#{name}] = []
                @Published var selectedItem: #{name}?
                @Published var isLoading = false
                @Published var errorMessage: String?

                func fetchAll() async {
                    isLoading = true
                    do {
                        items = try await #{name}Service.list()
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                    isLoading = false
                }

                func fetch(id: Int) async {
                    isLoading = true
                    do {
                        selectedItem = try await #{name}Service.get(id: id)
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                    isLoading = false
                }

                func create(_ item: #{name}) async {
                    do {
                        let created = try await #{name}Service.create(item)
                        items.append(created)
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }

                func update(_ item: #{name}) async {
                    do {
                        let updated = try await #{name}Service.update(item)
                        if let index = items.firstIndex(where: { $0.id == updated.id }) {
                            items[index] = updated
                        }
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }

                func delete(id: Int) async {
                    do {
                        try await #{name}Service.delete(id: id)
                        items.removeAll { $0.id == id }
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }
          SWIFT
        end

        # ── Auth Views ───────────────────────────────────────────────

        def generate_auth_views
          generate_login_view
          generate_register_view
        end

        def generate_login_view
          write_file("#{APP}/Views/Auth/LoginView.swift", <<~SWIFT)
            import SwiftUI

            struct LoginView: View {
                @EnvironmentObject var authViewModel: AuthViewModel
                @State private var email = ""
                @State private var password = ""
                @State private var showRegister = false

                var body: some View {
                    VStack(spacing: 20) {
                        Text("Login")
                            .font(.largeTitle)
                            .bold()

                        TextField("Email", text: $email)
                            .textFieldStyle(.roundedBorder)
                            .autocapitalization(.none)
                            .keyboardType(.emailAddress)

                        SecureField("Password", text: $password)
                            .textFieldStyle(.roundedBorder)

                        if let error = authViewModel.errorMessage {
                            Text(error).foregroundColor(.red).font(.caption)
                        }

                        Button(action: {
                            Task { await authViewModel.login(email: email, password: password) }
                        }) {
                            if authViewModel.isLoading {
                                ProgressView()
                            } else {
                                Text("Login").frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Don't have an account? Register") {
                            showRegister = true
                        }
                    }
                    .padding()
                    .sheet(isPresented: $showRegister) {
                        RegisterView()
                            .environmentObject(authViewModel)
                    }
                }
            }
          SWIFT
        end

        def generate_register_view
          write_file("#{APP}/Views/Auth/RegisterView.swift", <<~SWIFT)
            import SwiftUI

            struct RegisterView: View {
                @EnvironmentObject var authViewModel: AuthViewModel
                @Environment(\\.dismiss) var dismiss
                @State private var email = ""
                @State private var password = ""
                @State private var name = ""

                var body: some View {
                    NavigationStack {
                        VStack(spacing: 20) {
                            TextField("Name", text: $name)
                                .textFieldStyle(.roundedBorder)

                            TextField("Email", text: $email)
                                .textFieldStyle(.roundedBorder)
                                .autocapitalization(.none)
                                .keyboardType(.emailAddress)

                            SecureField("Password", text: $password)
                                .textFieldStyle(.roundedBorder)

                            if let error = authViewModel.errorMessage {
                                Text(error).foregroundColor(.red).font(.caption)
                            }

                            Button(action: {
                                Task {
                                    await authViewModel.register(email: email, password: password, name: name)
                                    if authViewModel.isAuthenticated { dismiss() }
                                }
                            }) {
                                if authViewModel.isLoading {
                                    ProgressView()
                                } else {
                                    Text("Register").frame(maxWidth: .infinity)
                                }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .padding()
                        .navigationTitle("Register")
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Cancel") { dismiss() }
                            }
                        }
                    }
                }
            }
          SWIFT
        end

        # ── Resource Views ───────────────────────────────────────────

        def generate_resource_views(resource)
          name = classify(resource.name)
          plural = camelize(resource.name)
          generate_list_view(resource, name, plural)
          generate_detail_view(resource, name, plural)
          generate_form_view(resource, name, plural)
        end

        def generate_list_view(resource, name, plural)
          write_file("#{APP}/Views/#{plural}/#{name}ListView.swift", <<~SWIFT)
            import SwiftUI

            struct #{name}ListView: View {
                @StateObject private var viewModel = #{name}ViewModel()
                @State private var showForm = false

                var body: some View {
                    List {
                        ForEach(viewModel.items) { item in
                            NavigationLink(destination: #{name}DetailView(id: item.id ?? 0)) {
                                Text(item.#{first_display_field(resource)})
                            }
                        }
                    }
                    .navigationTitle("#{plural}")
                    .toolbar {
                        Button(action: { showForm = true }) {
                            Image(systemName: "plus")
                        }
                    }
                    .sheet(isPresented: $showForm) {
                        #{name}FormView()
                    }
                    .task {
                        await viewModel.fetchAll()
                    }
                }
            }
          SWIFT
        end

        def generate_detail_view(resource, name, _plural)
          write_file("#{APP}/Views/#{camelize(resource.name)}/#{name}DetailView.swift", <<~SWIFT)
            import SwiftUI

            struct #{name}DetailView: View {
                let id: Int
                @StateObject private var viewModel = #{name}ViewModel()
                @Environment(\\.dismiss) var dismiss
                @State private var showEdit = false

                var body: some View {
                    Group {
                        if let item = viewModel.selectedItem {
                            VStack(alignment: .leading, spacing: 12) {
            #{detail_fields(resource)}
                                Spacer()
                            }
                            .padding()
                        } else if viewModel.isLoading {
                            ProgressView()
                        } else {
                            Text("Not found")
                        }
                    }
                    .navigationTitle("#{name} Detail")
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) {
                            Button("Edit") { showEdit = true }
                        }
                        ToolbarItem(placement: .destructiveAction) {
                            Button("Delete", role: .destructive) {
                                Task {
                                    await viewModel.delete(id: id)
                                    dismiss()
                                }
                            }
                        }
                    }
                    .sheet(isPresented: $showEdit) {
                        #{name}FormView(existing: viewModel.selectedItem)
                    }
                    .task {
                        await viewModel.fetch(id: id)
                    }
                }
            }
          SWIFT
        end

        def generate_form_view(resource, name, _plural)
          fields = resource.fields || []

          state_vars = fields.map do |f|
            fname = camel_case(f[:name])
            "    @State private var #{fname} = \"\""
          end.join("\n")

          form_fields = fields.map do |f|
            fname = camel_case(f[:name])
            label = f[:name].to_s.capitalize
            "                TextField(\"#{label}\", text: $#{fname})"
          end.join("\n")

          build_props = fields.map do |f|
            fname = camel_case(f[:name])
            if f[:required]
              "#{fname}: #{fname}"
            else
              "#{fname}: #{fname}.isEmpty ? nil : #{fname}"
            end
          end.join(", ")

          on_appear_lines = fields.map do |f|
            fname = camel_case(f[:name])
            "                    #{fname} = existing.#{fname}#{f[:required] ? '' : ' ?? \"\"'}"
          end.join("\n")

          write_file("#{APP}/Views/#{camelize(resource.name)}/#{name}FormView.swift", <<~SWIFT)
            import SwiftUI

            struct #{name}FormView: View {
                var existing: #{name}?
                @StateObject private var viewModel = #{name}ViewModel()
                @Environment(\\.dismiss) var dismiss
            #{state_vars}

                var body: some View {
                    NavigationStack {
                        Form {
            #{form_fields}
                        }
                        .navigationTitle(existing == nil ? "New #{name}" : "Edit #{name}")
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Cancel") { dismiss() }
                            }
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Save") {
                                    Task {
                                        var item = #{name}(id: existing?.id, #{build_props})
                                        if existing != nil {
                                            await viewModel.update(item)
                                        } else {
                                            await viewModel.create(item)
                                        }
                                        dismiss()
                                    }
                                }
                            }
                        }
                        .onAppear {
                            if let existing = existing {
            #{on_appear_lines}
                            }
                        }
                    }
                }
            }
          SWIFT
        end

        # ── Xcode Project ────────────────────────────────────────────

        def generate_xcode_project
          write_file("WhooshApp.xcodeproj/project.pbxproj", <<~PBXPROJ)
            // !$*UTF8*$!
            {
              archiveVersion = 1;
              classes = {};
              objectVersion = 56;
              objects = {
                /* Begin PBXGroup section */
                  00000000000000000000001 = {
                    isa = PBXGroup;
                    children = ();
                    sourceTree = "<group>";
                  };
                /* End PBXGroup section */

                /* Begin PBXProject section */
                  00000000000000000000002 = {
                    isa = PBXProject;
                    buildConfigurationList = 00000000000000000000003;
                    compatibilityVersion = "Xcode 14.0";
                    mainGroup = 00000000000000000000001;
                    productRefGroup = 00000000000000000000001;
                    projectDirPath = "";
                    projectRoot = "";
                  };
                /* End PBXProject section */

                /* Begin XCBuildConfiguration section */
                  00000000000000000000004 = {
                    isa = XCBuildConfiguration;
                    buildSettings = {
                      PRODUCT_BUNDLE_IDENTIFIER = com.whoosh.app;
                      PRODUCT_NAME = "$(TARGET_NAME)";
                      SWIFT_VERSION = 5.0;
                      TARGETED_DEVICE_FAMILY = "1,2";
                    };
                    name = Release;
                  };
                /* End XCBuildConfiguration section */

                /* Begin XCConfigurationList section */
                  00000000000000000000003 = {
                    isa = XCConfigurationList;
                    buildConfigurations = (
                      00000000000000000000004,
                    );
                    defaultConfigurationIsVisible = 0;
                    defaultConfigurationName = Release;
                  };
                /* End XCConfigurationList section */
              };
              rootObject = 00000000000000000000002;
            }
          PBXPROJ
        end

        # ── Helpers ───────────────────────────────────────────────────

        def camel_case(name)
          parts = name.to_s.split("_")
          parts.first + parts[1..].map(&:capitalize).join
        end

        def first_display_field(resource)
          fields = resource.fields || []
          field = fields.find { |f| f[:required] } || fields.first
          field ? camel_case(field[:name]) : "id ?? 0"
        end

        def detail_fields(resource)
          (resource.fields || []).map do |f|
            fname = camel_case(f[:name])
            label = f[:name].to_s.capitalize
            if f[:required]
              "                    Text(\"#{label}: \\(item.#{fname})\")"
            else
              "                    if let val = item.#{fname} { Text(\"#{label}: \\(val)\") }"
            end
          end.join("\n")
        end
      end
    end
  end
end
