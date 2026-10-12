class CreateLedgerEntries < ActiveRecord::Migration[8.1]
  def change
    create_table :ledger_entries do |t|
      t.bigint :account_id, null: false
      t.string :entry_type, null: false
      t.integer :amount_cents, null: false
      t.date :posted_on, null: false
      t.string :memo
      t.timestamps
    end
    add_index :ledger_entries, [:account_id, :posted_on]
  end
end
