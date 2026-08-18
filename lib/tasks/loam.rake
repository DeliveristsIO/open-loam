namespace :loam do
  desc "Re-run every Loam.on_tenant_created callback for every existing tenant (idempotent)"
  task sync: :environment do
    synced = Loam.sync_tenants!
    puts "loam:sync — ran #{Loam.tenant_created_callbacks.size} tenant callback(s) across #{synced} tenant(s)."
  end
end
