class Factory::Run < ApplicationRecord
  class NotClaimable < StandardError; end
  class RunnerMismatch < StandardError; end

  MAX_LOG_CONTENT_LENGTH = 64.kilobytes
  STREAMS = %w[ system stdout stderr agent verification ].freeze
  STATES = %w[ queued running completed failed blocked ].freeze

  belongs_to :account, default: -> { card&.account || profile&.account || Current.account }
  belongs_to :card
  belongs_to :profile, class_name: "Factory::Profile"
  belongs_to :runner, class_name: "Factory::Runner", optional: true
  belongs_to :requester, class_name: "User", optional: true

  has_many :logs, class_name: "Factory::RunLog", dependent: :destroy

  store :metadata, coder: JSON

  enum :state, STATES.index_by(&:itself), default: :queued

  scope :ordered, -> { order(created_at: :desc, id: :desc) }
  scope :oldest_first, -> { order(:created_at, :id) }

  before_validation :set_defaults, on: :create
  after_create_commit :broadcast_progress
  after_update_commit :broadcast_progress

  validates :branch_name, presence: true
  validates :state, inclusion: { in: STATES }
  validates :attempts_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :max_attempts, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 10 }
  validates :max_iterations, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 20 }
  validate :records_share_account

  class << self
    def queue_for(card:, profile:, requester: Current.user)
      create!(
        account: card.account,
        card: card,
        profile: profile,
        requester: requester,
        max_attempts: profile.max_attempts,
        max_iterations: profile.max_iterations,
        verification_command: profile.verification_command
      ).tap do |run|
        run.add_system_note!("Queued for #{profile.name}.")
      end
    end

    def claim_next_for(runner)
      where(account: runner.account).queued.oldest_first.find_each do |run|
        return run if run.claim_by(runner)
      end

      nil
    end
  end

  def ready_for_runner?
    queued? && dependencies_satisfied?
  end

  def dependencies_satisfied?
    blocked_dependency_cards.none?
  end

  def blocked_dependency_cards
    card.factory_parent_cards.reject do |parent|
      parent.closed? || parent.factory_runs.completed.exists?
    end
  end

  def claim_by(runner)
    with_lock do
      return false unless queued?
      return false unless dependencies_satisfied?

      update!(
        runner: runner,
        state: :running,
        attempts_count: attempts_count + 1,
        claimed_at: Time.current,
        heartbeat_at: Time.current,
        started_at: started_at || Time.current
      )

      add_log!(stream: "system", content: "Claimed by #{runner.name}.")
      true
    end
  end

  def heartbeat_by!(runner, metadata: nil)
    with_authorized_runner!(runner) do
      self.metadata = metadata if metadata.present?
      update!(heartbeat_at: Time.current)
    end
  end

  def add_log!(stream:, content:, sequence: nil)
    with_lock do
      logs.create!(
        account: account,
        stream: stream,
        sequence: sequence.presence || next_log_sequence,
        content: content.to_s.truncate(MAX_LOG_CONTENT_LENGTH, omission: "\n...[truncated]")
      )
    end
  end

  def complete_by!(runner, summary:, commit_sha: nil, branch_name: nil, verification_status: nil, metadata: nil)
    with_authorized_runner!(runner) do
      transaction do
        self.metadata = metadata if metadata.present?
        update!(
          state: :completed,
          summary: summary,
          commit_sha: commit_sha.presence || self.commit_sha,
          branch_name: branch_name.presence || self.branch_name,
          verification_status: verification_status.presence,
          completed_at: Time.current,
          heartbeat_at: Time.current
        )

        add_system_note!("Factory run completed#{commit_reference}.")
        close_card_after_success
      end
    end
  end

  def fail_by!(runner, failure_reason:, metadata: nil)
    with_authorized_runner!(runner) do
      transaction do
        self.metadata = metadata if metadata.present?

        if attempts_count < max_attempts
          update!(
            state: :queued,
            runner: nil,
            failure_reason: failure_reason,
            heartbeat_at: nil,
            claimed_at: nil
          )
          add_system_note!("Factory run failed and was requeued: #{failure_reason}")
        else
          update!(
            state: :failed,
            failure_reason: failure_reason,
            completed_at: Time.current,
            heartbeat_at: Time.current
          )
          add_system_note!("Factory run failed: #{failure_reason}")
        end
      end
    end
  end

  def block_by!(runner, block_reason:, metadata: nil)
    with_authorized_runner!(runner) do
      transaction do
        self.metadata = metadata if metadata.present?
        update!(
          state: :blocked,
          block_reason: block_reason,
          completed_at: Time.current,
          heartbeat_at: Time.current
        )
        add_system_note!("Factory run blocked: #{block_reason}")
      end
    end
  end

  def runner_prompt
    profile.build_prompt_for(self)
  end

  def latest_log
    logs.order(sequence: :desc, id: :desc).first
  end

  def add_system_note!(body)
    card.comments.create!(account: account, creator: account.system_user, body: body)
  end

  private
    def broadcast_progress
      broadcast_refresh_later
      card.broadcast_refresh_later
    end

    def set_defaults
      self.max_attempts ||= profile&.max_attempts || 2
      self.max_iterations ||= profile&.max_iterations || 1
      self.verification_command ||= profile&.verification_command
      self.branch_name ||= default_branch_name
    end

    def default_branch_name
      suffix = SecureRandom.hex(4)
      "factory/card-#{card&.number || "new"}-#{suffix}"
    end

    def records_share_account
      [ card, profile, runner, requester ].compact.each do |record|
        if record.account_id != account_id
          errors.add(:account, "must match #{record.class.model_name.human.downcase}")
        end
      end
    end

    def with_authorized_runner!(runner)
      raise RunnerMismatch unless self.runner == runner

      yield
    end

    def next_log_sequence
      logs.maximum(:sequence).to_i + 1
    end

    def close_card_after_success
      if verification_status.blank? || verification_status.in?(%w[ passed skipped ])
        card.close(user: account.system_user)
      end
    end

    def commit_reference
      commit_sha.present? ? " at #{commit_sha.first(12)}" : ""
    end
end
