defmodule Product do
  @moduledoc """
  Simplified product management for demonstrating metastatic's MetaAST capabilities.

  This module showcases various language constructs that will be transformed to MetaAST:
  - Arithmetic operations (price calculations)
  - Comparison operations (stock checking, boundary conditions)
  - Boolean logic (availability checks)
  - Conditional branches (discount tiers)
  - Pattern matching (function clauses)
  """

  defstruct [:id, :name, :price, :stock]

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          price: float(),
          stock: non_neg_integer()
        }

  @doc """
  Checks if product has sufficient stock for requested quantity.

  ## Examples

      iex> product = %Product{id: "P1", name: "Widget", price: 10.0, stock: 100}
      iex> Product.available?(product, 50)
      true

      iex> product = %Product{id: "P1", name: "Widget", price: 10.0, stock: 5}
      iex> Product.available?(product, 10)
      false
  """
  def available?(%__MODULE__{stock: stock}, quantity) when quantity > 0 do
    stock >= quantity
  end

  def available?(_product, _quantity), do: false

  @doc """
  Calculates price for given quantity with tiered bulk discounts.

  Discount tiers:
  - 100+: 20% off
  - 50+: 15% off
  - 10+: 10% off
  - 5+: 5% off

  ## Examples

      iex> product = %Product{id: "P1", name: "Widget", price: 10.0, stock: 100}
      iex> Product.calculate_price(product, 1)
      10.0

      iex> Product.calculate_price(product, 10)
      90.0
  """
  def calculate_price(%__MODULE__{price: price}, quantity) when quantity > 0 do
    base_price = price * quantity

    discount_rate =
      cond do
        quantity >= 100 -> 0.20
        quantity >= 50 -> 0.15
        quantity >= 10 -> 0.10
        quantity >= 5 -> 0.05
        true -> 0.0
      end

    discount = base_price * discount_rate
    base_price - discount
  end

  @doc """
  Reduces stock by specified quantity.

  ## Examples

      iex> product = %Product{id: "P1", name: "Widget", price: 10.0, stock: 100}
      iex> {:ok, updated} = Product.reduce_stock(product, 30)
      iex> updated.stock
      70
  """
  def reduce_stock(%__MODULE__{stock: stock} = product, quantity)
      when quantity > 0 and stock >= quantity do
    {:ok, %{product | stock: stock - quantity}}
  end

  def reduce_stock(_product, _quantity) do
    {:error, :insufficient_stock}
  end

  @doc """
  Checks if product needs restocking based on threshold.

  ## Examples

      iex> product = %Product{id: "P1", name: "Widget", price: 10.0, stock: 3}
      iex> Product.needs_restock?(product, 10)
      true

      iex> product = %Product{id: "P1", name: "Widget", price: 10.0, stock: 20}
      iex> Product.needs_restock?(product, 10)
      false
  """
  def needs_restock?(%__MODULE__{stock: stock}, threshold) do
    stock < threshold
  end

  @doc """
  Calculates shipping weight for quantity.
  Assumes 0.5 lbs per unit + 0.1 lbs packaging per item.

  ## Examples

      iex> product = %Product{id: "P1", name: "Widget", price: 10.0, stock: 100}
      iex> Product.shipping_weight(product, 10)
      6.0
  """
  def shipping_weight(%__MODULE__{}, quantity) when quantity > 0 do
    unit_weight = 0.5
    packaging_per_unit = 0.1
    quantity * (unit_weight + packaging_per_unit)
  end
end
