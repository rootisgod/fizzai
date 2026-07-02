class Factory::RunLog < ApplicationRecord
  belongs_to :account, default: -> { run.account }
  belongs_to :run, class_name: "Factory::Run"

  validates :content, presence: true
  validates :sequence, numericality: { only_integer: true, greater_than: 0 }, uniqueness: { scope: :run_id }
  validates :stream, inclusion: { in: Factory::Run::STREAMS }
  validate :record_shares_account

  after_create_commit :broadcast_progress

  scope :ordered, -> { order(:sequence, :id) }

  private
    def broadcast_progress
      run.broadcast_refresh_later
      run.card.broadcast_refresh_later
    end

    def record_shares_account
      return if run.blank?

      if run.account_id != account_id
        errors.add(:account, "must match run")
      end
    end
end
