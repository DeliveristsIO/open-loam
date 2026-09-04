require "logger"

namespace :open_loam do
  namespace :mcp do
    # Serve the OpenLoam MCP server over stdio. Point an MCP client (Claude Code,
    # Cursor, Codex) at `bin/rails open_loam:mcp:serve` with OPEN_LOAM_MCP_TOKEN set to a
    # OpenLoam API token — the agent then acts as that token's user, in that tenant.
    #
    # stdout carries JSON-RPC only; every log is sent to stderr so it can't
    # corrupt the stream.
    desc "Serve the OpenLoam MCP server over stdio (auth via OPEN_LOAM_MCP_TOKEN)"
    task serve: :environment do
      Rails.logger = Logger.new($stderr)
      ActiveRecord::Base.logger = Rails.logger
      $stdout.sync = true

      OpenLoam::Mcp::Server.new.run
    end
  end
end
