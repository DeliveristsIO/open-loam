module Loam
  # CSV formula-injection defense. A cell whose value starts with =, +, -, @, or
  # a tab/CR is treated as a FORMULA by Excel/Google Sheets when the file is
  # opened — so `=cmd|...` or `=HYPERLINK(...)` in imported/exported data can run.
  # Prefixing such a value with a single quote neutralizes it while leaving the
  # visible text intact. Applied on every CSV cell Loam writes (export + the
  # import error file).
  module Csv
    DANGEROUS = /\A[=+\-@\t\r]/

    module_function

    def safe(value)
      string = value.to_s
      string.match?(DANGEROUS) ? "'#{string}" : value
    end
  end
end
