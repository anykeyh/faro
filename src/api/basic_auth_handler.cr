require "base64"

module Faro
  module API
    class BasicAuthHandler < Kemal::Handler
      def initialize(@username : String, @password : String)
      end

      def call(env)
        unless authorized?(env)
          env.response.status_code = 401
          env.response.headers["WWW-Authenticate"] = %(Basic realm="Faro Monitoring")
          env.response.print "Unauthorized"
          return
        end

        call_next(env)
      end

      private def authorized?(env) : Bool
        header = env.request.headers["Authorization"]?
        return false unless header && header.starts_with?("Basic ")

        credentials = Base64.decode_string(header[6..]).split(":", 2)
        return false unless credentials.size == 2

        credentials[0] == @username && credentials[1] == @password
      end
    end
  end
end
