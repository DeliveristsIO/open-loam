require "test_helper"

# Concurrent-edit safety: optimistic locking (lock_version) is the guarantee,
# advisory Loam::RecordLocks the courtesy.
class LoamRecordLockTest < ActiveSupport::TestCase
  setup do
    @warsaw = Loam::Tenant.create!(name: "Branch Warsaw", slug: "warsaw-lock")
    @krakow = Loam::Tenant.create!(name: "Branch Krakow", slug: "krakow-lock")
    @anna = User.create!(name: "Anna", email: "anna@example.test", password: "password")
    @bob = User.create!(name: "Bob", email: "bob@example.test", password: "password")

    with_tenant(@warsaw) do
      Loam::Membership.create!(user: @anna, role: "manager")
      Loam::Membership.create!(user: @bob, role: "employee")
    end
  end

  test "a stale save raises StaleObjectError instead of clobbering" do
    id = with_tenant(@warsaw) { Equipment.create!(name: "Digger", daily_rate: 100, status: "available").id }

    with_tenant(@warsaw) do
      first = Equipment.find(id)
      second = Equipment.find(id) # same version, loaded independently

      first.update!(name: "First's change")
      assert_raises(ActiveRecord::StaleObjectError) { second.update!(name: "Second's clobber") }
      assert_equal "First's change", Equipment.find(id).name, "the first write stands"
    end
  end

  test "acquire takes a free lock, blocks a second holder, and reports the holder" do
    with_tenant(@warsaw) do
      equipment = Equipment.create!(name: "Digger", daily_rate: 100, status: "available")

      assert Loam::RecordLocks.acquire(equipment, by: @anna)
      assert_nil Loam::RecordLocks.acquire(equipment, by: @bob), "Bob is blocked while Anna holds it"
      assert_equal @anna.id, Loam::RecordLocks.holder(equipment).id
    end
  end

  test "a heartbeat by the same holder extends the TTL" do
    with_tenant(@warsaw) do
      equipment = Equipment.create!(name: "Digger", daily_rate: 100, status: "available")
      first = Loam::RecordLocks.acquire(equipment, by: @anna).expires_at

      travel 1.minute do
        assert Loam::RecordLocks.acquire(equipment, by: @anna).expires_at > first, "re-acquiring extends the lock"
      end
    end
  end

  test "an expired lock is free; release and manager force-release both clear it" do
    with_tenant(@warsaw) do
      equipment = Equipment.create!(name: "Digger", daily_rate: 100, status: "available")
      Loam::RecordLocks.acquire(equipment, by: @anna)

      travel 6.minutes do
        assert Loam::RecordLocks.acquire(equipment, by: @bob), "Bob may take an expired lock"
        assert_equal @bob.id, Loam::RecordLocks.holder(equipment).id

        Loam::RecordLocks.release(equipment, by: @bob)
        assert_nil Loam::RecordLocks.holder(equipment)

        Loam::RecordLocks.acquire(equipment, by: @bob)
        Loam::RecordLocks.force_release(equipment) # manager override
        assert_nil Loam::RecordLocks.holder(equipment)
      end
    end
  end

  test "a lock auto-frees when its record is soft-deleted" do
    with_tenant(@warsaw) do
      equipment = Equipment.create!(name: "Digger", daily_rate: 100, status: "available")
      Loam::RecordLocks.acquire(equipment, by: @anna)

      equipment.soft_delete!

      assert_nil Loam::RecordLocks.holder(equipment), "the lock is gone with the record"
      assert_equal 0, Loam::RecordLock.where(lockable_type: "Equipment", lockable_id: equipment.id).count
    end
  end

  test "record locks are tenant-isolated" do
    warsaw_id = with_tenant(@warsaw) do
      equipment = Equipment.create!(name: "Digger", daily_rate: 100, status: "available")
      Loam::RecordLocks.acquire(equipment, by: @anna)
      equipment.id
    end

    with_tenant(@krakow) do
      assert_equal 0, Loam::RecordLock.count, "Warsaw's lock is invisible from Krakow"
    end
  end
