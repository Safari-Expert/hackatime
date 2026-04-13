class SessionsController < ApplicationController
  skip_forgery_protection only: :internal_ui_redeem

  def hca_new
    session[:return_data] = { "url" => safe_return_url(params[:continue].presence) } if params[:continue].present?
    Rails.logger.info("Sessions return data: #{session[:return_data]}")
    redirect_uri = url_for(action: :hca_create, only_path: false)

    redirect_to User.hca_authorize_url(redirect_uri),
      host: "https://auth.hackclub.com",
      allow_other_host: "https://auth.hackclub.com"
  end

  def hca_create
    if params[:error].present?
      if params[:error] == "access_denied"
        redirect_to root_path, alert: "Sign in cancelled"
        return
      end

      report_message("HCA OAuth error: #{params[:error]}")
      redirect_to root_path, alert: "Failed to authenticate with Hack Club Auth. Error ID: #{Sentry.last_event_id}"
      return
    end

    redirect_uri = url_for(action: :hca_create, only_path: false)

    @user = User.from_hca_token(params[:code], redirect_uri)

    if @user&.persisted?
      session[:user_id] = @user.id

      PosthogService.identify(@user)
      PosthogService.capture(@user, "user_signed_in", { method: "hca" })

      if @user.previously_new_record?
        redirect_to my_wakatime_setup_path, notice: "Successfully signed in with Hack Club Auth! Welcome!"
      elsif session[:return_data]&.dig("url").present?
        return_url = session[:return_data].delete("url")
        redirect_to return_url, notice: "Successfully signed in with Hack Club Auth! Welcome!"
      else
        redirect_to root_path, notice: "Successfully signed in with Hack Club Auth! Welcome!"
      end
    else
      redirect_to root_path, alert: "Failed to authenticate with Hack Club Auth!"
    end
  end

  def slack_new
    redirect_uri = url_for(action: :slack_create, only_path: false)
    oauth_nonce = SecureRandom.hex(24)
    session[:slack_oauth_state_nonce] = oauth_nonce
    state_payload = {
      token: oauth_nonce,
      close_window: params[:close_window].present?,
      continue: params[:continue]
    }.to_json

    Rails.logger.info "Starting Slack OAuth flow with redirect URI: #{redirect_uri}"
    redirect_to User.slack_authorize_url(redirect_uri, state: state_payload),
                host: "https://slack.com",
                allow_other_host: "https://slack.com"
  end

  def slack_create
    redirect_uri = url_for(action: :slack_create, only_path: false)

    if params[:error].present?
      if params[:error] == "access_denied"
        redirect_to root_path, alert: "Sign in cancelled"
        return
      end

      report_message("Slack OAuth error: #{params[:error]}")
      redirect_to root_path, alert: "Failed to authenticate with Slack. Error ID: #{Sentry.last_event_id}"
      return
    end

    slack_state = parse_slack_state(params[:state])
    unless valid_oauth_state?(provider: "Slack", session_key: :slack_oauth_state_nonce, received_nonce: slack_state&.dig("token"))
      redirect_to root_path, alert: "Failed to authenticate with Slack"
      return
    end

    @user = User.from_slack_token(params[:code], redirect_uri)

    if @user&.persisted?
      session[:user_id] = @user.id

      PosthogService.identify(@user)
      PosthogService.capture(@user, "user_signed_in", { method: "slack" })

      if slack_state&.dig("close_window")
        redirect_to close_window_path
      elsif @user.previously_new_record?
        session[:return_data] = { "url" => safe_return_url(slack_state&.dig("continue").presence) }
        redirect_to my_wakatime_setup_path, notice: "Successfully signed in with Slack! Welcome!"
      elsif slack_state&.dig("continue").present? && safe_return_url(slack_state["continue"]).present?
        redirect_to safe_return_url(slack_state["continue"]), notice: "Successfully signed in with Slack! Welcome!"
      else
        redirect_to root_path, notice: "Successfully signed in with Slack! Welcome!"
      end
    else
      report_message("Failed to create/update user from Slack data")
      redirect_to root_path, alert: "Failed to sign in with Slack"
    end
  end

  def close_window
    render :close_window, layout: false
  end

  def github_new
    unless current_user
      redirect_to root_path, alert: "Please sign in first to link your GitHub account"
      return
    end

    redirect_uri = url_for(action: :github_create, only_path: false)
    oauth_nonce = SecureRandom.hex(24)
    session[:github_oauth_state_nonce] = oauth_nonce
    Rails.logger.info "Starting GitHub OAuth flow with redirect URI: #{redirect_uri}"
    redirect_to User.github_authorize_url(redirect_uri, state: oauth_nonce),
                allow_other_host: "https://github.com"
  end

  def github_create
    unless current_user
      redirect_to root_path, alert: "Please sign in first to link your GitHub account"
      return
    end

    redirect_uri = url_for(action: :github_create, only_path: false)

    if params[:error].present?
      report_message("GitHub OAuth error: #{params[:error]}")
      redirect_to my_settings_path, alert: "Failed to authenticate with GitHub. Error ID: #{Sentry.last_event_id}"
      return
    end

    unless valid_oauth_state?(provider: "GitHub", session_key: :github_oauth_state_nonce, received_nonce: params[:state])
      redirect_to my_settings_path, alert: "Failed to link GitHub account"
      return
    end

    @user = User.from_github_token(params[:code], redirect_uri, current_user)

    if @user&.persisted?
      PosthogService.capture(@user, "github_linked")
      redirect_to my_settings_path, notice: "Successfully linked GitHub account!"
    else
      report_message("Failed to link GitHub account")
      redirect_to my_settings_path, alert: "Failed to link GitHub account"
    end
  end

  def github_unlink
    unless current_user
      redirect_to root_path, alert: "Please sign in first"
      return
    end

    current_user.update!(github_access_token: nil, github_uid: nil, github_username: nil)
    Rails.logger.info "GitHub account unlinked for User ##{current_user.id}"
    redirect_to my_settings_path, notice: "GitHub account unlinked successfully"
  end

  def email
    email = params[:email].downcase
    continue_param = params[:continue]

    if Rails.env.production?
      HandleEmailSigninJob.perform_later(email, continue_param)
    else
      token = HandleEmailSigninJob.perform_now(email, continue_param)
      session[:dev_magic_link] = auth_token_url(token)
    end

    redirect_path = params[:redirect_to] == "signin" ? signin_path(sign_in_email: true) : root_path(sign_in_email: true)
    redirect_to redirect_path, notice: "Check your email for a sign-in link!"
  end

  def external
    username = params[:username].to_s.strip
    password = params[:password].to_s
    continue_param = safe_return_url(params[:continue].presence)
    external_user = User.find_by("LOWER(username) = ?", username.downcase)

    unless external_user&.account_kind_external? && external_user.authenticate(password)
      redirect_to signin_path(continue: continue_param), alert: "Invalid username or password"
      return
    end

    session[:user_id] = external_user.id

    PosthogService.identify(external_user)
    PosthogService.capture(external_user, "user_signed_in", { method: "external_password" })

    redirect_to(continue_param.presence || employee_monitoring_path, notice: "Successfully signed in.")
  end

  def add_email
    unless current_user
      redirect_to root_path, alert: "Please sign in first to add an email"
      return
    end

    email = params[:email].downcase

    if EmailAddress.exists?(email: email)
      redirect_to my_settings_path, alert: "This email is already associated with an account"
      return
    end

    if EmailVerificationRequest.exists?(email: email)
      redirect_to my_settings_path, alert: "This email is already pending verification"
      return
    end

    verification_request = current_user.email_verification_requests.create!(
      email: email
    )

    if Rails.env.production?
      EmailVerificationMailer.verify_email(verification_request).deliver_later
    else
      EmailVerificationMailer.verify_email(verification_request).deliver_now
    end

    redirect_to my_settings_path, notice: "Check your email to verify the new address!"
  rescue ActiveRecord::RecordInvalid => e
    redirect_to my_settings_path, alert: "Failed to add email: #{e.record.errors.full_messages.join(', ')}"
  end

  def unlink_email
    unless current_user
      redirect_to root_path, alert: "Please sign in first to unlink an email"
      return
    end

    email = params[:email].downcase

    email_record = current_user.email_addresses.find_by(
      email: email
    )

    unless email_record
      redirect_to my_settings_path, alert: "Email must exist to be unlinked"
      return
    end

    unless current_user.can_delete_email_address?(email_record)
      redirect_to my_settings_path, alert: "Email must be registered for signing in to unlink"
      return
    end

    email_verification_request = current_user.email_verification_requests.find_by(
      email: email
    )

    email_record.destroy!
    email_verification_request&.destroy

    redirect_to my_settings_path, notice: "Email unlinked!"
  rescue ActiveRecord::RecordNotDestroyed => e
    redirect_to my_settings_path, alert: "Failed to unlink email: #{e.record.errors.full_messages.join(', ')}"
  end

  def token
    verification_request = EmailVerificationRequest.valid.find_by(token: params[:token])

    if verification_request
      verification_request.verify!
      redirect_to my_settings_path, notice: "Successfully verified your email address!"
      return
    end

    # If no verification request found, try the old sign-in token system
    valid_token = SignInToken.where(token: params[:token], used_at: nil)
                            .where("expires_at > ?", Time.current)
                            .first

    if valid_token
      valid_token.mark_used!
      session[:user_id] = valid_token.user_id
      session[:return_data] = valid_token.return_data || {}

      user = User.find(valid_token.user_id)
      PosthogService.identify(user)
      PosthogService.capture(user, "user_signed_in", { method: "email" })

      if valid_token.continue_param.present? && safe_return_url(valid_token.continue_param).present?
        redirect_to safe_return_url(valid_token.continue_param), notice: "Successfully signed in!"
      else
        redirect_to root_path, notice: "Successfully signed in!"
      end
    else
      redirect_to root_path, alert: "Invalid or expired link"
    end
  end

  def internal_ui_redeem
    claims = InternalUiLaunchTokenService.new.decode!(
      params[:launch_token],
      audience: "hackatime"
    )

    unless claims.dig("hackatime", "launch")
      render_internal_ui_launch_error(
        "Launch not allowed",
        "This account does not have Hackatime access.",
        status: :forbidden
      )
      return
    end

    consumed = InternalUiLaunchRedemption.consume!(
      jti: claims.fetch("jti"),
      audience: claims.fetch("aud"),
      github_uid: claims.fetch("sub"),
      expires_at: Time.at(claims.fetch("exp")).utc
    )

    unless consumed
      render_internal_ui_launch_error(
        "Launch link already used",
        "Return to Internal UI and open Hackatime again.",
        status: :conflict
      )
      return
    end

    user = upsert_internal_ui_user!(claims)
    apply_internal_ui_admin_level!(user, claims.dig("hackatime", "admin_level"))

    session[:user_id] = user.id

    redirect_to safe_return_url(claims["next"]).presence || root_path,
                notice: "Successfully signed in from Internal UI!"
  rescue InternalUiLaunchTokenService::ConfigurationError
    render_internal_ui_launch_error(
      "Launch unavailable",
      "Hackatime trusted launch is not configured.",
      status: :service_unavailable
    )
  rescue InternalUiLaunchTokenService::InvalidTokenError => e
    Rails.logger.warn("Invalid Internal UI launch token: #{e.message}")
    render_internal_ui_launch_error(
      "Launch denied",
      "The trusted launch token is invalid or expired.",
      status: :unauthorized
    )
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
    Rails.logger.error("Failed to redeem Internal UI launch: #{e.class} #{e.message}")
    render_internal_ui_launch_error(
      "Sign-in failed",
      "Hackatime could not create the requested session.",
      status: :unprocessable_entity
    )
  end

  def impersonate
    unless current_user && current_user.admin_level.in?([ "admin", "superadmin" ])
      redirect_to root_path, alert: "You are not authorized to impersonate users"
      return
    end

    user = User.find_by(id: params[:id])
    unless user
      redirect_to root_path, alert: "who?"
      return
    end

    if user.admin_level == "superadmin"
      redirect_to root_path, alert: "nice try, you cant do that"
      return
    end
    if user.admin_level == "admin" && current_user.admin_level != "superadmin"
      redirect_to root_path, alert: "nice try, you cant do that"
      return
    end

    session[:impersonater_user_id] ||= current_user.id
    session[:user_id] = user.id
    redirect_to root_path, notice: "Impersonating #{user.display_name}"
  end

  def stop_impersonating
    session[:user_id] = session[:impersonater_user_id]
    session[:impersonater_user_id] = nil
    redirect_to root_path, notice: "Stopped impersonating"
  end

  def destroy
    PosthogService.capture(session[:user_id], "user_signed_out") if session[:user_id]
    session[:user_id] = nil
    session[:impersonater_user_id] = nil
    redirect_to root_path, notice: "Signed out!"
  end

  private

  def parse_slack_state(raw_state)
    JSON.parse(raw_state)
  rescue JSON::ParserError, TypeError
    nil
  end

  def valid_oauth_state?(provider:, session_key:, received_nonce:)
    expected_nonce = session.delete(session_key)

    if expected_nonce.blank? || received_nonce.blank?
      report_message("#{provider} OAuth state missing expected=#{expected_nonce.present?} received=#{received_nonce.present?}")
      return false
    end

    return true if ActiveSupport::SecurityUtils.secure_compare(received_nonce.to_s, expected_nonce.to_s)

    report_message("#{provider} OAuth state mismatch")
    false
  end

  def upsert_internal_ui_user!(claims)
    github_uid = claims.fetch("sub").to_s
    email = claims.fetch("email").to_s.downcase
    github_login = claims.fetch("github_login").to_s.strip.presence
    avatar_url = claims["avatar_url"].to_s.strip.presence

    user = User.find_by(github_uid: github_uid)
    user ||= EmailAddress.find_by(email: email)&.user
    user ||= User.new

    if user.new_record?
      username = resolve_internal_ui_username(github_login)
      user.username = username if username.present?
    end

    user.github_uid = github_uid
    user.github_username = github_login if github_login.present?
    user.github_avatar_url = avatar_url if avatar_url.present?
    user.save!

    attach_internal_ui_email!(user, email) if email.present?
    user
  end

  def resolve_internal_ui_username(candidate)
    return nil if candidate.blank?

    existing_user = User.find_by("LOWER(username) = ?", candidate.downcase)
    return candidate unless existing_user

    nil
  end

  def attach_internal_ui_email!(user, email)
    email_record = EmailAddress.find_by(email: email)
    if email_record && email_record.user_id != user.id
      Rails.logger.warn(
        "Internal UI launch email #{email} belongs to User ##{email_record.user_id}; " \
        "keeping existing ownership while signing in User ##{user.id}"
      )
      return
    end

    email_record ||= user.email_addresses.build(email: email)
    email_record.user = user
    email_record.source = :github
    email_record.save! if email_record.new_record? || email_record.changed?
  end

  def apply_internal_ui_admin_level!(user, requested_level)
    normalized_level = requested_level.to_s.presence
    return if normalized_level.blank?
    return unless User.admin_levels.key?(normalized_level)

    user.set_admin_level(normalized_level)
  end

  def render_internal_ui_launch_error(title, message, status:)
    render html: <<~HTML.html_safe, status: status
      <!doctype html>
      <html lang="en">
        <head>
          <meta charset="utf-8" />
          <meta name="viewport" content="width=device-width, initial-scale=1" />
          <title>#{ERB::Util.html_escape(title)}</title>
        </head>
        <body>
          <main style="font-family: system-ui, sans-serif; max-width: 28rem; margin: 12vh auto; padding: 2rem; border: 1px solid #d4d4d8; border-radius: 1rem;">
            <h1 style="margin: 0 0 0.75rem;">#{ERB::Util.html_escape(title)}</h1>
            <p style="margin: 0; color: #52525b;">#{ERB::Util.html_escape(message)}</p>
          </main>
        </body>
      </html>
    HTML
  end
end
