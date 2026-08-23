require "logger"

namespace :loam do
  namespace :mcp do
    # Serve the Loam MCP server over stdio. Point an MCP client (Claude Code,
    # Cursor, Codex) at `bin/rails loam:mcp:serve` with LOAM_MCP_TOKEN set to a
    # Loam API token — the agent then acts as that token's user, in that tenant.
    #
    # stdout carries JSON-RPC only; every log is sent to stderr so it can't
    # corrupt the stream.
    desc "Serve the Loam MCP server over stdio (auth via LOAM_MCP_TOKEN)"
    task serve: :environment do
      Rails.logger = Logger.new($stderr)
      ActiveRecord::Base.logger = Rails.logger
      $stdout.sync = true

      Loam::Mcp::Server.new.run
    end
  end
end
