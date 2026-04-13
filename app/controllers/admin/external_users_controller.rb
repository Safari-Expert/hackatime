# frozen_string_literal: true

class Admin::ExternalUsersController < Admin::BaseController
  before_action :authenticate_external_user_manager!
  before_action :set_external_user, only: [ :update, :destroy ]

  def index
    @external_user = build_external_user
    load_external_users
  end

  def create
    @external_user = build_external_user(external_user_params)

    ActiveRecord::Base.transaction do
      @external_user.save!
      @external_user.create_employee_monitoring_profile!
    end

    redirect_to admin_external_users_path, notice: "#{@external_user.display_name} created."
  rescue ActiveRecord::RecordInvalid => e
    @external_user = e.record
    load_external_users
    render :index, status: :unprocessable_entity
  end

  def update
    @external_user.assign_attributes(external_user_update_params.except(:password))
    @external_user.password = external_user_update_params[:password] if external_user_update_params[:password].present?
    @external_user.save!

    redirect_to admin_external_users_path, notice: "#{@external_user.display_name} updated."
  rescue ActiveRecord::RecordInvalid => e
    @external_user = e.record
    load_external_users
    render :index, status: :unprocessable_entity
  end

  def destroy
    display_name = @external_user.display_name
    @external_user.destroy!

    redirect_to admin_external_users_path, notice: "#{display_name} deleted."
  rescue ActiveRecord::RecordNotDestroyed => e
    redirect_to admin_external_users_path, alert: e.record.errors.full_messages.to_sentence
  end

  private

  def authenticate_external_user_manager!
    redirect_to root_path, alert: "You are not authorized to manage external collaborators." unless current_user&.admin_level.in?(%w[admin superadmin])
  end

  def set_external_user
    @external_user = User.external_accounts.find(params[:id])
  end

  def load_external_users
    @external_users = User.external_accounts.includes(:employee_monitoring_profile).to_a.sort_by do |user|
      [ user.display_name.to_s.downcase, user.username.to_s.downcase ]
    end
  end

  def build_external_user(attributes = {})
    user = User.new({ account_kind: :external, timezone: "UTC" }.merge(attributes))
    user.password = attributes[:password] if attributes[:password].present?
    user
  end

  def external_user_params
    params.require(:external_user).permit(:display_name_override, :username, :password, :timezone)
  end

  def external_user_update_params
    params.require(:external_user).permit(:display_name_override, :username, :password, :timezone)
  end
end
