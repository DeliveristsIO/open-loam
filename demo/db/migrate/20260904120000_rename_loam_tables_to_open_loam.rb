class RenameLoamTablesToOpenLoam < ActiveRecord::Migration[8.1]
  TABLES = %w[
    api_tokens audit_records auth_attempts business_rule_runs business_rules
    comments configs custom_field_values dashboard_widgets dictionaries
    dictionary_entries event_deliveries field_definitions
    inbound_webhook_deliveries inbound_webhook_sources memberships
    mfa_credentials notifications pending_actions perspectives progress_jobs
    record_locks scheduled_jobs search_tokens sso_identities sso_providers
    tenants translations webhook_endpoints
  ].freeze

  def up
    TABLES.each { |t| rename_table "loam_#{t}", "open_loam_#{t}" }

    change_column_default :open_loam_inbound_webhook_sources, :signature_header,
                           from: "X-Loam-Signature", to: "X-OpenLoam-Signature"
    execute <<~SQL
      UPDATE open_loam_inbound_webhook_sources
      SET signature_header = 'X-OpenLoam-Signature'
      WHERE signature_header = 'X-Loam-Signature'
    SQL

    execute <<~SQL
      UPDATE open_loam_scheduled_jobs
      SET key = 'open_loam_event_redelivery_sweep'
      WHERE key = 'loam_event_redelivery_sweep'
    SQL
  end

  def down
    execute <<~SQL
      UPDATE open_loam_scheduled_jobs
      SET key = 'loam_event_redelivery_sweep'
      WHERE key = 'open_loam_event_redelivery_sweep'
    SQL

    execute <<~SQL
      UPDATE open_loam_inbound_webhook_sources
      SET signature_header = 'X-Loam-Signature'
      WHERE signature_header = 'X-OpenLoam-Signature'
    SQL
    change_column_default :open_loam_inbound_webhook_sources, :signature_header,
                           from: "X-OpenLoam-Signature", to: "X-Loam-Signature"

    TABLES.each { |t| rename_table "open_loam_#{t}", "loam_#{t}" }
  end
end
