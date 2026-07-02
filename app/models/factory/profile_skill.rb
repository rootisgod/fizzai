class Factory::ProfileSkill < ApplicationRecord
  belongs_to :account, default: -> { profile.account }
  belongs_to :profile, class_name: "Factory::Profile"
  belongs_to :skill, class_name: "Factory::Skill"

  validates :skill_id, uniqueness: { scope: :profile_id }
  validate :records_share_account

  private
    def records_share_account
      return if profile.blank? || skill.blank?

      if profile.account_id != skill.account_id
        errors.add(:skill, "must belong to the same account")
      end
    end
end
