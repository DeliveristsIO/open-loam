require "json"

module OpenLoam
  module Mcp
    # The stdio transport for the OpenLoam MCP server (L-302): newline-delimited
    # JSON-RPC over stdin/stdout, the MCP-spec stdio binding. Authenticates ONCE
    # from OPEN_LOAM_MCP_TOKEN (a OpenLoam API token — never a tool argument, so it can't
    # land in an agent transcript), then runs every message inside that token's
    # tenant + actor. Nothing but JSON-RPC is written to stdout; logs go to stderr
    # (wired in the rake task) — a stray stdout line corrupts the stream.
    class Server
      def initialize(input: $stdin, output: $stdout, token: ENV["OPEN_LOAM_MCP_TOKEN"])
        @input = input
        @output = output
        @token = token
      end

      def run
        api_token = OpenLoam::ApiToken.authenticate(@token)
        return fail_auth unless api_token

        tenant = api_token.tenant
        actor = api_token.user

        @input.each_line do |line|
          line = line.strip
          next if line.empty?

          request = parse(line)
          next write(OpenLoam::Mcp.err(nil, -32700, "parse error")) if request.nil?

          begin
            response = OpenLoam.as_tenant(tenant, actor: actor) { OpenLoam::Mcp.handle_jsonrpc(request) }
            write(response) if response
          ensure
            OpenLoam::Current.reset
          end
        end
      end

      private

      def parse(line)
        JSON.parse(line)
      rescue JSON::ParserError
        nil
      end

      def write(message)
        @output.puts(JSON.generate(message))
        @output.flush
      end

      def fail_auth
        write(OpenLoam::Mcp.err(nil, -32001, "authentication failed: set OPEN_LOAM_MCP_TOKEN to a valid OpenLoam API token"))
        exit(1)
      end
    end
  end
end
