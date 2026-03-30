# frozen_string_literal: true

module Api
  module Admin
    module V1
      class EmployeeMonitoringController < Api::Admin::ApplicationController
        before_action :set_target_user, only: %i[show_user update_profile]
        before_action :require_schedule_editor!, only: :update_profile

        def summary
          render json: SafariExpert::EmployeeMonitoring::SummaryQuery.new(now: Time.current).call.merge(
            monitoring_path: admin_employee_monitoring_path
          )
        end

        def overview
          render json: SafariExpert::EmployeeMonitoring::OverviewQuery.new(
            now: Time.current,
            search: params[:search],
            status: params[:status]
          ).call
        end

        def show_user
          render json: SafariExpert::EmployeeMonitoring::UserDetailQuery.new(user: @target_user, now: Time.current).call
        end

        def update_profile
          profile = SafariExpert::EmployeeMonitoring::ProfileUpdater.new(
            user: @target_user,
            params: profile_params
          ).call

          render json: {
            success: true,
            profile: {
              monitoring_enabled: profile.monitoring_enabled,
              timezone_override: profile.timezone_override,
              effective_timezone: profile.effective_timezone(@target_user),
              expected_start_minute_local: profile.expected_start_minute_local,
              expected_end_minute_local: profile.expected_end_minute_local,
              workdays: profile.normalized_workdays,
              start_grace_minutes: profile.start_grace_minutes,
              end_grace_minutes: profile.end_grace_minutes,
              label: profile.schedule_label(user: @target_user)
            }
          }
        rescue ActiveRecord::RecordInvalid => e
          render json: { error: e.record.errors.full_messages.to_sentence }, status: :unprocessable_entity
        end

        private

        def set_target_user
          @target_user = User.find(params[:id])
        end

        def require_schedule_editor!
          return if current_user&.admin_level.in?(%w[admin superadmin])

          render_forbidden
        end

        def profile_params
          profile_payload.permit(
            :monitoring_enabled,
            :timezone_override,
            :expected_start_minute_local,
            :expected_end_minute_local,
            :start_grace_minutes,
            :end_grace_minutes,
            workdays: []
          )
        end

        def profile_payload
          source = params[:profile] || params[:payload] || params
          return source if source.is_a?(ActionController::Parameters)

          ActionController::Parameters.new(source.to_h)
        end
      end
    end
  end
end
