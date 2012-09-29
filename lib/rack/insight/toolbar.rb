module Rack::Insight
  class Toolbar
    include Render
    include Logging

    MIME_TYPES = ["text/html", "application/xhtml+xml"]

    def initialize(app, insight)
      @app = app
      @insight = insight
      @request_table = Database::RequestTable.new
    end

    def call(env)
      @env = env
      status, headers, body = @app.call(@env)

      response = Rack::Response.new(body, status, headers)

      if okay_to_modify?(env, response)
        inject_toolbar(response)
      end

      return response.to_a
    end

    def okay_to_modify?(env, response)
      req = Rack::Request.new(env)
      content_type, charset = response.content_type.split(";")

      response.ok? && MIME_TYPES.include?(content_type) && !req.xhr?
    end

    def inject_toolbar(response)
      full_body = response.body.join

      toolbar = render
      toolbar.force_encoding('UTF-8') if RUBY_VERSION > '1.9.0'

      # install at bottom
      # full_body.sub! /<\/body>/, toolbar + "</body>"
      
      # install at top
      full_body.sub! /<(body[^>]*)>/, "\1#{toolbar}"

      response["Content-Length"] = full_body.size.to_s

      # Ensure that browser doesn't cache
      response["Etag"] = ""
      response["Cache-Control"] = "no-cache"

      response.body = [full_body]
    end

    def render
      req_id = (@env['rack-insight.request-id'] || @request_table.last_request_id).to_i
      requests = @request_table.to_a.map do |row|
        { :id => row[0], :method => row[1], :path => row[2] }
      end

      unless verbose(:silent)
        logger.info do
          "Injecting toolbar: active panels: #{@insight.panels.map{|pnl| pnl.class.name}.inspect}"
        end
      end

      headers_fragment = render_template("headers_fragment",
                                         :panels => @insight.panels,
                                         :request_id => req_id)

      current_request_fragment = render_template("request_fragment",
                                                 :request_id => req_id,
                                                 :requests => requests,
                                                 :panels => @insight.panels)
      render_template("toolbar",
                      :request_fragment => current_request_fragment,
                      :headers_fragment => headers_fragment,
                      :request_id => req_id)
    end
  end
end
