# frozen_string_literal: true

class Book < ApplicationRecord
  belongs_to :category

  validates :title, presence: true, length: { minimum: 1, maximum: 255 }
  validates :price, presence: true, numericality: { greater_than: 0 }
  validates :stock, numericality: { greater_than_or_equal_to: 0 }

  scope :in_stock, -> { where("stock > 0") }
  scope :by_categories, ->(ids) { where(category_id: ids) if ids.present? }

  STATUSES = %w[draft published].freeze

  def in_stock?
    stock > 0
  end

  def available?(quantity)
    stock >= quantity
  end
end
