# frozen_string_literal: true

module Whoosh
  module OpenAPI
    class UI
      SWAGGER_CDN = "https://unpkg.com/swagger-ui-dist@5"

      def self.swagger_html(spec_url)
        <<~HTML
          <!DOCTYPE html>
          <html lang="en">
          <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>API Docs</title>
            <link rel="stylesheet" href="#{SWAGGER_CDN}/swagger-ui.css">
          </head>
          <body>
            <div id="swagger-ui"></div>
            <script src="#{SWAGGER_CDN}/swagger-ui-bundle.js"></script>
            <script>
              SwaggerUIBundle({
                url: "#{spec_url}",
                dom_id: '#swagger-ui',
                presets: [SwaggerUIBundle.presets.apis],
                layout: "BaseLayout"
              });
            </script>
          </body>
          </html>
        HTML
      end

      def self.rack_response(spec_url)
        html = swagger_html(spec_url)
        [200, { "content-type" => "text/html", "content-length" => html.bytesize.to_s }, [html]]
      end
    end
  end
end
