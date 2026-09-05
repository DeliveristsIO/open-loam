namespace :open_loam do
  desc "Re-run every OpenLoam.on_tenant_created callback for every existing tenant (idempotent)"
  task sync: :environment do
    synced = OpenLoam.sync_tenants!
    puts "open_loam:sync — ran #{OpenLoam.tenant_created_callbacks.size} tenant callback(s) across #{synced} tenant(s)."
  end

  namespace :openapi do
    # Write the OpenAPI 3.1 document + a Markdown rendering to disk, for CI or
    # publishing. Introspection only — no server, no network.
    #
    #   bin/rails open_loam:openapi:export
    desc "Export the API's OpenAPI JSON + Markdown to doc/"
    task export: :environment do
      require "json"
      dir = ENV["DIR"].presence || "doc"
      FileUtils.mkdir_p(dir)
      File.write(File.join(dir, "openapi.json"), JSON.pretty_generate(OpenLoam::OpenApi.document))
      File.write(File.join(dir, "openapi.md"), OpenLoam::OpenApi.markdown)
      puts "open_loam:openapi:export — wrote #{dir}/openapi.json and #{dir}/openapi.md."
    end
  end

  namespace :scheduler do
    # Fire every due recurring job once. Wire to system cron, every minute:
    #   * * * * * cd /app && bin/rails open_loam:scheduler:tick
    # The claim is atomic, so running this from several hosts never double-fires
    # a job (Postgres SKIP LOCKED; SQLite serializes the single-process claim).
    desc "Enqueue every due OpenLoam::ScheduledJob (run from cron)"
    task tick: :environment do
      fired = OpenLoam::Scheduler.tick
      puts "open_loam:scheduler:tick — fired #{fired} scheduled job(s)."
    end
  end

  namespace :index do
    # Rebuild the custom-field read-model index (OpenLoam::CustomFieldIndex) for every
    # entity with custom fields, in every tenant. Run once after enabling it so
    # existing rows are projected; new/updated records index themselves on save.
    #
    #   bin/rails open_loam:index:reindex
    desc "Rebuild the custom-field read-model index for every model in every tenant"
    task reindex: :environment do
      Rails.application.eager_load!
      models = OpenLoam::TenantRecord.descendants.select do |model|
        model.name.present? && model.respond_to?(:custom_field_definitions)
      end

      tenants = 0
      OpenLoam::Tenant.find_each do |tenant|
        OpenLoam.as_tenant(tenant) { models.each { |model| OpenLoam::CustomFieldIndex.reindex(model) } }
        tenants += 1
      end
      puts "open_loam:index:reindex — rebuilt #{models.size} model(s) across #{tenants} tenant(s)."
    end

    # Report custom-field index coverage (indexed vs expected) per model/field
    # per tenant — the trust signal for whether the index is complete or drifting.
    #
    #   bin/rails open_loam:index:coverage
    desc "Report custom-field index coverage per model/field per tenant"
    task coverage: :environment do
      Rails.application.eager_load!
      models = OpenLoam::TenantRecord.descendants.select do |model|
        model.name.present? && model.respond_to?(:custom_field_definitions)
      end

      OpenLoam::Tenant.find_each do |tenant|
        OpenLoam.as_tenant(tenant) do
          models.each do |model|
            model.custom_field_definitions.find_each do |definition|
              c = OpenLoam::CustomFieldIndex.coverage(model, definition.name)
              flag = c[:complete] ? "ok" : "GAP"
              puts "  [#{flag}] #{tenant.slug} #{model.name}.#{definition.name}: #{c[:indexed]}/#{c[:expected]} indexed"
            end
          end
        end
      end
    end
  end

  namespace :search do
    # Rebuild the active driver's search index for every searchable model in
    # every tenant. Needed once after switching to a driver that keeps an index
    # (OpenLoam::Search::TokenDriver): existing rows have no tokens until reindexed,
    # while new and updated records index themselves on save. A no-op under the
    # default LikeDriver (its reindex does nothing), so it is always safe to run.
    #
    #   bin/rails open_loam:search:reindex
    desc "Rebuild the search index for every searchable model in every tenant"
    task reindex: :environment do
      Rails.application.eager_load!
      models = OpenLoam::TenantRecord.descendants.select do |model|
        model.name.present? && model.respond_to?(:open_loam_searchable?) && model.open_loam_searchable?
      end

      tenants = 0
      OpenLoam::Tenant.find_each do |tenant|
        OpenLoam.as_tenant(tenant) { models.each { |model| OpenLoam::Search.reindex(model) } }
        tenants += 1
      end
      puts "open_loam:search:reindex — rebuilt #{models.size} model(s) across #{tenants} tenant(s) using #{OpenLoam::Search.driver}."
    end
  end

  namespace :sso do
    # Domain ownership can only be granted from OUTSIDE the tenant: the manager
    # who typed the domain is the party this check exists to constrain. Confirm
    # ownership out of band (DNS TXT, a signed request from the domain's
    # operator, an existing contract) BEFORE running this.
    #
    #   bin/rails open_loam:sso:verify_domain[42]
    desc "Mark an SSO provider's domain as proven-owned (operator only)"
    task :verify_domain, %i[provider_id] => :environment do |_task, args|
      provider = OpenLoam::SsoProvider.unscoped.find(args[:provider_id])
      tenant = OpenLoam::Tenant.find(provider.tenant_id)
      OpenLoam.as_tenant(tenant) { provider.verify_domain! }
      puts "open_loam:sso:verify_domain — #{provider.domain} verified for tenant #{tenant.slug} (provider #{provider.id})."
    end

    desc "Revoke an SSO provider's domain verification"
    task :unverify_domain, %i[provider_id] => :environment do |_task, args|
      provider = OpenLoam::SsoProvider.unscoped.find(args[:provider_id])
      tenant = OpenLoam::Tenant.find(provider.tenant_id)
      OpenLoam.as_tenant(tenant) { provider.update!(domain_verified_at: nil) }
      puts "open_loam:sso:unverify_domain — #{provider.domain} is no longer verified."
    end

    desc "List SSO providers and their domain-verification state"
    task providers: :environment do
      OpenLoam::SsoProvider.unscoped.order(:domain).each do |provider|
        state = provider.domain_verified? ? "verified #{provider.domain_verified_at.to_fs(:db)}" : "UNVERIFIED"
        puts format("%-6s %-30s tenant=%-6s %s", provider.id, provider.domain, provider.tenant_id, state)
      end
    end
  end

  namespace :encryption do
    # Rotate a tenant's encrypted data under the current key: read each record's
    # encrypted fields (old key) and re-seal them (new key), one record at a
    # time. The version tag in the stored format means old and new ciphertext
    # coexist, so this can run incrementally without downtime. Each record is an
    # ordinary audited "[encrypted]" update.
    #
    #   bin/rails open_loam:encryption:rotate[Customer,42]
    desc "Re-encrypt a model's encrypted fields for one tenant (rotation step)"
    task :rotate, %i[model tenant_id] => :environment do |_task, args|
      model = fetch_encryptable_model(args[:model])
      tenant = OpenLoam::Tenant.find(args[:tenant_id])

      count = 0
      OpenLoam.as_tenant(tenant) do
        each_record(model) do |record|
          record.open_loam_reencrypt!
          count += 1
        end
      end
      puts "open_loam:encryption:rotate — re-encrypted #{count} #{model.name} record(s) in tenant #{tenant.slug}."
    end

    # Decrypt and print one tenant's encrypted fields, e.g. for a GDPR data
    # export or a migration. OPERATIONAL CAUTION: this prints plaintext PII to
    # stdout — run it only where that output is safe (never into shared logs or
    # a shell history that syncs), and only for a tenant you are authorized to
    # export.
    #
    #   bin/rails open_loam:encryption:decrypt_dump[Customer,42]
    desc "Print decrypted encrypted-field values for one tenant (GDPR export; handle with care)"
    task :decrypt_dump, %i[model tenant_id] => :environment do |_task, args|
      require "json"
      model = fetch_encryptable_model(args[:model])
      tenant = OpenLoam::Tenant.find(args[:tenant_id])
      fields = model.open_loam_encrypted_attributes

      OpenLoam.as_tenant(tenant) do
        each_record(model) do |record|
          row = { id: record.id }.merge(fields.index_with { |field| record.public_send(field) })
          puts row.to_json
        end
      end
    end
  end
end

# Resolve a model name to a class that actually uses OpenLoam::Encryptable — a typo
# or a plain model should fail loudly, not silently dump/rotate nothing.
def fetch_encryptable_model(name)
  # Force the app's classes (and OpenLoam::TenantRecord, required lazily via the
  # active_record on_load hook) to load before we constantize a model name.
  Rails.application.eager_load!
  model = name.to_s.constantize
  unless model.respond_to?(:open_loam_encrypted_attributes) && model.open_loam_encrypted_attributes.any?
    abort "#{name} does not `include OpenLoam::Encryptable` with any `encrypts` fields."
  end
  model
end

# Iterate every record, soft-deleted ones included (a GDPR export must not miss
# data hidden in the recycle bin), staying inside the current tenant scope.
def each_record(model, &block)
  scope = model.respond_to?(:with_deleted) ? model.with_deleted : model.all
  scope.find_each(&block)
end
