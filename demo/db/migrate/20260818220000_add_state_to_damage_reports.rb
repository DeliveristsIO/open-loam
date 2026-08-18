class AddStateToDamageReports < ActiveRecord::Migration[8.1]
  def up
    add_column :damage_reports, :state, :string

    # Existing rows predate the workflow and would fail its inclusion
    # validation on their next save. Backfill them into the initial state.
    execute "UPDATE damage_reports SET state = 'open' WHERE state IS NULL"
  end

  def down
    remove_column :damage_reports, :state
  end
end
