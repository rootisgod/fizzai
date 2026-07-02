class Factory::Profile < ApplicationRecord
  BRAIN_PROVIDERS = %w[ codex_cli openrouter minimax custom ].freeze
  RUNNER_KINDS = %w[ sandcastle dry_run custom ].freeze

  belongs_to :account, default: -> { Current.account }

  has_many :profile_skills, class_name: "Factory::ProfileSkill", dependent: :destroy
  has_many :skills, through: :profile_skills
  has_many :runs, class_name: "Factory::Run", dependent: :restrict_with_exception

  store :brain_options, coder: JSON

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:name, :id) }

  validates :name, presence: true, uniqueness: { scope: :account_id }
  validates :brain_provider, inclusion: { in: BRAIN_PROVIDERS }
  validates :runner_kind, inclusion: { in: RUNNER_KINDS }
  validates :max_attempts, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 10 }
  validates :max_iterations, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 20 }

  def build_prompt_for(run)
    card = run.card
    sections = [
      "You are working a Fizzy factory card.",
      "Card ##{card.number}: #{card.title}",
      card_description(card),
      profile_context,
      skills_context,
      "Use branch #{run.branch_name}. Commit changes locally, but do not push branches or open pull requests.",
      verification_context(run)
    ]

    sections.compact_blank.join("\n\n")
  end

  private
    def card_description(card)
      description = card.description&.to_plain_text.to_s.strip
      "Description:\n#{description.presence || "(none)"}"
    end

    def profile_context
      [
        "Profile: #{name}",
        description.presence,
        prompt.presence
      ].compact_blank.join("\n")
    end

    def skills_context
      active_skills = skills.active.ordered
      return if active_skills.none?

      skill_blocks = active_skills.map do |skill|
        [
          "Skill: #{skill.name}",
          skill.description.presence,
          skill.instructions.presence
        ].compact_blank.join("\n")
      end

      "Skills:\n#{skill_blocks.join("\n\n")}"
    end

    def verification_context(run)
      return if run.verification_command.blank?

      "After implementation, run this verification command inside the worktree:\n#{run.verification_command}"
    end
end
