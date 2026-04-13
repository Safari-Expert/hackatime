class AutoCloseExternalWorkSessionsJob < ApplicationJob
  queue_as :default

  def perform(reference_time = Time.current.iso8601)
    closed_at = Time.iso8601(reference_time.to_s)

    ExternalWorkSession.open.find_each do |session|
      session.update!(
        ended_at: closed_at,
        close_reason: :auto_closed_eod
      )
    end
  end
end
