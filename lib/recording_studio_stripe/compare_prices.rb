# frozen_string_literal: true

module RecordingStudioStripe
  class ComparePrices
    def self.upgrade?(from:, to:)
      new(from: from, to: to).upgrade?
    end

    def initialize(from:, to:)
      @from = from
      @to = to
    end

    def upgrade?
      return interval_upgrade? if same_product?

      to_rank > from_rank
    end

    def downgrade?
      return interval_downgrade? if same_product?

      to_rank < from_rank
    end

    private

    def same_product?
      @from.respond_to?(:product_id) && @to.respond_to?(:product_id) &&
        @from.product_id.present? && @from.product_id == @to.product_id
    end

    def interval_upgrade?
      @from.monthly? && @to.annual?
    end

    def interval_downgrade?
      @from.annual? && @to.monthly?
    end

    def from_rank
      rank_for(@from)
    end

    def to_rank
      rank_for(@to)
    end

    def rank_for(price)
      metadata_rank = price.metadata.to_h["rank"].to_i
      return metadata_rank if metadata_rank.positive?

      price.monthly_unit_amount.to_i
    end
  end
end
