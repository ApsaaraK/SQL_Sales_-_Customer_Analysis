#!/usr/bin/env python3
"""
verify_with_pandas.py - recomputes every query result from the raw CSVs with pandas (no SQL)
and compares it with the CSV files that PostgreSQL produced in results/.

Run after exporting the results:  python verification/verify_with_pandas.py
Exit code 0 = every query matches, 1 = at least one difference.
"""
import itertools
import math
import sys
from pathlib import Path

import numpy as np
import pandas as pd

ROOT = Path(__file__).resolve().parent.parent
AS_OF = pd.Timestamp("2025-12-31")

items = pd.read_csv(ROOT / "data" / "order_items.csv")
orders = pd.read_csv(ROOT / "data" / "orders.csv", parse_dates=["order_date"])
customers = pd.read_csv(ROOT / "data" / "customers.csv")
products = pd.read_csv(ROOT / "data" / "products.csv")

df = items.merge(orders, on="order_id").merge(products[["product_id", "product_name", "category", "unit_cost"]], on="product_id")
df["net"] = df.quantity * df.list_price * (1 - df.discount_pct)
df["cost"] = df.quantity * df.unit_cost
kept = df[df.returned == 0]


def half_up(x, d=0):
    return math.floor(x * 10 ** d + 0.5) / 10 ** d


failures = []


def compare(name, expected: pd.DataFrame, actual_path: str, decimals: dict):
    """Compare each column; numeric columns must agree to one unit in the last printed decimal."""
    actual = pd.read_csv(ROOT / "results" / actual_path)
    ok = list(expected.columns) == list(actual.columns) and len(expected) == len(actual)
    problems = [] if ok else [f"shape/columns differ: expected {expected.shape} {list(expected.columns)}, got {actual.shape} {list(actual.columns)}"]
    if ok:
        for col in expected.columns:
            for i, (e, a) in enumerate(zip(expected[col], actual[col])):
                if pd.isna(e) and pd.isna(a):
                    continue
                if isinstance(e, str) or isinstance(a, str):
                    if str(e) != str(a):
                        problems.append(f"{col} row {i}: expected {e!r}, got {a!r}")
                elif abs(float(e) - float(a)) > 10 ** -decimals.get(col, 2) + 1e-9:
                    problems.append(f"{col} row {i}: expected {e}, got {a}")
    print(f"{'PASS' if not problems else 'FAIL'}  {name}")
    for p in problems[:5]:
        print("      ", p)
    if problems:
        failures.append(name)


# Q1 ---------------------------------------------------------------- top customers
g = kept.groupby("customer_id").agg(revenue=("net", "sum"), orders=("order_id", "nunique")).reset_index()
g = g.merge(customers[["customer_id", "district"]], on="customer_id")
total = g.revenue.sum()
g = g.sort_values(["revenue", "customer_id"], ascending=[False, True]).head(10).reset_index(drop=True)
q1 = pd.DataFrame({"rank": range(1, 11), "customer_id": g.customer_id, "district": g.district, "orders": g.orders,
                   "revenue": g.revenue.round(2), "avg_order_value": (g.revenue / g.orders).round(2),
                   "pct_of_total_revenue": (100 * g.revenue / total).round(2)})
compare("Q1 top customers", q1, "q1_top_customers.csv", {"pct_of_total_revenue": 2})

# Q2 ---------------------------------------------------------------- repeat customers
purch = kept[["customer_id", "order_id", "order_date"]].drop_duplicates().sort_values(["customer_id", "order_date", "order_id"])
purch["n"] = purch.groupby("customer_id").cumcount() + 1
first = purch[purch.n == 1].set_index("customer_id").order_date
second = purch[purch.n == 2].set_index("customer_id").order_date
pc = pd.DataFrame({"first": first, "second": second, "count": purch.groupby("customer_id").size()})
days = (pc["second"] - pc["first"]).dt.days.dropna()
observable = pc[pc["first"] <= AS_OF - pd.Timedelta(days=90)]
within = ((observable["second"] <= observable["first"] + pd.Timedelta(days=90)) & observable["second"].notna()).sum()
q2 = pd.DataFrame([{"customers_with_purchases": len(pc), "repeat_customers": int(pc["second"].notna().sum()),
                    "repeat_rate_pct": half_up(100 * pc["second"].notna().sum() / len(pc), 1),
                    "avg_purchases_per_customer": half_up(pc["count"].mean(), 2),
                    "median_days_to_second_purchase": half_up(days.median(), 0),
                    "repeat_within_90_days_pct": half_up(100 * within / len(observable), 1)}])
compare("Q2 repeat customers", q2, "q2_repeat_customers.csv", {"repeat_rate_pct": 1, "avg_purchases_per_customer": 2,
                                                              "median_days_to_second_purchase": 0, "repeat_within_90_days_pct": 1})

