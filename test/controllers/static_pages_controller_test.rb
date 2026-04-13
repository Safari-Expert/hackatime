require "test_helper"

class StaticPagesControllerTest < ActionDispatch::IntegrationTest
  test "root redirects signed-in users to employee monitoring" do
    user = User.create!(timezone: "UTC", username: "redirected-root-user")
    sign_in_as(user)

    get root_path

    assert_response :redirect
    assert_redirected_to employee_monitoring_path
  end

  test "root renders the public signed-out homepage for guests" do
    get root_path

    assert_response :success
    assert_inertia_component "Home/SignedOut"
  end
end
