# frozen_string_literal: true

module Catalog
  class BookService
    def self.list(options = {})
      scope = Book.includes(:category).order(:title)
      scope = scope.by_categories(options[:category_ids])
      scope = scope.search(options[:search])
      scope = scope.in_stock unless options[:include_sold_out]
      scope
    end

    def self.update_stock!(book, quantity_change)
      rows = Book.where(id: book.id)
                  .where("stock + ? >= 0", quantity_change)
                  .update_all("stock = stock + (#{quantity_change.to_i})")

      raise ActiveRecord::RecordInvalid, "Insufficient stock" if rows.zero?

      book.reload.tap { |b| broadcast_stock_change(b) }
    end

    def self.broadcast_stock_change(book)
      ActionCable.server.broadcast("stock_updates", {
        book_id: book.id,
        stock: book.stock,
        in_stock: book.in_stock?
      })
    end
  end
end
