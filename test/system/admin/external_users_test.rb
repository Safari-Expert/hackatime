require "application_system_test_case"

class Admin::ExternalUsersTest < ApplicationSystemTestCase
  test "superadmin can create an external user from settings and open schedule editing" do
    superadmin = User.create!(timezone: "UTC", admin_level: "superadmin", username: "settings-ext-admin")

    sign_in_as(superadmin)
    visit my_settings_profile_path

    click_link "External Collaborators"

    assert_text "External Collaborators"
    fill_in "Display name", with: "Warehouse Shift"
    fill_in "Username", with: "warehouse-shift"
    fill_in "Password", with: "supersecure123"
    select "UTC", from: "Timezone"
    click_button "Create external user"

    assert_text "Warehouse Shift"
    assert_text "@warehouse-shift"
    click_link "Edit schedule"

    assert_current_path employee_monitoring_path, ignore_query: true
    assert_text "SELECTED EXTERNAL COLLABORATOR"
    assert_text "Warehouse Shift"
    assert_text "EDIT SCHEDULE"
  end
end
