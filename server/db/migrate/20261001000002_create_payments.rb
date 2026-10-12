class CreatePayments < ActiveRecord::Migration[8.1]
  def change
    create_table :payments do |t|
      t.references :account, null: false, foreign_key: true
      t.integer :amount_cents, null: false
      t.datetime :paid_at, null: false
      t.timestamps
    end
  end
end
