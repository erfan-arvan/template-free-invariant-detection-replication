# Oca Token Usage and API Cost

Pricing used throughout:

- Input: **$0.40 per 1M tokens**
- Output: **$1.60 per 1M tokens**

## Prompt / Context Study

| Project | Input tokens | Output tokens | Total tokens | Cost |
|---|---:|---:|---:|---:|
| Apollo | 1,241,025 | 235,075 | 1,476,100 | $0.8725 |
| Dubbo | 16,519,086 | 2,378,921 | 18,898,007 | $10.4139 |
| Hudi | 570,493 | 101,514 | 672,007 | $0.3906 |
| libGDX | 21,152,431 | 1,940,372 | 23,092,803 | $11.5656 |
| Netty | 10,121,774 | 1,112,694 | 11,234,468 | $5.8290 |
| Spring | 14,266,704 | 1,725,218 | 15,991,922 | $8.4670 |
| **Subtotal** | **63,871,513** | **7,493,794** | **71,365,307** | **$37.5387** |

## Usefulness Study

JxPath is excluded.

| Project | Input tokens | Output tokens | Total tokens | Cost |
|---|---:|---:|---:|---:|
| Cli_40f | 1,288,979 | 84,818 | 1,373,797 | $0.6513 |
| Codec_18f | 3,742,282 | 223,507 | 3,965,789 | $1.8545 |
| Collections_28f | 19,864,845 | 1,595,817 | 21,460,662 | $10.4992 |
| Gson_18f | 3,103,251 | 223,456 | 3,326,707 | $1.5988 |
| Math_106f | 4,750,652 | 404,883 | 5,155,535 | $2.5481 |
| **Subtotal** | **32,750,009** | **2,532,481** | **35,282,490** | **$17.1520** |

## Combined Total

| Input tokens | Output tokens | Total tokens | Total cost |
|---:|---:|---:|---:|
| **96,621,522** | **10,026,275** | **106,647,797** | **$54.6906** |

The usefulness-study output-token counts include the estimation procedure used by
`summarize_oca_token_cost.py` for prompts without a recorded cassette response.