end

# The optimistic-conflict web flow and the advisory-lock take-over.
class AdminRecordLockFlowTest < ActionDispatch::IntegrationTest
  setup do
    @tenant = Loam::Tenant.create!(name: "Branch Warsaw", slug: "warsaw-lock-flow")
    @anna = User.create!(name: "Anna", email: "anna@example.test", password: "password")
    @tomek = User.create!(name: "Tomek", email: "tomek@example.test", password: "password")

    with_tenant(@tenant) do
      Loam::Membership.create!(user: @anna, role: "manager")
      Loam::Membership.create!(user: @tomek, role: "employee")
      @excavator = Equipment.create!(name: "Excavator", daily_rate: 900, status: "available")
    end
  end

  test "a stale update re-renders the conflict with a diff, never a 500 or a clobber" do
    sign_in(@anna)
    get edit_polymorphic_path([:admin, @excavator])
    assert_response :success
    version = @excavator.lock_version # 0 from setup; unchanged by opening the form

    # Someone else saves it in the meantime.
    with_tenant(@tenant) { Equipment.find(@excavator.id).update!(name: "Renamed by someone else") }

    # Our submit carries the now-stale version.
    patch polymorphic_path([:admin, @excavator]),
          params: { equipment: { name: "My change", lock_version: version } }

    assert_response :conflict
    assert_match "changed while you were editing", response.body
    assert_equal "Renamed by someone else", with_tenant(@tenant) { Equipment.find(@excavator.id).name }, "the stale change did not clobber"
  end

  test "a conflict diff shows decrypted values for an encrypted field, never ciphertext" do
    customer = with_tenant(@tenant) { Customer.create!(name: "Acme", email: "a@acme.test", tax_id: "PL-OLD") }
    sign_in(@anna)
    get edit_polymorphic_path([:admin, customer])
    version = customer.lock_version # 0

    with_tenant(@tenant) { Customer.find(customer.id).update!(tax_id: "PL-THEIRS") }

    patch polymorphic_path([:admin, customer]),
          params: { customer: { name: "Acme", email: "a@acme.test", tax_id: "PL-MINE", lock_version: version } }

    assert_response :conflict
    assert_match "PL-THEIRS", response.body, "shows the current (decrypted) value"
    assert_match "PL-MINE", response.body, "shows the attempted (decrypted) value"
    refute_match "v1:", response.body, "never the ciphertext"
  end

  test "a manager sees the lock banner for another editor and can take over; an employee cannot" do
    sign_in(@tomek)
    get edit_polymorphic_path([:admin, @excavator]) # Tomek acquires the lock
    assert_equal @tomek.id, with_tenant(@tenant) { Loam::RecordLocks.holder(@excavator).id }

    sign_in(@anna)
    get edit_polymorphic_path([:admin, @excavator])
    assert_match "Locked by", response.body
    assert_match "Take over", response.body

    delete admin_record_lock_path(lockable_type: "Equipment", lockable_id: @excavator.id)
    assert_response :redirect
    assert_nil with_tenant(@tenant) { Loam::RecordLocks.holder(@excavator) }, "the manager force-released it"
  end

  test "an employee cannot force-release, and a non-entity lockable_type is refused" do
    with_tenant(@tenant) { Loam::RecordLocks.acquire(@excavator, by: @anna) }

    sign_in(@tomek)
    delete admin_record_lock_path(lockable_type: "Equipment", lockable_id: @excavator.id)
    assert_response :forbidden

    sign_in(@anna)
    delete admin_record_lock_path(lockable_type: "User", lockable_id: @tomek.id)
    assert_response :forbidden, "User is not a lockable entity"
  end

  private

  def sign_in(user)
    post admin_session_path, params: { email: user.email, password: "password" }
  end
end
