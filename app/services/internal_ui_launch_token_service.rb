require "base64"
require "json"
require "openssl"

class InternalUiLaunchTokenService
  class ConfigurationError < StandardError; end
  class InvalidTokenError < StandardError; end

  def initialize(secret: ENV["HACKATIME_INTERNAL_UI_LAUNCH_SHARED_SECRET"])
    @secret = secret.to_s
  end

  def decode!(token, audience:)
    raise ConfigurationError, "missing shared secret" if @secret.blank?

    header_segment, payload_segment, signature_segment = token.to_s.split(".", 3)
    raise InvalidTokenError, "invalid token format" if [ header_segment, payload_segment, signature_segment ].any?(&:blank?)

    signing_input = [ header_segment, payload_segment ].join(".")
    expected_signature = Base64.urlsafe_encode64(
      OpenSSL::HMAC.digest("SHA256", @secret, signing_input),
      padding: false
    )

    unless ActiveSupport::SecurityUtils.secure_compare(expected_signature, signature_segment)
      raise InvalidTokenError, "signature mismatch"
    end

    header = parse_segment(header_segment)
    payload = parse_segment(payload_segment)

    raise InvalidTokenError, "unexpected algorithm" unless header["alg"] == "HS256"
    raise InvalidTokenError, "unexpected issuer" unless payload["iss"] == "internal_ui"
    raise InvalidTokenError, "unexpected audience" unless payload["aud"] == audience
    raise InvalidTokenError, "missing subject" if payload["sub"].blank?
    raise InvalidTokenError, "missing github login" if payload["github_login"].blank?
    raise InvalidTokenError, "missing email" if payload["email"].blank?
    raise InvalidTokenError, "missing jti" if payload["jti"].blank?
    raise InvalidTokenError, "expired token" if payload["exp"].to_i <= Time.current.to_i

    payload
  end

  private

  def parse_segment(segment)
    JSON.parse(Base64.urlsafe_decode64(pad(segment)))
  rescue ArgumentError, JSON::ParserError => e
    raise InvalidTokenError, "malformed token payload: #{e.message}"
  end

  def pad(segment)
    padding_length = (4 - (segment.length % 4)) % 4
    "#{segment}#{'=' * padding_length}"
  end
end
