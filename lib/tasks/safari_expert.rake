namespace :safari_expert do
  desc "Create or refresh the Safari Expert bootstrap admin, API keys, and sign-in URL"
  task bootstrap_admin: :environment do
    email = ENV.fetch("SAFARI_EXPERT_BOOTSTRAP_ADMIN_EMAIL").downcase
    username = ENV.fetch("SAFARI_EXPERT_BOOTSTRAP_ADMIN_USERNAME", email.split("@").first)
    timezone = ENV.fetch("SAFARI_EXPERT_BOOTSTRAP_ADMIN_TIMEZONE", "Africa/Nairobi")
    admin_key_name = ENV.fetch("SAFARI_EXPERT_BOOTSTRAP_ADMIN_API_KEY_NAME", "Safari Expert Internal UI")
    user_key_name = ENV.fetch("SAFARI_EXPERT_BOOTSTRAP_USER_API_KEY_NAME", "Safari Expert WakaTime")
    sign_in_token_ttl_days = ENV.fetch("SAFARI_EXPERT_BOOTSTRAP_SIGN_IN_TTL_DAYS", "365").to_i
    base_url = ENV.fetch("APP_HOST")
    base_url = "https://#{base_url}" unless base_url.start_with?("http://", "https://")

    user = ActiveRecord::Base.transaction do
      existing_email = EmailAddress.includes(:user).find_by(email: email)
      admin = existing_email&.user || User.create!
      admin.update!(
        username: username,
        timezone: timezone,
      )
      admin.set_admin_level(:superadmin)

      email_address = admin.email_addresses.find_or_initialize_by(email: email)
      email_address.source = :signing_in if email_address.new_record? || email_address.source.nil?
      email_address.save!

      admin
    end

    admin_api_key = user.admin_api_keys.find_or_create_by!(name: admin_key_name)
    user_api_key = user.api_keys.find_or_create_by!(name: user_key_name)

    sign_in_token = user.sign_in_tokens
      .where(auth_type: :email, used_at: nil, continue_param: nil)
      .where("expires_at > ?", 30.days.from_now)
      .order(expires_at: :desc)
      .first

    sign_in_token ||= user.sign_in_tokens.create!(
      auth_type: :email,
      expires_at: sign_in_token_ttl_days.days.from_now,
    )

    sign_in_url = "#{base_url}#{Rails.application.routes.url_helpers.auth_token_path(sign_in_token.token)}"

    puts "Safari Expert bootstrap admin ready"
    puts "  Username: #{user.username}"
    puts "  Email: #{email}"
    puts "  Admin API Key: #{admin_api_key.token}"
    puts "  User API Key: #{user_api_key.token}"
    puts "  Sign-in URL: #{sign_in_url}"
    puts "  Sign-in URL Expires At: #{sign_in_token.expires_at.iso8601}"
  end
end
