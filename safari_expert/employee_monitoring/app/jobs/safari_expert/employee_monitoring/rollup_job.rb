class SafariExpert::EmployeeMonitoring::RollupJob < ApplicationJob
  queue_as :latency_5m

  def perform
    SafariExpert::EmployeeMonitoring::UserScope.new.relation.find_each do |user|
      SafariExpert::EmployeeMonitoring::RollupBuilder.new(user: user, now: Time.current, persist: true).call
    rescue StandardError => e
      report_error(e, message: "[EmployeeMonitoring] Failed to build rollup for user ##{user.id}")
    end
  end
end
