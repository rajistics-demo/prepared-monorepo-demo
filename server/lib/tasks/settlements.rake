namespace :settlements do
  desc "Post one processor settlement day into the ledger: bin/rails settlements:post[2025-03-14]"
  task :post, [:day] => :environment do |_, args|
    day = Settlements::DayFile.for(args.fetch(:day))
    puts "posted #{Settlements::LedgerPoster.new(day).post!} ledger entries for #{day.date}"
  end

  desc "Reconcile one settlement day against the ledger; exits 1 on mismatch: bin/rails settlements:reconcile[2025-03-14]"
  task :reconcile, [:day] => :environment do |_, args|
    r = Settlements::Reconciliation.new(args.fetch(:day)).call
    puts format("%<status>s %<day>s processor_net_cents=%<p>d ledger_net_cents=%<l>d difference_cents=%<d>d entries=%<n>d",
                status: r.matched? ? "MATCH" : "MISMATCH", day: r.settled_on, p: r.processor_net_cents,
                l: r.ledger_net_cents, d: r.difference_cents, n: r.ledger_entries)
    exit 1 unless r.matched?
  end
end
