require "test_helper"

class Admin::ExternalUsersControllerTest < ActionDispatch::IntegrationTest
  test "admins can view and create external users" do
    admin = User.create!(timezone: "UTC", admin_level: "admin", username: "external-admin")
    sign_in_as(admin)

    get admin_external_users_path

    assert_response :success
    assert_select "h1", text: "External Collaborators"

    assert_difference -> { User.external_accounts.count }, 1 do
      post admin_external_users_path, params: {
        external_user: {
          display_name_override: "Shift Worker",
          username: "shift-worker",
          password: "supersecure123",
          timezone: "UTC"
        }
      }
    end

    created_user = User.external_accounts.find_by!(username: "shift-worker")
    assert_redirected_to admin_external_users_path
    assert_not_nil created_user.employee_monitoring_profile
  end

  test "admins can update and delete external users" do
    admin = User.create!(timezone: "UTC", admin_level: "admin", username: "external-admin-2")
    external_user = User.create!(
      timezone: "UTC",
      account_kind: :external,
      display_name_override: "Old Name",
      username: "old-name",
      password: "supersecure123"
    )
    external_user.create_employee_monitoring_profile!
    sign_in_as(admin)

    patch admin_external_user_path(external_user), params: {
      external_user: {
        display_name_override: "New Name",
        username: "new-name",
        password: "newsecure456",
        timezone: "Europe/Paris"
      }
    }

    assert_redirected_to admin_external_users_path
    assert_equal "New Name", external_user.reload.display_name_override
    assert_equal "new-name", external_user.username
    assert_equal "Europe/Paris", external_user.timezone
    assert external_user.authenticate("newsecure456")

    assert_difference -> { User.external_accounts.count }, -1 do
      delete admin_external_user_path(external_user)
    end

    assert_redirected_to admin_external_users_path
  end

  test "viewers cannot access external user management" do
    viewer = User.create!(timezone: "UTC", admin_level: "viewer", username: "external-viewer")
    sign_in_as(viewer)

    get admin_external_users_path

    assert_response :not_found
  end
end
