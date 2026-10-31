# Rewarded-UA Account Review

A Monday-morning review of a book of five advertiser accounts on a rewarded user-acquisition platform: which accounts carry the book, which segments hit their ROAS targets, where budget is left unspent, why one account's revenue dropped, how much margin each segment earns, and what each fix is worth in euros.

**[Open the notebook](Rewarded_UA_Account_Review.ipynb)** to read the full analysis with tables and charts, or [run it in Google Colab](https://colab.research.google.com/drive/19IzwuelsU9EsgnTXnhfG2or3DSFJStsB?usp=sharing).

## How this was built

This is a learning project, built **with AI assistance (Claude)** to learn and demonstrate the core concepts of rewarded user acquisition: ROAS, cap fill, cohorts, retention and margin. The data is **simulated**: the advertisers are fictional, and I simulated the problems a growth manager typically meets, then built the checks that catch them. The SQL runs on DuckDB.

## What the analysis finds

| Finding | The number | What I'd do |
| --- | --- | --- |
| One account carries the book | Emberfall Legends: 53% of spend, 54% of margin | Review it first, every day |
| Its revenue dropped while installs held | Account D7 revenue −14% in 14 days; installs +1% | Traced to US iOS from 8 Sep: revenue per install −39%, retention flat. Likely a tracking or monetization change, so raise it with the advertiser before cutting bids (~€245k monthly margin at risk) |
| A segment leaves budget unspent | Tidepool Puzzle DE Android: 55% cap fill, D7 ROAS 0.31 vs 0.20 target | Bid up to 90% fill: ~€25k more margin a month |
| A segment spends fully but misses target | Coinmoth FR iOS: D7 ROAS 0.109 vs 0.18 target, 30% margin | Cut volume ~40%: costs ~€9k margin a month, protects a €125k-margin account |
| Brazil keeps thin margin | 20% margin vs ~38% elsewhere | Review reward levels in Brazil |

## Key concepts

- **D7 ROAS:** revenue the acquired users generate in their first 7 days ÷ what the advertiser spent. Always judged against the advertiser's target, by geo and OS.
- **Cap fill:** actual spend ÷ the advertiser's daily budget cap. Low fill with ROAS above target means budget is being left on the table.
- **Cohorts:** users grouped by install day. Only cohorts that have finished their 7 days are judged, which is why the newest week is excluded.
- **Retention:** the share of users still active after 1 and 7 days, a measure of user quality. Flat retention with falling revenue points to measurement or monetization, not worse users.
- **Margin:** what the advertiser pays minus the rewards paid to users. This is what the platform actually keeps.

## Files

| File | What it is |
| --- | --- |
| `Rewarded_UA_Account_Review.ipynb` | The analysis: SQL, charts and written takeaways |
| `queries.sql` | All queries with comments explaining each SQL concept |
| `daily_performance.csv` | Simulated daily data per advertiser, geo and OS (1 Aug – 29 Sep 2026) |
| `roas_targets.csv` | Each advertiser's D7 ROAS target |

To run it yourself: open the notebook in Google Colab, choose Runtime → Run all, and upload the two CSV files when asked.

---

Achintya Rawal · [LinkedIn](https://linkedin.com/in/achintya-rawal)
