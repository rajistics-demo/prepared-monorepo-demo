class CreateAccounts < ActiveRecord::Migration[8.1]
  def change
    create_table :accounts do |t|
      t.string :name, null: false
      t.string :email, null: false
      t.string :status, null: false, default: "trial"
      t.datetime :last_payment_at
      t.timestamps
    end
    add_index :accounts, :email, unique: true
    add_index :accounts, [:status, :last_payment_at]
  end
end