# Q3 ---------------------------------------------------------------- monthly revenue
m = kept.assign(month=kept.order_date.dt.to_period("M")).groupby("month").agg(revenue=("net", "sum"), orders=("order_id", "nunique"))
m["mom"] = 100 * m.revenue.pct_change()
m["ma3"] = m.revenue.rolling(3).mean()
m["yoy"] = 100 * (m.revenue / m.revenue.shift(12) - 1)
q3 = pd.DataFrame({"month": m.index.astype(str), "revenue": m.revenue.round(2).values, "orders": m.orders.values,
                   "mom_change_pct": m.mom.round(1).values, "moving_avg_3m": m.ma3.round(2).values,
                   "yoy_change_pct": m.yoy.round(1).values})
compare("Q3 monthly revenue", q3, "q3_monthly_revenue.csv", {"mom_change_pct": 1, "yoy_change_pct": 1})

# Q4 ---------------------------------------------------------------- bought together
op = kept[["order_id", "product_id"]].drop_duplicates()
n_orders = op.order_id.nunique()
pop = op.groupby("product_id").size()
pair_counts = {}
for _, grp in op.groupby("order_id"):
    for a, b in itertools.combinations(sorted(grp.product_id), 2):
        pair_counts[(a, b)] = pair_counts.get((a, b), 0) + 1
names = products.set_index("product_id").product_name
rows = []
for (a, b), c in pair_counts.items():
    lift = (c / n_orders) / ((pop[a] / n_orders) * (pop[b] / n_orders))
    rows.append({"product_a": names[a], "product_b": names[b], "orders_together": c,
                 "pct_of_orders": 100 * c / n_orders, "lift": lift})
q4 = pd.DataFrame(rows).sort_values(["orders_together", "product_a", "product_b"], ascending=[False, True, True]).head(10).reset_index(drop=True)
q4["pct_of_orders"] = q4.pct_of_orders.round(2)
q4["lift"] = q4.lift.round(2)
compare("Q4 bought together", q4, "q4_bought_together.csv", {"pct_of_orders": 2, "lift": 2})

# Q5 ---------------------------------------------------------------- inactive customers
last = kept.groupby("customer_id").agg(last_date=("order_date", "max"), purchases=("order_id", "nunique"), life=("net", "sum"))
s = customers[["customer_id"]].merge(last, on="customer_id", how="left")
s["days"] = (AS_OF - s.last_date).dt.days


def segment(d):
    if pd.isna(d):
        return "Never purchased"
    return "1 Active (0-90 days)" if d <= 90 else "2 At risk (91-180 days)" if d <= 180 else "3 Inactive (180+ days)"


s["segment"] = s.days.map(segment)
q5 = s.groupby("segment").agg(customers=("customer_id", "count"), life=("life", "sum"), purchases=("purchases", "mean")).reset_index()
q5["pct_of_customers"] = (100 * q5.customers / q5.customers.sum()).map(lambda x: half_up(x, 1))
q5["lifetime_revenue"] = q5.life.fillna(0).round(2)
q5["avg_purchases"] = q5.purchases.fillna(0).map(lambda x: half_up(x, 1))
q5 = q5[["segment", "customers", "pct_of_customers", "lifetime_revenue", "avg_purchases"]].sort_values("segment").reset_index(drop=True)
compare("Q5 inactive customers", q5, "q5_inactive_customers.csv", {"pct_of_customers": 1, "avg_purchases": 1})

# Q6 ---------------------------------------------------------------- category revenue
c = kept.groupby("category").agg(revenue=("net", "sum"), cost=("cost", "sum")).sort_values("revenue", ascending=False)
c["gp"] = c.revenue - c.cost
q6 = pd.DataFrame({"category": c.index, "revenue": c.revenue.round(2).values,
                   "pct_of_revenue": (100 * c.revenue / c.revenue.sum()).round(1).values,
                   "cumulative_pct": (100 * c.revenue.cumsum() / c.revenue.sum()).round(1).values,
                   "gross_profit": c.gp.round(2).values, "gross_margin_pct": (100 * c.gp / c.revenue).round(1).values})
compare("Q6 category revenue", q6, "q6_category_revenue.csv", {"pct_of_revenue": 1, "cumulative_pct": 1, "gross_margin_pct": 1})

# Reconciliation file ------------------------------------------------------------
rec = pd.read_csv(ROOT / "results" / "reconciliation.csv")
checks = rec[~rec["group"].str.startswith("Trap")]
ok = (checks.status == "PASS").all()
print(f"{'PASS' if ok else 'FAIL'}  Reconciliation: {int((checks.status == 'PASS').sum())} of {len(checks)} checks pass")
if not ok:
    failures.append("reconciliation")

print("\nAll results match the independent pandas calculation." if not failures else f"\nDifferences found in: {', '.join(failures)}")
sys.exit(1 if failures else 0)
