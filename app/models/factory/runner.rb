class Factory::Runner < ApplicationRecord
  KINDS = %w[ sandcastle dry_run custom ].freeze

  belongs_to :account, default: -> { Current.account }

  has_many :runs, class_name: "Factory::Run", dependent: :nullify

  has_secure_token :token
  store :metadata, coder: JSON

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:name, :id) }

  validates :name, presence: true, uniqueness: { scope: :account_id }
  validates :kind, inclusion: { in: KINDS }

  def heartbeat!(metadata: nil)
    self.metadata = metadata if metadata.present?
    update!(last_seen_at: Time.current)
  end
end
