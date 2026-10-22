"""
Load the raw Online Retail II data into a SQLite database (retail.db), unchanged.
All cleaning and modelling happens afterwards in SQL (see sql/01_data_cleaning.sql).

Data: Online Retail II, UCI Machine Learning Repository (CC BY 4.0)
      https://archive.ics.uci.edu/dataset/502/online+retail+ii

Usage:
    1. Download and unzip the dataset so online_retail_II.xlsx sits in this folder
    2. python load_data.py
"""
import sqlite3
from pathlib import Path

import pandas as pd

RAW_FILE = Path("online_retail_II.xlsx")
DB_FILE = Path("retail.db")

COLUMNS = {"Invoice": "invoice", "StockCode": "stock_code", "Description": "description",
           "Quantity": "quantity", "InvoiceDate": "invoice_date", "Price": "price",
           "Customer ID": "customer_id", "Country": "country"}


def main() -> None:
    print(f"Reading {RAW_FILE} (both sheets, takes a few minutes)...")
    sheets = pd.read_excel(RAW_FILE, sheet_name=None, dtype={"Invoice": str, "StockCode": str})
    frames = []
    for name, df in sheets.items():
        df = df.rename(columns=COLUMNS)
        df["invoice_date"] = df["invoice_date"].dt.strftime("%Y-%m-%d %H:%M:%S")
        df["customer_id"] = df["customer_id"].astype("Int64")      # 12345.0 -> 12345, keeps NULLs
        df["source_sheet"] = name
        frames.append(df)
    raw = pd.concat(frames, ignore_index=True)

    DB_FILE.unlink(missing_ok=True)
    with sqlite3.connect(DB_FILE) as con:
        raw.to_sql("raw_transactions", con, index=False, chunksize=50_000)
    print(f"Loaded {len(raw):,} rows into {DB_FILE} -> table raw_transactions")


if __name__ == "__main__":
    main()
