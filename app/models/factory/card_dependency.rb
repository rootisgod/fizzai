class Factory::CardDependency < ApplicationRecord
  belongs_to :account, default: -> { child_card&.account || parent_card&.account || Current.account }
  belongs_to :parent_card, class_name: "Card"
  belongs_to :child_card, class_name: "Card"

  validates :child_card_id, uniqueness: { scope: :parent_card_id }
  validate :cards_share_account
  validate :cannot_depend_on_self

  def self.add!(child:, parent:)
    create!(account: child.account, child_card: child, parent_card: parent)
  end

  private
    def cards_share_account
      return if child_card.blank? || parent_card.blank?

      if child_card.account_id != parent_card.account_id
        errors.add(:parent_card, "must belong to the same account")
      end
    end

    def cannot_depend_on_self
      if child_card_id.present? && child_card_id == parent_card_id
        errors.add(:parent_card, "cannot be the same card")
      end
    end
end
