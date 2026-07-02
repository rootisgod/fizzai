class Factory::RunLog < ApplicationRecord
  belongs_to :account, default: -> { run.account }
  belongs_to :run, class_name: "Factory::Run"

  validates :content, presence: true
  validates :sequence, numericality: { only_integer: true, greater_than: 0 }, uniqueness: { scope: :run_id }
  validates :stream, inclusion: { in: Factory::Run::STREAMS }
  validate :record_shares_account

  scope :ordered, -> { order(:sequence, :id) }

  private
    def record_shares_account
      return if run.blank?

      if run.account_id != account_id
        errors.add(:account, "must match run")
      end
    end
end
