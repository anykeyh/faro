module Faro::API
  # Frontend files embedded at compile time when building with --release.
  # In dev mode (crystal run / spec) files are read from disk instead.
  module EmbeddedFrontend
    # Frontend files embedded at compile time when building with --release.
    # In dev mode the constant is empty and files are served from disk instead.
    FILES = {% if flag?(:release) %}
      {
        "/index.html"                   => {{ read_file("frontend/index.html") }},
        "/styles.css"                   => {{ read_file("frontend/styles.css") }},
        "/app.js"                       => {{ read_file("frontend/app.js") }},
        "/mithril.js"                   => {{ read_file("frontend/mithril.js") }},
        "/api.js"                       => {{ read_file("frontend/api.js") }},
        "/store.js"                     => {{ read_file("frontend/store.js") }},
        "/components/header.js"         => {{ read_file("frontend/components/header.js") }},
        "/components/indicator_card.js" => {{ read_file("frontend/components/indicator_card.js") }},
        "/components/graph_card.js"     => {{ read_file("frontend/components/graph_card.js") }},
        "/components/latch_card.js"     => {{ read_file("frontend/components/latch_card.js") }},
        "/components/add_card.js"       => {{ read_file("frontend/components/add_card.js") }},
        "/components/dashboard.js"      => {{ read_file("frontend/components/dashboard.js") }},
      }
    {% else %}
      {} of String => String
    {% end %}

    # Returns the content for a request path, or nil if not found.
    def self.get(request_path : String) : String?
      {% if flag?(:release) %}
        FILES[request_path]?
      {% else %}
        nil
      {% end %}
    end
  end
end
