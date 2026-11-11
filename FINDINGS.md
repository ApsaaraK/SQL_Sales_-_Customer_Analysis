# Findings: Customer and Sales Analysis

Online retailer, January 2024 to December 2025. 4,300 orders, 7,447 order lines, 700 customers, 30 products, amounts in LKR. Synthetic data, so the patterns below describe this dataset, not a real business.

**Revenue** is the value of order lines after discounts, excluding returned lines (which are fully refunded). Total revenue is **Rs 54,450,015**: Rs 23.83M in 2024 and Rs 30.62M in 2025, up 28.5%.

| Question | What the data shows | What I would do |
|---|---|---|
| **Q1. Who are the top customers?** | Revenue is spread very evenly. The top customer (C0601, Colombo) is 0.43% of revenue, and the top ten together are 3.94%. | No customer-dependency risk. Loyalty offers should target broad segments, not a few key accounts. |
| **Q2. Do customers come back?** | 688 of 698 purchasing customers (98.6%) bought again. They average 5.9 purchases, the median wait for a second purchase is 89 days, and 50.1% returned within 90 days of their first purchase. | Treat the first 90 days as the window for a follow-up offer, since half of repeat buyers return within it. |
| **Q3. How does revenue move?** | A strong seasonal pattern: April (New Year) and November to December peak. December 2025 was the best month at Rs 2.94M. Every 2025 month beat the same month of 2024, by between 2.7% and 75.9%. | Plan stock and staffing around April and November to December. |
| **Q4. What is bought together?** | The most common pair, Power Bank and Bluetooth Speaker, appears in only 24 orders (0.58%). All ten top pairs have a lift between 0.85 and 1.09, close to the 1.0 expected by chance. | Do not build bundles on this evidence. These pairs are common because the products are popular, not because they go together. |
| **Q5. Who has gone quiet?** | 64.0% of customers are active (bought in the last 90 days), 19.9% are at risk (91 to 180 days), 15.9% are inactive (180+ days). Two customers have never bought. | The 139 at-risk customers hold Rs 10.7M of lifetime revenue and are the best win-back target. |
| **Q6. Which categories matter?** | Home & Kitchen (28.2%) and Electronics (25.1%) bring over half of revenue. But Electronics earns only a 14.6% margin, against 50.5% for Beauty & Care and 41.1% for Fashion. | Judge categories on profit as well as revenue. Electronics needs a discount and returns review. |

## How the numbers were checked

- **Joins do not inflate revenue.** The order-line view has exactly as many rows as the order-lines table (7,447). Revenue summed five different ways (directly, by customer, by month, by category, by channel) is the same Rs 54,450,015 every time.
- **A deliberately wrong join shows the risk.** Joining each line to all lines of its order overstates revenue by 120% and the order count by 266%.
- **Independent recalculation.** Every query result was recomputed in pandas from the raw CSV files, with no SQL, and matches. Changing one figure by one rupee makes the check fail, so the check is not just agreeing with itself.
- **Matches the dashboard project.** Total revenue and the category figures are identical to the Tableau dashboard project's answer key.

## Limits

- Customer behaviour here is random by construction, so the 98.6% repeat rate is far higher than a real shop would see, and the weak co-purchase signal in Q4 reflects the data generator, not shopper behaviour. The queries are the deliverable, and they would run unchanged on real data.
- The as-of date (31 December 2025) and the 90 and 180 day thresholds are set at the top of Q2 and Q5 and can be changed.
