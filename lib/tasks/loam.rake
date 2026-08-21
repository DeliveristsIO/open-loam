namespace :loam do
  desc "Re-run every Loam.on_tenant_created callback for every existing tenant (idempotent)"
  task sync: :environment do
    synced = Loam.sync_tenants!
    puts "loam:sync — ran #{Loam.tenant_created_callbacks.size} tenant callback(s) across #{synced} tenant(s)."
  end

  namespace :search do
    # Rebuild the active driver's search index for every searchable model in
    # every tenant. Needed once after switching to a driver that keeps an index
    # (Loam::Search::TokenDriver): existing rows have no tokens until reindexed,
    # while new and updated records index themselves on save. A no-op under the
    # default LikeDriver (its reindex does nothing), so it is always safe to run.
    #
    #   bin/rails loam:search:reindex
    desc "Rebuild the search index for every searchable model in every tenant"
    task reindex: :environment do
      Rails.application.eager_load!
      models = Loam::TenantRecord.descendants.select do |model|
        model.respond_to?(:loam_searchable?) && model.loam_searchable?
      end

      tenants = 0
      Loam::Tenant.find_each do |tenant|
        Loam.as_tenant(tenant) { models.each { |model| Loam::Search.reindex(model) } }
        tenants += 1
      end
      puts "loam:search:reindex — rebuilt #{models.size} model(s) across #{tenants} tenant(s) using #{Loam::Search.driver}."
    end
  end

  namespace :encryption do
    # Rotate a tenant's encrypted data under the current key: read each record's
    # encrypted fields (old key) and re-seal them (new key), one record at a
    # time. The version tag in the stored format means old and new ciphertext
    # coexist, so this can run incrementally without downtime. Each record is an
    # ordinary audited "[encrypted]" update.
    #
    #   bin/rails loam:encryption:rotate[Customer,42]
    desc "Re-encrypt a model's encrypted fields for one tenant (rotation step)"
    task :rotate, %i[model tenant_id] => :environment do |_task, args|
      model = fetch_encryptable_model(args[:model])
      tenant = Loam::Tenant.find(args[:tenant_id])

      count = 0
      Loam.as_tenant(tenant) do
        each_record(model) do |record|
          record.loam_reencrypt!
          count += 1
        end
      end
      puts "loam:encryption:rotate — re-encrypted #{count} #{model.name} record(s) in tenant #{tenant.slug}."
    end

    # Decrypt and print one tenant's encrypted fields, e.g. for a GDPR data
    # export or a migration. OPERATIONAL CAUTION: this prints plaintext PII to
    # stdout — run it only where that output is safe (never into shared logs or
    # a shell history that syncs), and only for a tenant you are authorized to
    # export.
    #
    #   bin/rails loam:encryption:decrypt_dump[Customer,42]
    desc "Print decrypted encrypted-field values for one tenant (GDPR export; handle with care)"
    task :decrypt_dump, %i[model tenant_id] => :environment do |_task, args|
      require "json"
      model = fetch_encryptable_model(args[:model])
      tenant = Loam::Tenant.find(args[:tenant_id])
      fields = model.loam_encrypted_attributes

      Loam.as_tenant(tenant) do
        each_record(model) do |record|
          row = { id: record.id }.merge(fields.index_with { |field| record.public_send(field) })
          puts row.to_json
        end
      end
    end
  end
end

# Resolve a model name to a class that actually uses Loam::Encryptable — a typo
# or a plain model should fail loudly, not silently dump/rotate nothing.
def fetch_encryptable_model(name)
  # Force the app's classes (and Loam::TenantRecord, required lazily via the
  # active_record on_load hook) to load before we constantize a model name.
  Rails.application.eager_load!
  model = name.to_s.constantize
  unless model.respond_to?(:loam_encrypted_attributes) && model.loam_encrypted_attributes.any?
    abort "#{name} does not `include Loam::Encryptable` with any `encrypts` fields."
  end
  model
end

# Iterate every record, soft-deleted ones included (a GDPR export must not miss
# data hidden in the recycle bin), staying inside the current tenant scope.
def each_record(model, &block)
  scope = model.respond_to?(:with_deleted) ? model.with_deleted : model.all
  scope.find_each(&block)
end
