require "json"

module Loam
  module Mcp
    # The stdio transport for the Loam MCP server (L-302): newline-delimited
    # JSON-RPC over stdin/stdout, the MCP-spec stdio binding. Authenticates ONCE
    # from LOAM_MCP_TOKEN (a Loam API token — never a tool argument, so it can't
    # land in an agent transcript), then runs every message inside that token's
    # tenant + actor. Nothing but JSON-RPC is written to stdout; logs go to stderr
    # (wired in the rake task) — a stray stdout line corrupts the stream.
    class Server
      def initialize(input: $stdin, output: $stdout, token: ENV["LOAM_MCP_TOKEN"])
        @input = input
        @output = output
        @token = token
      end

      def run
        api_token = Loam::ApiToken.authenticate(@token)
        return fail_auth unless api_token

        tenant = api_token.tenant
        actor = api_token.user

        @input.each_line do |line|
          line = line.strip
          next if line.empty?

          request = parse(line)
          next write(Loam::Mcp.err(nil, -32700, "parse error")) if request.nil?

          begin
            response = Loam.as_tenant(tenant, actor: actor) { Loam::Mcp.handle_jsonrpc(request) }
            write(response) if response
          ensure
            Loam::Current.reset
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
        write(Loam::Mcp.err(nil, -32001, "authentication failed: set LOAM_MCP_TOKEN to a valid Loam API token"))
        exit(1)
      end
    end
  end
end
