module OpenLoam
  # Field-level encryption at rest, keyed per tenant. Declare it on a model:
  #
  #   class Patient < OpenLoam::TenantRecord
  #     include OpenLoam::Encryptable
  #     encrypts :ssn                      # encrypted at rest, not searchable
  #     encrypts :email, searchable: true  # + a blind index for exact-match lookup
  #   end
  #
  #   Patient.create!(ssn: "078-05-1120")   # the ssn COLUMN now holds "v1:...."
  #   patient.ssn                           # => "078-05-1120" (decrypted on read)
  #   Patient.find_by_email("a@b.com")      # exact match via the blind index
  #
  # The value is sealed with the CURRENT tenant's key (OpenLoam.tenant!), never the
  # record's stored tenant_id — so a read in the wrong tenant's context fails the
  # GCM auth tag instead of quietly decrypting another tenant's data. Reading or
  # writing an encrypted field with no tenant in context raises
  # MissingTenantError: you cannot encrypt without knowing whose key.
  #
  # Encryption happens eagerly on assignment, so re-submitting a form with the
  # same value re-seals it under a fresh IV and records a "[encrypted]" audit
  # update with no real change — accepted prototype noise.
  module Encryptable
    extend ActiveSupport::Concern

    included do
      class_attribute :open_loam_encrypted_attributes, default: [].freeze, instance_writer: false
      class_attribute :open_loam_searchable_encrypted_attributes, default: [].freeze, instance_writer: false
    end

    class_methods do
      # `scope:` chooses whose key seals the field. `:tenant` (default) keys off
      # OpenLoam.tenant! — right for entity data. A Proc `->(record) { "user/#{...}" }`
      # keys off something else, for genuinely non-tenant data (an MFA secret
      # belongs to the person and must decrypt in any tenant, and at login before
      # a tenant is chosen). Non-tenant scopes cannot be `searchable`.
      def encrypts(name, searchable: false, scope: :tenant)
        name = name.to_s

        if searchable && scope != :tenant
          raise OpenLoam::Error, "#{self.name}: `#{name}` cannot be both `searchable` and non-tenant-scoped."
        end

        # Encrypted ciphertext is meaningless to a LIKE scan, so the two are a
        # contradiction. Caught whichever declaration comes second (Searchable
        # runs the mirror check), so order in the model does not matter.
        if respond_to?(:open_loam_searchable_columns) && open_loam_searchable_columns.include?(name)
          raise OpenLoam::Error,
                "#{self.name}: `#{name}` is declared both `searchable_by` (LIKE) and `encrypts` — " \
                "ciphertext cannot be LIKE-searched. Drop it from `searchable_by` and use " \
                "`encrypts :#{name}, searchable: true` for exact-match lookup instead."
        end

        # A translation row would store the field's PLAINTEXT — recreating the
        # leak encryption closes. Caught whichever declaration comes second
        # (Translatable runs the mirror check), so model order does not matter.
        if respond_to?(:open_loam_translatable_attributes) && open_loam_translatable_attributes.include?(name)
          raise OpenLoam::Error,
                "#{self.name}: `#{name}` is declared both `translates` and `encrypts` — a translation " \
                "would store plaintext. Encrypted data is not translatable."
        end

        self.open_loam_encrypted_attributes = (open_loam_encrypted_attributes + [name]).freeze
        self.open_loam_searchable_encrypted_attributes = (open_loam_searchable_encrypted_attributes + [name]).freeze if searchable

        include open_loam_encryption_reader_writer(name, searchable, scope)
        define_open_loam_blind_index_finder(name) if searchable
      end

      # Reader/writer live in their own module (the OpenLoam::Workflow precedent) so
      # an app can override and still call `super`, and so they sit ABOVE Active
      # Record's generated attribute methods in the ancestor chain and win.
      def open_loam_encryption_reader_writer(name, searchable, scope)
        hash_column = "#{name}_hash"

        Module.new do
          define_method(name) do
            resolved = open_loam_encryption_scope(scope)
            aad = OpenLoam::Encryption.aad(resolved, self.class.table_name, name)
            OpenLoam::Encryption.decrypt_scoped(read_attribute(name), resolved, aad: aad)
          end

          define_method("#{name}=") do |value|
            resolved = open_loam_encryption_scope(scope)
            # Bind this ciphertext to its (scope, table, column) so it can't be
            # transplanted to another column/table/tenant (v2 AAD).
            aad = OpenLoam::Encryption.aad(resolved, self.class.table_name, name)
            write_attribute(name, OpenLoam::Encryption.encrypt_scoped(value, resolved, aad: aad))
            # The blind index tracks the ciphertext column: rewrite it in the
            # same breath, so an exact-match lookup can never go stale.
            write_attribute(hash_column, OpenLoam::Encryption.blind_index_scoped(value, resolved)) if searchable
          end
        end
      end

      # `find_by_<name>` / `where_<name>` match the per-tenant blind index. They
      # deliberately shadow Active Record's dynamic `find_by_<attr>`: the obvious
      # call must hash-and-compare, never match a plaintext query against the
      # ciphertext column (which would silently find nothing).
      def define_open_loam_blind_index_finder(name)
        hash_column = :"#{name}_hash"

        define_singleton_method("where_#{name}") do |value|
          where(hash_column => OpenLoam::Encryption.blind_index(value, OpenLoam.tenant!.id))
        end

        define_singleton_method("find_by_#{name}") do |value|
          public_send("where_#{name}", value).first
        end
      end
    end

    private

    # Resolve a declared `scope:` to the namespaced owner string the key is
    # derived from. `:tenant` keys off the current tenant (raises with none, the
    # same safety property as an entity write); a Proc computes it from the
    # record. A blank or `.../`-terminated result (e.g. a nil user_id) raises
    # rather than deriving a degenerate shared key.
    def open_loam_encryption_scope(scope)
      resolved = scope == :tenant ? "tenant/#{OpenLoam.tenant!.id}" : scope.call(self).to_s

      if resolved.strip.empty? || resolved.end_with?("/")
        raise OpenLoam::Encryption::Error, "#{self.class}: cannot derive an encryption key from a blank scope (#{resolved.inspect})"
      end
      resolved
    end

    public

    # Re-seal every encrypted field under the current key, with fresh IVs — the
    # per-record step of a key rotation (read old, write new). With HKDF-from-
    # master, a real rotation means a new master or a bumped Cipher::VERSION; the
    # version tag lets old and new ciphertext coexist while this runs across a
    # tenant's records, so rotation is a lazy re-encrypt, not a stop-the-world
    # migration. Writes an ordinary audited "[encrypted]" update — see
    # lib/tasks/open_loam.rake (open_loam:encryption:rotate).
    def open_loam_reencrypt!
      self.class.open_loam_encrypted_attributes.each do |name|
        public_send("#{name}=", public_send(name))
      end
      save!
    end
  end
end
