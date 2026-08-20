module Loam
  # Field-level encryption at rest, keyed per tenant. Declare it on a model:
  #
  #   class Patient < Loam::TenantRecord
  #     include Loam::Encryptable
  #     encrypts :ssn                      # encrypted at rest, not searchable
  #     encrypts :email, searchable: true  # + a blind index for exact-match lookup
  #   end
  #
  #   Patient.create!(ssn: "078-05-1120")   # the ssn COLUMN now holds "v1:...."
  #   patient.ssn                           # => "078-05-1120" (decrypted on read)
  #   Patient.find_by_email("a@b.com")      # exact match via the blind index
  #
  # The value is sealed with the CURRENT tenant's key (Loam.tenant!), never the
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
      class_attribute :loam_encrypted_attributes, default: [].freeze, instance_writer: false
      class_attribute :loam_searchable_encrypted_attributes, default: [].freeze, instance_writer: false
    end

    class_methods do
      def encrypts(name, searchable: false)
        name = name.to_s

        # Encrypted ciphertext is meaningless to a LIKE scan, so the two are a
        # contradiction. Caught whichever declaration comes second (Searchable
        # runs the mirror check), so order in the model does not matter.
        if respond_to?(:loam_searchable_columns) && loam_searchable_columns.include?(name)
          raise Loam::Error,
                "#{self.name}: `#{name}` is declared both `searchable_by` (LIKE) and `encrypts` — " \
                "ciphertext cannot be LIKE-searched. Drop it from `searchable_by` and use " \
                "`encrypts :#{name}, searchable: true` for exact-match lookup instead."
        end

        self.loam_encrypted_attributes = (loam_encrypted_attributes + [name]).freeze
        self.loam_searchable_encrypted_attributes = (loam_searchable_encrypted_attributes + [name]).freeze if searchable

        include loam_encryption_reader_writer(name, searchable)
        define_loam_blind_index_finder(name) if searchable
      end

      # Reader/writer live in their own module (the Loam::Workflow precedent) so
      # an app can override and still call `super`, and so they sit ABOVE Active
      # Record's generated attribute methods in the ancestor chain and win.
      def loam_encryption_reader_writer(name, searchable)
        hash_column = "#{name}_hash"

        Module.new do
          define_method(name) do
            Loam::Encryption.decrypt(read_attribute(name), Loam.tenant!.id)
          end

          define_method("#{name}=") do |value|
            tenant_id = Loam.tenant!.id
            write_attribute(name, Loam::Encryption.encrypt(value, tenant_id))
            # The blind index tracks the ciphertext column: rewrite it in the
            # same breath, so an exact-match lookup can never go stale.
            write_attribute(hash_column, Loam::Encryption.blind_index(value, tenant_id)) if searchable
          end
        end
      end

      # `find_by_<name>` / `where_<name>` match the per-tenant blind index. They
      # deliberately shadow Active Record's dynamic `find_by_<attr>`: the obvious
      # call must hash-and-compare, never match a plaintext query against the
      # ciphertext column (which would silently find nothing).
      def define_loam_blind_index_finder(name)
        hash_column = "#{name}_hash"

        define_singleton_method("where_#{name}") do |value|
          where(hash_column => Loam::Encryption.blind_index(value, Loam.tenant!.id))
        end

        define_singleton_method("find_by_#{name}") do |value|
          public_send("where_#{name}", value).first
        end
      end
    end

    # Re-seal every encrypted field under the current key, with fresh IVs — the
    # per-record step of a key rotation (read old, write new). With HKDF-from-
    # master, a real rotation means a new master or a bumped Cipher::VERSION; the
    # version tag lets old and new ciphertext coexist while this runs across a
    # tenant's records, so rotation is a lazy re-encrypt, not a stop-the-world
    # migration. Writes an ordinary audited "[encrypted]" update — see
    # lib/tasks/loam.rake (loam:encryption:rotate).
    def loam_reencrypt!
      self.class.loam_encrypted_attributes.each do |name|
        public_send("#{name}=", public_send(name))
      end
      save!
    end
  end
end
