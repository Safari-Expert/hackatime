require "test_helper"

class SettingsNavigationControllerTest < ActionDispatch::IntegrationTest
  test "profile page includes resource sidebar links for normal users" do
    user = User.create!(timezone: "UTC", username: "settings-nav-user")
    sign_in_as(user)

    get my_settings_profile_path

    assert_response :success
    groups = inertia_page.dig("props", "sidebar_link_groups")
    assert_equal [ "Resources" ], groups.map { |group| group["title"] }
    assert_equal [ "Docs", "Extensions", "My OAuth Apps" ],
      groups.first.fetch("items").map { |item| item["label"] }
  end

  test "profile page includes admin sidebar links for superadmins" do
    user = User.create!(timezone: "UTC", admin_level: "superadmin", username: "settings-superadmin")
    DeletionRequest.create_for_user!(User.create!(timezone: "UTC", username: "pending-delete"))
    sign_in_as(user)

    get my_settings_profile_path

    assert_response :success
    groups = inertia_page.dig("props", "sidebar_link_groups")
    admin_group = groups.find { |group| group["title"] == "Admin" }

    assert_not_nil admin_group
    assert_equal [ "Admin API Keys", "External Collaborators", "Admin Management", "Account Deletions" ],
      admin_group.fetch("items").map { |item| item["label"] }
    assert_equal 1, admin_group.fetch("items").last["badge"]
  end
end
