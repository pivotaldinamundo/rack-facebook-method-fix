module Rack
  module Facebook
    class MethodFix

      def initialize(app, settings={})
        @app = app
        @settings = settings
      end

      def call(env)
        unless env_excluded?(env)
          if env["REQUEST_METHOD"] == "POST"
            request = Request.new(env)
            if request.params["signed_request"]
              if @settings[:secret_id].nil? || signed_request_valid?(@settings[:secret_id], request)
                env["REQUEST_METHOD"] = "GET"
                env["facebook.signed_request"] = decoded_json(request.params["signed_request"])
              end
            end
          end
        end
        @app.call(env)
      end

      def decoded_json(signed_request)
        signature, payload = signed_request.split(".", 2)
        parsed_json_for_encoded_payload payload if payload
      end

      # Code adapted from https://github.com/nsanta/fbgraph
      def signed_request_valid?(secret_id, request)
        encoded_signature, payload = request.params["signed_request"].split(".", 2)
        signature = ""
        valid = true

        url_decode_64(encoded_signature).each_byte do |byte|
          signature << "%02x" % byte
        end

        data = parsed_json_for_encoded_payload(payload)
        if data["algorithm"].to_s.upcase != "HMAC-SHA256"
          valid = false
        end

        expected_signature = OpenSSL::HMAC.hexdigest("sha256", secret_id, payload)
        if expected_signature != signature
          valid = false
        end

        valid
      end

      protected

      def url_decode_64(string)
        encoded_string = string.gsub("-", "+").gsub("_", "/")
        encoded_string += "=" while !(encoded_string.size % 4).zero?
        Base64.decode64(encoded_string)
      end

      def env_excluded?(env)
        @settings[:exclude] && @settings[:exclude].call(env)
      end

      def parsed_json_for_encoded_payload(payload)
        JSON.parse(url_decode_64(payload))
      end

    end
  end
end
