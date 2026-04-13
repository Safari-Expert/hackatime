require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "theme defaults to gruvbox dark" do
    user = User.new

    assert_equal "gruvbox_dark", user.theme
  end

  test "theme options include all supported themes in order" do
    values = User.theme_options.map { |option| option[:value] }

    assert_equal %w[
      standard
      neon
      catppuccin_mocha
      catppuccin_iced_latte
      gruvbox_dark
      github_dark
      github_light
      nord
      rose
      rose_pine_dawn
    ], values
  end

  test "theme metadata falls back to default for unknown themes" do
    metadata = User.theme_metadata("not-a-real-theme")

    assert_equal "gruvbox_dark", metadata[:value]
  end

  test "flipper id uses the user id" do
    user = User.create!(timezone: "UTC")

    assert_equal "User;#{user.id}", user.flipper_id
  end

  test "active remote heartbeat import run only counts remote imports" do
    user = User.create!(timezone: "UTC")

    assert_not user.active_remote_heartbeat_import_run?

    # An active non-remote (dev_upload) import should not count as a remote import.
    # Use a separate user because the unique index prevents two active imports per user.
    other_user = User.create!(timezone: "UTC")
    other_user.heartbeat_import_runs.create!(
      source_kind: :dev_upload,
      state: :queued,
      source_filename: "dev.json"
    )
    assert_not other_user.active_remote_heartbeat_import_run?

    user.heartbeat_import_runs.create!(
      source_kind: :wakatime_dump,
      state: :waiting_for_dump,
      encrypted_api_key: "secret"
    )

    assert user.active_remote_heartbeat_import_run?
  end

  test "external accounts require username and password and use display name override" do
    user = User.new(
      timezone: "UTC",
      account_kind: :external,
      display_name_override: "Pat Contractor"
    )

    assert_not user.valid?
    assert_includes user.errors[:username], "can't be blank"
    assert_includes user.errors[:password], "can't be blank"

    user.username = "pat-contractor"
    user.password = "supersecure123"

    assert user.valid?
    assert_equal "Pat Contractor", user.display_name
    assert user.authenticate("supersecure123")
    assert_not user.authenticate("wrong-password")
  end
end
