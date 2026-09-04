module Loam
  # Files on a record, via ActiveStorage:
  #
  #   equipment.files.attach(io: File.open(path), filename: "manual.pdf")
  #   equipment.files.each { |file| url_for(file) }
  #
  # KNOWN BOUNDARY: ActiveStorage blobs live in global tables that Loam does
  # NOT tenant-scope. The association is scoped (a record only ever lists its
  # own files, and the record is tenant-scoped), but a signed blob URL is a
  # bearer capability: whoever holds the link can fetch the file, with no
  # tenant check. Gate access at the record — through its policy — and treat
  # attachment URLs as secrets rather than as addresses.
  module Attachable
    extend ActiveSupport::Concern

    included do
      unless respond_to?(:has_many_attached)
        raise Loam::Error,
              "#{name} includes Loam::Attachable but ActiveStorage is not available. " \
              "Run `bin/rails active_storage:install && bin/rails db:migrate`, or remove the include " \
              "(this app was probably generated with --skip-active-storage)."
      end

      has_many_attached :files
    end
  end
end
