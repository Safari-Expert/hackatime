# frozen_string_literal: true

module SafariExpert
  module EmployeeMonitoring
    class UserScope
      def initialize(search: nil, ids: nil)
        @search = search.to_s.strip
        @ids = Array(ids).filter_map { |value| Integer(value, exception: false) }.uniq
      end

      def relation
        scoped = User.left_outer_joins(:employee_monitoring_profile)
                     .where(
                       "COALESCE(NULLIF(users.github_username, ''), NULLIF(users.username, '')) IS NOT NULL OR employee_monitoring_profiles.id IS NOT NULL"
                     )
                     .where("employee_monitoring_profiles.monitoring_enabled IS DISTINCT FROM FALSE")
                     .includes(:employee_monitoring_profile)
                     .distinct

        scoped = scoped.where(id: @ids) if @ids.any?
        scoped = scoped.search_identity(@search) if @search.present?

        scoped
      end
    end
  end
end
