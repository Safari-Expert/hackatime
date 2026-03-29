class InternalUiLaunchRedemption < ApplicationRecord
  validates :jti, presence: true, uniqueness: true
  validates :audience, presence: true
  validates :github_uid, presence: true
  validates :expires_at, presence: true

  def self.consume!(jti:, audience:, github_uid:, expires_at:)
    where("expires_at < ?", Time.current).delete_all

    create!(
      jti: jti,
      audience: audience,
      github_uid: github_uid,
      expires_at: expires_at
    )

    true
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    false
  end
end
