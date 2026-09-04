# Bundler auto-requires the gem's name ("open-loam") on load. The library's
# entry point and whole namespace are `open_loam` / `OpenLoam::` — the gem is only
# *distributed* as open-loam (the plain `loam` name is taken on RubyGems). This
# shim bridges the two so `gem "open-loam"` works with the default require.
require_relative "open_loam"
