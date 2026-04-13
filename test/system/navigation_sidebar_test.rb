require "application_system_test_case"

class NavigationSidebarTest < ApplicationSystemTestCase
  test "signed-in users land on employee monitoring and the main nav is decluttered" do
    user = User.create!(timezone: "UTC", username: "nav-regular-user")

    sign_in_as(user)
    visit root_path

    assert_current_path employee_monitoring_path, ignore_query: true
    assert_text "Employee Monitoring"

    within "aside[data-nav-target='nav'] nav" do
      assert_link "Employee Monitoring"
      assert_link "Settings"
      assert_no_link "Home"
      assert_no_link "Docs"
      assert_no_link "Extensions"
      assert_no_link "My OAuth Apps"
    end
  end

  test "superadmin nav keeps only the remaining admin links" do
    superadmin = User.create!(timezone: "UTC", admin_level: "superadmin", username: "nav-superadmin")

    sign_in_as(superadmin)
    visit employee_monitoring_path

    within "aside[data-nav-target='nav'] nav" do
      assert_link "Employee Monitoring"
      assert_link "Review Timeline"
      assert_link "GoodBoy"
      assert_no_link "Trust Level Logs"
      assert_no_link "Admin API Keys"
      assert_no_link "Admin Management"
      assert_no_link "Account Deletions"
      assert_no_link "All OAuth Apps"
      assert_no_link "Feature Flags"
    end
  end
end
