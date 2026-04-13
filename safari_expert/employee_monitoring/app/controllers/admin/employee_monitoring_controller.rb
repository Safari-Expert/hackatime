# frozen_string_literal: true

class Admin::EmployeeMonitoringController < InertiaController
  layout "inertia"

  before_action :authenticate_user!
  before_action :set_target_user, only: :update_profile
  before_action :require_schedule_editor!, only: :update_profile

  def show
    if request.path.start_with?("/admin/employee_monitoring")
      redirect_to employee_monitoring_path(request.query_parameters)
      return
    end

    overview = SafariExpert::EmployeeMonitoring::OverviewQuery.new(
      now: Time.current,
      search: params[:search],
      status: params[:status]
    ).call

    selected_user_id = params[:user_id].presence&.to_i || overview[:roster].first&.dig(:id)
    selected_user = selected_user_id ? User.find_by(id: selected_user_id) : nil

    render inertia: "SafariExpert/EmployeeMonitoring/Index", props: {
      page_title: "Employee Monitoring",
      overview: decorate_overview(overview),
      selected_user: selected_user ? decorate_selected_user(selected_user) : nil,
      can_edit_schedule: can_edit_schedule?,
      page_path: employee_monitoring_path
    }
  end

  def update_profile
    SafariExpert::EmployeeMonitoring::ProfileUpdater.new(user: @target_user, params: profile_params).call
    redirect_to employee_monitoring_path(user_id: @target_user.id), notice: "Monitoring schedule updated."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to employee_monitoring_path(user_id: @target_user.id), alert: e.record.errors.full_messages.to_sentence
  end

  private

  def decorate_overview(overview)
    overview.merge(
      roster: overview[:roster].map do |row|
        row.merge(selection_path: employee_monitoring_path(user_id: row[:id]))
      end
    )
  end

  def decorate_selected_user(user)
    payload = SafariExpert::EmployeeMonitoring::UserDetailQuery.new(user: user, now: Time.current).call
    payload[:schedule] = payload[:schedule].merge(
      update_path: admin_employee_monitoring_user_profile_path(id: user.id)
    )
    payload
  end

  def set_target_user
    @target_user = User.find(params[:id])
  end

  def require_schedule_editor!
    redirect_to employee_monitoring_path(user_id: @target_user.id), alert: "You are not authorized to edit monitoring schedules." unless can_edit_schedule?
  end

  def can_edit_schedule?
    current_user&.admin_level.in?(%w[admin superadmin])
  end

  def profile_params
    params.require(:profile).permit(
      :monitoring_enabled,
      :timezone_override,
      :expected_start_minute_local,
      :expected_end_minute_local,
      :start_grace_minutes,
      :end_grace_minutes,
      workdays: []
    )
  end
end
