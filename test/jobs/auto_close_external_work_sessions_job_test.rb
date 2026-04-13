require "test_helper"

class AutoCloseExternalWorkSessionsJobTest < ActiveJob::TestCase
  test "closes all open external work sessions at the provided time" do
    user = User.create!(
      timezone: "UTC",
      account_kind: :external,
      display_name_override: "Auto Close",
      username: "auto-close",
      password: "supersecure123"
    )
    session = user.external_work_sessions.create!(started_at: Time.utc(2026, 4, 13, 9, 0, 0))

    AutoCloseExternalWorkSessionsJob.perform_now("2026-04-13T23:59:00Z")

    assert_equal Time.utc(2026, 4, 13, 23, 59, 0), session.reload.ended_at
    assert_equal "auto_closed_eod", session.close_reason
  end
end
