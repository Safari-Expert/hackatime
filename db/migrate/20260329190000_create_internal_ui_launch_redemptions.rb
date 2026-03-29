class CreateInternalUiLaunchRedemptions < ActiveRecord::Migration[8.1]
  def change
    create_table :internal_ui_launch_redemptions do |t|
      t.string :jti, null: false
      t.string :audience, null: false
      t.string :github_uid, null: false
      t.datetime :expires_at, null: false

      t.timestamps
    end

    add_index :internal_ui_launch_redemptions, :jti, unique: true
    add_index :internal_ui_launch_redemptions, :expires_at
  end
end
