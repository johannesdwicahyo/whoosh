# lib/whoosh/client_gen/generators/htmx.rb
# frozen_string_literal: true

require "whoosh/client_gen/base_generator"

module Whoosh
  module ClientGen
    module Generators
      class Htmx < BaseGenerator
        def generate
          generate_index
          generate_config_js
          generate_auth_js
          generate_api_js
          generate_style_css
          if ir.has_auth?
            generate_auth_login_page
            generate_auth_register_page
          end
          ir.resources.each do |resource|
            generate_resource_index_page(resource)
            generate_resource_show_page(resource)
            generate_resource_form_page(resource)
          end
        end

        private

        HEAD_INCLUDES = <<~HTML.freeze
            <meta charset="UTF-8" />
            <meta name="viewport" content="width=device-width, initial-scale=1.0" />
            <script src="https://unpkg.com/htmx.org@1.9.12"></script>
            <link rel="stylesheet" href="/css/style.css" />
            <script src="/config.js"></script>
            <script src="/js/auth.js"></script>
            <script src="/js/api.js"></script>
        HTML

        def generate_index
          nav_links = ir.resources.map do |r|
            plural = r.name.to_s
            "<a href=\"/pages/#{plural}/index.html\">#{camelize(plural)}</a>"
          end.join("\n      ")

          write_file("index.html", <<~HTML)
            <!DOCTYPE html>
            <html lang="en">
            <head>
              <title>App</title>
            #{HEAD_INCLUDES.chomp}
            </head>
            <body>
              <nav>
                <a href="/index.html">Home</a>
                #{nav_links}
                <a href="/pages/auth/login.html" id="nav-login">Login</a>
                <button id="nav-logout" onclick="handleLogout()" style="display:none">Logout</button>
              </nav>
              <main>
                <h1>Welcome</h1>
                <p>Select a resource from the navigation above.</p>
              </main>
              <script>
                requireAuth();
              </script>
            </body>
            </html>
          HTML
        end

        def generate_config_js
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
              if (refresh) localStorage.setItem("refresh_token", refresh);
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

            function handleLogout() {
              clearTokens();
              window.location.href = "/pages/auth/login.html";
            }

            // Attach Authorization header to every htmx request
            document.addEventListener("htmx:configRequest", function (evt) {
              var token = getToken();
              if (token) {
                evt.detail.headers["Authorization"] = "Bearer " + token;
              }
            });
          JS
        end

        def generate_api_js
          write_file("js/api.js", <<~JS)
            async function apiRequest(path, options) {
              options = options || {};
              var token = getToken();
              var headers = Object.assign({ "Content-Type": "application/json" }, options.headers || {});
              if (token) {
                headers["Authorization"] = "Bearer " + token;
              }
              var res = await fetch(API_URL + path, Object.assign({}, options, { headers: headers }));
              if (res.status === 401) {
                clearTokens();
                window.location.href = "/pages/auth/login.html";
                return;
              }
              if (!res.ok) {
                var err = await res.json().catch(function() { return {}; });
                throw err;
              }
              if (res.status === 204) return null;
              return res.json();
            }

            async function handleLogin(email, password, onSuccess, onError) {
              try {
                var data = await apiRequest("/auth/login", {
                  method: "POST",
                  body: JSON.stringify({ email: email, password: password })
                });
                setTokens(data.access_token, data.refresh_token);
                if (onSuccess) onSuccess(data);
              } catch (err) {
                if (onError) onError(err);
              }
            }

            async function handleRegister(email, password, onSuccess, onError) {
              try {
                var data = await apiRequest("/auth/register", {
                  method: "POST",
                  body: JSON.stringify({ email: email, password: password })
                });
                setTokens(data.access_token, data.refresh_token);
                if (onSuccess) onSuccess(data);
              } catch (err) {
                if (onError) onError(err);
              }
            }
          JS
        end

        def generate_style_css
          write_file("css/style.css", <<~CSS)
            * { box-sizing: border-box; margin: 0; padding: 0; }
            body { font-family: system-ui, sans-serif; line-height: 1.6; color: #333; background: #fafafa; }
            nav { display: flex; gap: 1rem; align-items: center; padding: 0.75rem 1.5rem; background: #fff; border-bottom: 1px solid #ddd; }
            nav a { text-decoration: none; color: #0066cc; }
            main { max-width: 960px; margin: 2rem auto; padding: 0 1rem; }
            h1 { margin-bottom: 1rem; }
            table { width: 100%; border-collapse: collapse; margin: 1rem 0; background: #fff; }
            th, td { padding: 0.6rem 0.75rem; border: 1px solid #ddd; text-align: left; }
            th { background: #f5f5f5; font-weight: 600; }
            form { display: flex; flex-direction: column; gap: 0.75rem; max-width: 420px; background: #fff; padding: 1.5rem; border: 1px solid #ddd; border-radius: 6px; }
            label { display: flex; flex-direction: column; gap: 0.25rem; font-weight: 500; }
            input, select { padding: 0.45rem 0.6rem; border: 1px solid #ccc; border-radius: 4px; font-size: 1rem; }
            button, .btn { padding: 0.5rem 1.1rem; background: #0066cc; color: #fff; border: none; border-radius: 4px; cursor: pointer; text-decoration: none; display: inline-block; font-size: 1rem; }
            button:hover, .btn:hover { background: #0052a3; }
            .btn-danger { background: #cc0000; }
            .btn-danger:hover { background: #990000; }
            .error { color: #cc0000; margin: 0.5rem 0; }
            .auth-page { max-width: 420px; margin: 3rem auto; }
            .actions { display: flex; gap: 0.5rem; }
          CSS
        end

        def generate_auth_login_page
          login_path = ir.auth.endpoints[:login][:path]
          write_file("pages/auth/login.html", page_html("Login", <<~BODY))
            <div class="auth-page">
              <h1>Login</h1>
              <p id="error" class="error" style="display:none"></p>
              <form id="login-form" hx-post="#{login_path}">
                <label>Email
                  <input type="email" id="email" name="email" required />
                </label>
                <label>Password
                  <input type="password" id="password" name="password" required />
                </label>
                <button type="submit">Login</button>
              </form>
              <p style="margin-top:1rem">Don&apos;t have an account? <a href="/pages/auth/register.html">Register</a></p>
            </div>
            <script>
              document.getElementById("login-form").addEventListener("submit", async function(e) {
                e.preventDefault();
                var email = document.getElementById("email").value;
                var password = document.getElementById("password").value;
                await handleLogin(email, password,
                  function() { window.location.href = "/index.html"; },
                  function(err) {
                    var el = document.getElementById("error");
                    el.textContent = (err && err.message) || "Login failed";
                    el.style.display = "";
                  }
                );
              });
            </script>
          BODY
        end

        def generate_auth_register_page
          register_path = ir.auth.endpoints[:register][:path]
          write_file("pages/auth/register.html", page_html("Register", <<~BODY))
            <div class="auth-page">
              <h1>Register</h1>
              <p id="error" class="error" style="display:none"></p>
              <form id="register-form" hx-post="#{register_path}" hx-ext="json-enc">
                <label>Email
                  <input type="email" id="email" name="email" required />
                </label>
                <label>Password
                  <input type="password" id="password" name="password" required />
                </label>
                <button type="submit">Register</button>
              </form>
              <p style="margin-top:1rem">Already have an account? <a href="/pages/auth/login.html">Login</a></p>
            </div>
            <script>
              document.getElementById("register-form").addEventListener("submit", async function(e) {
                e.preventDefault();
                var email = document.getElementById("email").value;
                var password = document.getElementById("password").value;
                await handleRegister(email, password,
                  function() { window.location.href = "/index.html"; },
                  function(err) {
                    var el = document.getElementById("error");
                    el.textContent = (err && err.message) || "Registration failed";
                    el.style.display = "";
                  }
                );
              });
            </script>
          BODY
        end

        def generate_resource_index_page(resource)
          plural = resource.name.to_s
          singular = singularize(plural)
          name = camelize(plural)
          fields = resource.fields || []
          index_ep = resource.endpoints.find { |e| e.action == :index }
          list_path = index_ep ? index_ep.path : "/#{plural}"

          th_cells = fields.map { |f| "<th>#{camelize(f[:name].to_s)}</th>" }.join("\n          ")
          td_cells = fields.map { |f|
            "<td class=\"item-#{f[:name]}\"></td>"
          }.join("\n          ")

          write_file("pages/#{plural}/index.html", page_html("#{name} List", <<~BODY))
            <main>
              <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:1rem">
                <h1>#{name}</h1>
                <a href="/pages/#{plural}/form.html" class="btn">New #{singularize(name)}</a>
              </div>
              <table id="#{plural}-table">
                <thead>
                  <tr>
                    #{th_cells}
                    <th>Actions</th>
                  </tr>
                </thead>
                <tbody id="#{plural}-body">
                  <tr><td colspan="#{fields.length + 1}">Loading...</td></tr>
                </tbody>
              </table>
            </main>
            <script>
              requireAuth();
              (async function() {
                var tbody = document.getElementById("#{plural}-body");
                try {
                  var items = await apiRequest("#{list_path}");
                  if (!items || items.length === 0) {
                    tbody.innerHTML = "<tr><td colspan=\\"#{fields.length + 1}\\">No #{plural} found.</td></tr>";
                    return;
                  }
                  tbody.innerHTML = items.map(function(item) {
                    return "<tr>" +
                      #{fields.map { |f| "\"<td>\" + (item.#{f[:name]} !== undefined ? item.#{f[:name]} : \"\") + \"</td>\"" }.join(" +\n                      ")} +
                      "<td class=\\"actions\\">" +
                        "<a href=\\"/pages/#{plural}/show.html?id=" + item.id + "\\" class=\\"btn\\">View</a> " +
                        "<a href=\\"/pages/#{plural}/form.html?id=" + item.id + "\\" class=\\"btn\\">Edit</a> " +
                        "<button class=\\"btn-danger\\" onclick=\\"deleteItem('" + item.id + "')\\">Delete</button>" +
                      "</td>" +
                    "</tr>";
                  }).join("");
                } catch(err) {
                  tbody.innerHTML = "<tr><td colspan=\\"#{fields.length + 1}\\" class=\\"error\\">Failed to load #{plural}.</td></tr>";
                }
              })();

              async function deleteItem(id) {
                if (!confirm("Delete this #{singularize(name)}?")) return;
                try {
                  await apiRequest("/#{plural}/" + id, { method: "DELETE" });
                  window.location.reload();
                } catch(err) {
                  alert("Delete failed");
                }
              }
            </script>
          BODY
        end

        def generate_resource_show_page(resource)
          plural = resource.name.to_s
          singular = singularize(plural)
          name = camelize(singular)
          fields = resource.fields || []

          field_rows = fields.map { |f|
            "<p><strong>#{camelize(f[:name].to_s)}:</strong> <span id=\"field-#{f[:name]}\"></span></p>"
          }.join("\n        ")

          field_assigns = fields.map { |f|
            "document.getElementById(\"field-#{f[:name]}\").textContent = item.#{f[:name]} !== undefined ? item.#{f[:name]} : \"—\";"
          }.join("\n          ")

          write_file("pages/#{plural}/show.html", page_html("#{name} Detail", <<~BODY))
            <main>
              <h1 id="page-title">#{name} Detail</h1>
              <div id="detail-content">
                #{field_rows}
              </div>
              <div class="actions" style="margin-top:1rem">
                <a id="edit-link" href="#" class="btn">Edit</a>
                <button class="btn-danger" onclick="deleteItem()">Delete</button>
                <a href="/pages/#{plural}/index.html" class="btn">Back</a>
              </div>
            </main>
            <script>
              requireAuth();
              var params = new URLSearchParams(window.location.search);
              var id = params.get("id");
              if (!id) { window.location.href = "/pages/#{plural}/index.html"; }

              document.getElementById("edit-link").href = "/pages/#{plural}/form.html?id=" + id;

              (async function() {
                try {
                  var item = await apiRequest("/#{plural}/" + id);
                  #{field_assigns}
                } catch(err) {
                  document.getElementById("detail-content").innerHTML = "<p class=\\"error\\">Failed to load.</p>";
                }
              })();

              async function deleteItem() {
                if (!confirm("Delete this #{name}?")) return;
                try {
                  await apiRequest("/#{plural}/" + id, { method: "DELETE" });
                  window.location.href = "/pages/#{plural}/index.html";
                } catch(err) {
                  alert("Delete failed");
                }
              }
            </script>
          BODY
        end

        def generate_resource_form_page(resource)
          plural = resource.name.to_s
          singular = singularize(plural)
          name = camelize(singular)
          fields = resource.fields || []

          input_fields = fields.map do |f|
            fname = f[:name].to_s
            ftype = type_for(f[:type])
            required_attr = f[:required] ? " required" : ""
            if f[:enum]
              options = f[:enum].map { |v| "<option value=\"#{v}\">#{v}</option>" }.join("\n              ")
              <<~FIELD.chomp
                <label>#{camelize(fname)}
                    <select id="field-#{fname}" name="#{fname}"#{required_attr}>
                      <option value="">Select...</option>
                      #{options}
                    </select>
                  </label>
              FIELD
            else
              input_type = ftype == "number" ? "number" : (fname.include?("password") ? "password" : (fname.include?("email") ? "email" : "text"))
              <<~FIELD.chomp
                <label>#{camelize(fname)}
                    <input type="#{input_type}" id="field-#{fname}" name="#{fname}"#{required_attr} />
                  </label>
              FIELD
            end
          end.join("\n          ")

          field_collect = fields.map { |f|
            "#{f[:name]}: document.getElementById(\"field-#{f[:name]}\").value"
          }.join(",\n              ")

          field_load = fields.map { |f|
            "document.getElementById(\"field-#{f[:name]}\").value = item.#{f[:name]} !== undefined ? item.#{f[:name]} : \"\";"
          }.join("\n            ")

          write_file("pages/#{plural}/form.html", page_html("#{name} Form", <<~BODY))
            <main>
              <h1 id="page-title">New #{name}</h1>
              <p id="error" class="error" style="display:none"></p>
              <form id="resource-form">
                #{input_fields}
                <button type="submit" id="submit-btn">Create</button>
              </form>
              <a href="/pages/#{plural}/index.html">Back to list</a>
            </main>
            <script>
              requireAuth();
              var params = new URLSearchParams(window.location.search);
              var id = params.get("id");
              var isEdit = Boolean(id);

              if (isEdit) {
                document.getElementById("page-title").textContent = "Edit #{name}";
                document.getElementById("submit-btn").textContent = "Update";
                (async function() {
                  try {
                    var item = await apiRequest("/#{plural}/" + id);
                    #{field_load}
                  } catch(err) {
                    document.getElementById("error").textContent = "Failed to load item.";
                    document.getElementById("error").style.display = "";
                  }
                })();
              }

              document.getElementById("resource-form").addEventListener("submit", async function(e) {
                e.preventDefault();
                var errEl = document.getElementById("error");
                errEl.style.display = "none";
                var body = {
                  #{field_collect}
                };
                try {
                  if (isEdit) {
                    await apiRequest("/#{plural}/" + id, { method: "PUT", body: JSON.stringify(body) });
                  } else {
                    await apiRequest("/#{plural}", { method: "POST", body: JSON.stringify(body) });
                  }
                  window.location.href = "/pages/#{plural}/index.html";
                } catch(err) {
                  errEl.textContent = (err && err.message) || "Save failed";
                  errEl.style.display = "";
                }
              });
            </script>
          BODY
        end

        # Wraps body content in a full HTML document shell
        def page_html(title, body_content)
          <<~HTML
            <!DOCTYPE html>
            <html lang="en">
            <head>
              <title>#{title}</title>
            #{HEAD_INCLUDES.chomp}
            </head>
            <body>
              <nav>
                <a href="/index.html">Home</a>
            #{ir.resources.map { |r| "    <a href=\"/pages/#{r.name}/index.html\">#{camelize(r.name.to_s)}</a>" }.join("\n")}
                <button onclick="handleLogout()">Logout</button>
              </nav>
            #{body_content.chomp}
            </body>
            </html>
          HTML
        end
      end
    end
  end
end
