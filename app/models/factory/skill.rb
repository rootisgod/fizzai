class Factory::Skill < ApplicationRecord
  belongs_to :account, default: -> { Current.account }

  has_many :profile_skills, class_name: "Factory::ProfileSkill", dependent: :destroy
  has_many :profiles, through: :profile_skills

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:name, :id) }

  validates :name, presence: true, uniqueness: { scope: :account_id }
end
