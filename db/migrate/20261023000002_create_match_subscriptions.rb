class CreateMatchSubscriptions < ActiveRecord::Migration[8.1]
  def change
    create_table :match_subscriptions do |t|
      t.references :match, null: false, foreign_key: true
      t.references :subscription, null: false, foreign_key: true
    end

    add_index :match_subscriptions, %i[match_id subscription_id],
              unique: true, name: "idx_match_subs_uniq"
  end
end
