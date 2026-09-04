module Loam
  # Primary-key generation for tables whose key is not an integer.
  #
  # Rails leaves key generation to the database, which works for integer keys
  # (a sequence or AUTOINCREMENT) and for uuid columns on Postgres, where
  # create_table installs a gen_random_uuid() default. A *string* primary key
  # has neither: the INSERT sends NULL and the row is rejected or lands with an
  # empty key.
  #
  # Loam's tables follow the host app's key type (see
  # Loam::Generators::PrimaryKeyOptions), so on a string-keyed app every Loam
  # model needs its key generated in Ruby. Before this, hosts patched it in
  # themselves with a global before_create on ActiveRecord::Base — a lot to ask
  # of an app whose only deviation was not using bigints, and a hook broad
  # enough to reach models that had nothing to do with Loam.
  #
  # Integer keys take the early return, so nothing changes for the default app.
  module GeneratedKey
    def self.included(base)
      base.before_create :assign_loam_generated_key
    end

    private

    def assign_loam_generated_key
      key = self.class.primary_key
      return if key.nil?             # a join table declared with id: false
      return if self[key].present?   # the caller chose the key

      column = self.class.columns_hash[key]
      return if column.nil?
      return if column.type == :integer   # the database generates this one

      self[key] = SecureRandom.uuid
    end
  end
end
