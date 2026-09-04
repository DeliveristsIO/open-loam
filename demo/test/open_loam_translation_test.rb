require "test_helper"

# Loam::Translatable: per-record, per-locale content overlay over the base column.
class LoamTranslationTest < ActiveSupport::TestCase
  setup do
    @warsaw = Loam::Tenant.create!(name: "Branch Warsaw", slug: "warsaw-trans")
    @krakow = Loam::Tenant.create!(name: "Branch Krakow", slug: "krakow-trans")
    Loam::Current.locale = nil
  end

  teardown { Loam::Current.locale = nil }

  test "a translated field overlays the current locale, falling back to the base column" do
    with_tenant(@warsaw) do
      equipment = Equipment.create!(name: "Excavator", daily_rate: 1, status: "available")
      equipment.set_translation(:name, "de", "Bagger")

      Loam::Current.locale = nil
      assert_equal "Excavator", equipment.name, "no locale -> base"
      Loam::Current.locale = "de"
      assert_equal "Bagger", equipment.name, "de -> the translation"
      Loam::Current.locale = "fr"
      assert_equal "Excavator", equipment.name, "an untranslated locale falls back to the base"
    end
  end

  test "explicit-locale read ignores the current locale" do
    with_tenant(@warsaw) do
      equipment = Equipment.create!(name: "Excavator", daily_rate: 1, status: "available")
      equipment.set_translation(:name, "pl", "Koparka")
      Loam::Current.locale = "de"
      assert_equal "Koparka", equipment.name(locale: "pl")
      assert_equal "Excavator", equipment.name(locale: "en"), "no en translation -> base"
    end
  end

  test "set_translation writes then updates, and the base column is NEVER lost" do
    with_tenant(@warsaw) do
      equipment = Equipment.create!(name: "Excavator", daily_rate: 1, status: "available")
      equipment.set_translation(:name, "de", "Bagger")
      equipment.set_translation(:name, "de", "Löffelbagger") # update
      assert_equal({ "de" => "Löffelbagger" }, equipment.translations_for(:name))
      assert_equal "Excavator", equipment.read_attribute(:name), "the base value is untouched"
    end
  end

  test "translations are request-scoped: switching Loam::Current.locale changes reads" do
    with_tenant(@warsaw) do
      equipment = Equipment.create!(name: "Excavator", daily_rate: 1, status: "available")
      equipment.set_translation(:name, "de", "Bagger")
      equipment.set_translation(:name, "pl", "Koparka")

      Loam::Current.locale = "pl"
      assert_equal "Koparka", equipment.name
      Loam::Current.locale = "de"
      assert_equal "Bagger", equipment.name
    end
  end

  test "a translation is invisible from another tenant" do
    equipment = with_tenant(@warsaw) do
      e = Equipment.create!(name: "Excavator", daily_rate: 1, status: "available")
      e.set_translation(:name, "de", "Bagger")
      e
    end
    with_tenant(@krakow) { assert_equal 0, Loam::Translation.count, "Warsaw's translation is not visible in Krakow" }
    assert_equal 1, with_tenant(@warsaw) { Loam::Translation.where(translatable: equipment).count }
  end

  test "a translation value is unique per (record, locale, field)" do
    with_tenant(@warsaw) do
      equipment = Equipment.create!(name: "Excavator", daily_rate: 1, status: "available")
      equipment.set_translation(:name, "de", "Bagger")
      dup = Loam::Translation.new(translatable: equipment, locale: "de", field: "name", value: "X")
      refute dup.valid?
      assert dup.errors[:field].any?
    end
  end

  test "translating an ENCRYPTED field is refused at class load (no plaintext leak)" do
    error = assert_raises(Loam::Error) do
      Class.new(Loam::TenantRecord) do
        self.table_name = "loam_translations"
        include Loam::Encryptable
        include Loam::Translatable
        encrypts :value
        translates :value
      end
    end
    assert_match(/encrypted/, error.message)
  end

  test "set_translation refuses a non-translatable field" do
    with_tenant(@warsaw) do
      equipment = Equipment.create!(name: "Excavator", daily_rate: 1, status: "available")
      assert_raises(Loam::Error) { equipment.set_translation(:status, "de", "x") }
    end
  end
end

# The per-record translations admin screen + locale switcher.
class AdminTranslationsTest < ActionDispatch::IntegrationTest
  setup do
    @tenant = Loam::Tenant.create!(name: "Branch Warsaw", slug: "warsaw-trans-admin")
    @mgr = User.create!(name: "Anna", email: "anna@example.test", password: "password")
    @emp = User.create!(name: "Tomek", email: "tomek@example.test", password: "password")
    with_tenant(@tenant) do
      Loam::Membership.create!(user: @mgr, role: "manager")
      Loam::Membership.create!(user: @emp, role: "employee")
      @equipment = Equipment.create!(name: "Excavator", daily_rate: 1, status: "available")
    end
  end

  def sign_in(email)
    post admin_session_path, params: { email: email, password: "password" }
  end

  test "a manager saves per-locale translations" do
    sign_in("anna@example.test")

    patch admin_translations_path, params: {
      translatable_type: "Equipment", translatable_id: @equipment.id,
      translations: { "name" => { "de" => "Bagger", "pl" => "Koparka" } }
    }
    assert_response :redirect
    assert_equal({ "de" => "Bagger", "pl" => "Koparka" }, with_tenant(@tenant) { @equipment.reload.translations_for(:name) })
  end

  test "the locale switcher changes the displayed content" do
    with_tenant(@tenant) { @equipment.set_translation(:name, "de", "Bagger") }
    sign_in("anna@example.test")

    get admin_equipment_index_path(locale: "de")
    assert_match "Bagger", response.body
    get admin_equipment_index_path(locale: "en")
    assert_match "Excavator", response.body
  end

  test "an employee may not manage translations" do
    sign_in("tomek@example.test")
    get admin_translations_path(translatable_type: "Equipment", translatable_id: @equipment.id)
    assert_response :forbidden
  end
end
