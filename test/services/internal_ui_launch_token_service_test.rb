require "test_helper"

class InternalUiLaunchTokenServiceTest < ActiveSupport::TestCase
  def setup
    @secret = "shared-secret"
    ENV["HACKATIME_INTERNAL_UI_LAUNCH_SHARED_SECRET"] = @secret
  end

  def teardown
    ENV.delete("HACKATIME_INTERNAL_UI_LAUNCH_SHARED_SECRET")
  end

  test "decodes a valid token" do
    service = InternalUiLaunchTokenService.new
    token = build_token(@secret, aud: "hackatime")

    claims = service.decode!(token, audience: "hackatime")

    assert_equal "internal_ui", claims["iss"]
    assert_equal "hackatime", claims["aud"]
    assert_equal "123", claims["sub"]
    assert_equal "alexb", claims["github_login"]
    assert_equal "alexb@example.com", claims["email"]
    assert claims["exp"].to_i > Time.current.to_i
  end

  test "rejects wrong audience" do
    service = InternalUiLaunchTokenService.new
    token = build_token(@secret, aud: "vibe_meister")

    assert_raises(InternalUiLaunchTokenService::InvalidTokenError) do
      service.decode!(token, audience: "hackatime")
    end
  end

  test "rejects expired tokens" do
    service = InternalUiLaunchTokenService.new
    token = build_token(@secret, exp: 10.minutes.ago.to_i)

    assert_raises(InternalUiLaunchTokenService::InvalidTokenError) do
      service.decode!(token, audience: "hackatime")
    end
  end

  test "requires shared secret" do
    ENV["HACKATIME_INTERNAL_UI_LAUNCH_SHARED_SECRET"] = ""
    service = InternalUiLaunchTokenService.new
    token = build_token(@secret)

    assert_raises(InternalUiLaunchTokenService::ConfigurationError) do
      service.decode!(token, audience: "hackatime")
    end
  end

  private

  def build_token(secret, aud: "hackatime", exp: 10.minutes.from_now.to_i)
    header = base64url_json({ alg: "HS256", typ: "JWT" })
    payload = base64url_json(
      iss: "internal_ui",
      aud: aud,
      sub: "123",
      github_login: "alexb",
      email: "alexb@example.com",
      jti: SecureRandom.uuid,
      exp: exp
    )
    signing_input = "#{header}.#{payload}"
    signature = Base64.urlsafe_encode64(
      OpenSSL::HMAC.digest("SHA256", secret, signing_input),
      padding: false
    )
    "#{signing_input}.#{signature}"
  end

  def base64url_json(payload)
    Base64.urlsafe_encode64(payload.to_json, padding: false)
  end
end
