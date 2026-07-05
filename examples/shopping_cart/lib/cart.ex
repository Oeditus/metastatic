defmodule Cart do
  @moduledoc """
  Shopping cart with item management and price calculations.

  This module demonstrates metastatic's ability to handle:
  - Complex nested expressions (multi-step calculations)
  - Map operations (items management)
  - Higher-order functions (Enum.reduce, Enum.map)
  - Guard clauses and pattern matching
  - Error tuples and control flow
  """

  defstruct items: %{}, coupon_code: nil

  @type item :: %{product: Product.t(), quantity: non_neg_integer()}
  @type t :: %__MODULE__{
          items: %{String.t() => item()},
          coupon_code: String.t() | nil
        }

  @doc """
  Creates a new empty cart.
  """
  def new do
    %__MODULE__{}
  end

  @doc """
  Adds a product to the cart with validation.

  ## Examples

      iex> cart = Cart.new()
      iex> product = %Product{id: "P1", name: "Widget", price: 10.0, stock: 100}
      iex> {:ok, cart} = Cart.add_item(cart, product, 5)
      iex> Cart.item_count(cart)
      5
  """
  def add_item(%__MODULE__{items: items} = cart, %Product{} = product, quantity)
      when quantity > 0 do
    if Product.available?(product, quantity) do
      items =
        Map.update(
          items,
          product.id,
          %{product: product, quantity: quantity},
          fn existing ->
            new_quantity = existing.quantity + quantity

            if Product.available?(product, new_quantity) do
              %{existing | quantity: new_quantity}
            else
              existing
            end
          end
        )

      {:ok, %{cart | items: items}}
    else
      {:error, :insufficient_stock}
    end
  end

  def add_item(_cart, _product, _quantity) do
    {:error, :invalid_quantity}
  end

  @doc """
  Returns the total number of items in cart.

  ## Examples

      iex> cart = Cart.new()
      iex> Cart.item_count(cart)
      0
  """
  def item_count(%__MODULE__{items: items}) do
    Enum.reduce(items, 0, fn {_id, %{quantity: qty}}, acc ->
      acc + qty
    end)
  end

  @doc """
  Checks if the cart is empty.
  """
  def empty?(%__MODULE__{items: items}) do
    map_size(items) == 0
  end

  @doc """
  Calculates subtotal before discounts.

  ## Examples

      iex> cart = Cart.new()
      iex> product = %Product{id: "P1", name: "Widget", price: 10.0, stock: 100}
      iex> {:ok, cart} = Cart.add_item(cart, product, 10)
      iex> Cart.subtotal(cart)
      90.0
  """
  def subtotal(%__MODULE__{items: items}) do
    Enum.reduce(items, 0.0, fn {_id, %{product: product, quantity: qty}}, acc ->
      item_price = Product.calculate_price(product, qty)
      acc + item_price
    end)
  end

  @doc """
  Applies a coupon code.

  Supported coupons:
  - "SAVE10": 10% off, minimum $50
  - "SAVE20": 20% off, minimum $100

  ## Examples

      iex> cart = Cart.new()
      iex> product = %Product{id: "P1", name: "Widget", price: 10.0, stock: 100}
      iex> {:ok, cart} = Cart.add_item(cart, product, 10)
      iex> {:ok, cart} = Cart.apply_coupon(cart, "SAVE10")
      iex> cart.coupon_code
      "SAVE10"
  """
  def apply_coupon(%__MODULE__{} = cart, coupon_code) when is_binary(coupon_code) do
    case validate_coupon(cart, coupon_code) do
      :ok -> {:ok, %{cart | coupon_code: coupon_code}}
      {:error, _} = error -> error
    end
  end

  @doc """
  Calculates coupon discount amount.
  """
  def coupon_discount(%__MODULE__{coupon_code: nil}), do: 0.0

  def coupon_discount(%__MODULE__{coupon_code: coupon} = cart) do
    subtotal = subtotal(cart)

    discount_rate =
      case coupon do
        "SAVE10" -> 0.10
        "SAVE20" -> 0.20
        _ -> 0.0
      end

    subtotal * discount_rate
  end

  @doc """
  Calculates total weight of all items in cart.

  ## Examples

      iex> cart = Cart.new()
      iex> product = %Product{id: "P1", name: "Widget", price: 10.0, stock: 100}
      iex> {:ok, cart} = Cart.add_item(cart, product, 10)
      iex> Cart.total_weight(cart)
      6.0
  """
  def total_weight(%__MODULE__{items: items}) do
    Enum.reduce(items, 0.0, fn {_id, %{product: product, quantity: qty}}, acc ->
      acc + Product.shipping_weight(product, qty)
    end)
  end

  @doc """
  Calculates final total after discount.

  ## Examples

      iex> cart = Cart.new()
      iex> product = %Product{id: "P1", name: "Widget", price: 10.0, stock: 100}
      iex> {:ok, cart} = Cart.add_item(cart, product, 10)
      iex> Cart.total(cart)
      90.0
  """
  def total(%__MODULE__{} = cart) do
    subtotal = subtotal(cart)
    discount = coupon_discount(cart)
    subtotal - discount
  end

  # Private helpers

  defp validate_coupon(cart, coupon_code) do
    subtotal = subtotal(cart)

    min_required =
      case coupon_code do
        "SAVE10" -> 50.0
        "SAVE20" -> 100.0
        _ -> :invalid
      end

    cond do
      min_required == :invalid -> {:error, :invalid_coupon}
      subtotal < min_required -> {:error, :minimum_not_met}
      true -> :ok
    end
  end
end
