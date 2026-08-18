require "test_helper"
require "erb"

# Static checks on the generators themselves.
#
# These run in milliseconds and catch the failure modes that would otherwise
# only show up halfway through the slow smoke test: a template that was renamed
# without updating the generator, or an unbalanced ERB tag. They assert
# structure, never the text inside a template — templates are meant to change.
class GeneratorTemplatesTest < Minitest::Test
  GENERATORS = {
    "loam:install" => File.join(LoamHarness::GEM_ROOT, "lib/generators/loam/install"),
    "loam:entity" => File.join(LoamHarness::GEM_ROOT, "lib/generators/loam/entity")
  }.freeze

  def test_both_generators_are_present_with_a_templates_directory
    GENERATORS.each do |name, dir|
      generator = Dir[File.join(dir, "*_generator.rb")]
      assert_equal 1, generator.size, "expected exactly one generator file for #{name} in #{dir}"
      assert File.directory?(File.join(dir, "templates")),
             "#{name} has no templates/ directory — source_root would resolve to nothing"
    end
  end

  # Every `template "x", ...` / `migration_template "x", ...` names a file
  # relative to source_root. If it does not exist the generator dies partway
  # through, leaving the host app half-installed.
  def test_every_template_referenced_by_a_generator_exists_on_disk
    GENERATORS.each do |name, dir|
      source = File.read(Dir[File.join(dir, "*_generator.rb")].first)
      referenced = source.scan(/\b(?:migration_)?template\s+"([^"]+)"/).flatten

      refute_empty referenced, "#{name} does not reference any templates — did the parser or the generator change?"

      missing = referenced.reject { |rel| File.file?(File.join(dir, "templates", rel)) }
      assert_empty missing, "#{name} references templates that do not exist: #{missing.join(', ')}"
    end
  end

  # The reverse direction: an orphaned template is dead weight that reads like
  # a shipped file. Not fatal, but it means the generator and its templates
  # have drifted apart.
  def test_no_template_is_orphaned
    GENERATORS.each do |name, dir|
      source = File.read(Dir[File.join(dir, "*_generator.rb")].first)
      referenced = source.scan(/\b(?:migration_)?template\s+"([^"]+)"/).flatten.to_set

      templates_dir = File.join(dir, "templates")
      on_disk = Dir[File.join(templates_dir, "**", "*")].select { |f| File.file?(f) }
                                                        .map { |f| f.delete_prefix("#{templates_dir}/") }

      orphans = on_disk.reject { |rel| referenced.include?(rel) }
      assert_empty orphans, "#{name} ships templates nothing renders: #{orphans.join(', ')}"
    end
  end

  # Generator templates are run through ERB at generate time. An unbalanced tag
  # (an `<% if %>` with no `<% end %>`, a stray `<%`) blows up mid-generation
  # with a stack trace that points at ERB internals rather than at the file.
  def test_every_template_is_valid_erb
    broken = []

    GENERATORS.each_value do |dir|
      Dir[File.join(dir, "templates", "**", "*")].select { |f| File.file?(f) }.each do |file|
        compiled = ERB.new(File.read(file), trim_mode: "-").src
        RubyVM::InstructionSequence.compile(compiled)
      rescue SyntaxError => e
        broken << "#{file.delete_prefix("#{LoamHarness::GEM_ROOT}/")}: #{e.message.lines.first.strip}"
      end
    end

    assert_empty broken, "templates with invalid ERB:\n  #{broken.join("\n  ")}"
  end

  # The gem is what the generated app depends on, and gemspec.files is a
  # hand-written glob. If it stops matching lib/generators the generators
  # vanish from a packaged release while still working from a path: source —
  # i.e. this harness would stay green and real users would break.
  def test_the_packaged_gem_would_include_the_generators
    gemspec = Gem::Specification.load(File.join(LoamHarness::GEM_ROOT, "loam.gemspec"))
    refute_nil gemspec, "loam.gemspec did not load"

    Dir.chdir(LoamHarness::GEM_ROOT) do
      packaged = gemspec.files.to_set
      GENERATORS.each_value do |dir|
        rel = dir.delete_prefix("#{LoamHarness::GEM_ROOT}/")
        expected = Dir[File.join(rel, "**", "*")].select { |f| File.file?(f) }
        missing = expected.reject { |f| packaged.include?(f) }
        assert_empty missing, "gemspec.files would not ship: #{missing.join(', ')}"
      end
    end
  end
end
