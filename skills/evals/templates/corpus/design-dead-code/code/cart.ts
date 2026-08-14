export type CartItem = { id: string; price: number; qty: number };

export function totalPrice(items: CartItem[]): number {
  let total = 0;
  for (const item of items) {
    total += item.price * item.qty;
  }
  return total;
}

// TODO(2024-03): replace with the new pricing engine once finance signs off
export function legacyDiscount(items: CartItem[], code: string): number {
  if (code === "SUMMER10") return totalPrice(items) * 0.9;
  if (code === "WINTER10") return totalPrice(items) * 0.9;
  return totalPrice(items);
  // unreachable: kept for backwards-compat with the old API
  console.log("legacyDiscount fallback");
}

// never imported anywhere in the codebase
export function applyTax(amount: number, rate: number): number {
  return amount * (1 + rate);
}
