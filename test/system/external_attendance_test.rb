require "application_system_test_case"

class ExternalAttendanceTest < ApplicationSystemTestCase
  test "external user can sign in and clock in and out" do
    user = User.create!(
      timezone: "UTC",
      account_kind: :external,
      display_name_override: "External Worker",
      username: "external-system-user",
      password: "supersecure123"
    )
    user.create_employee_monitoring_profile!

    visit signin_path

    fill_in "Username", with: user.username
    fill_in "Password", with: "supersecure123"
    click_button "Sign in with username"

    assert_text "EXTERNAL ATTENDANCE"
    assert_text "Clock in"
    assert_includes find("[data-app-shell]")[:class], "max-w-[1800px]"
    assert_includes find("[data-external-attendance-shell]")[:class], "max-w-[1600px]"

    travel_to Time.utc(2026, 4, 13, 9, 0, 0) do
      click_button "Clock in"
    end

    assert_text "clocked in"
    assert_text "Started"

    travel_to Time.utc(2026, 4, 13, 17, 0, 0) do
      click_button "Clock out"
    end

    assert_text "clocked out"
    assert_text "8h"
  end
end
