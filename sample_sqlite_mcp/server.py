#!/usr/bin/env python3
import os
import aiosqlite
import asyncio
from fastmcp import FastMCP
from pydantic import BaseModel
from typing import List, Dict, Any
from dotenv import load_dotenv
import logging


logging.basicConfig(level=logging.INFO, format='%(asctime)s [%(levelname)s] %(message)s')
logger = logging.getLogger(__name__)

load_dotenv()

DB_PATH = os.getenv("DB_PATH", "sample.db")
MCP_PORT = int(os.getenv("MCP_PORT", "8080"))
READ_ONLY = os.getenv("READ_ONLY", "true").lower() == "true"

# Models
class QueryRequest(BaseModel):
    query: str

class TableRequest(BaseModel):
    table_name: str

class SampleDataRequest(BaseModel):
    table_name: str
    count: int = 5

class FeedbackRequest(BaseModel):
    user: str
    email: str
    feedback: str

app = FastMCP(
    title="Sample SQLite MCP Server",
    description="An Sample MCP Server to run with SQLite Databases",
    version="0.0.0"
)

# DB Connection
async def get_db():
    db = await aiosqlite.connect(DB_PATH)
    db.row_factory = aiosqlite.Row
    return db

# Initialize DB with Vultr-specific tables
async def init_db():
    if not os.path.exists(DB_PATH):
        db = await get_db()
        try:
            await db.execute('''
                CREATE TABLE vultr_products (
                    id INTEGER PRIMARY KEY,
                    name TEXT NOT NULL,
                    category TEXT NOT NULL
                )
            ''')
            await db.execute('''
                CREATE TABLE vultr_product_pricing (
                    id INTEGER PRIMARY KEY,
                    product_id INTEGER,
                    region TEXT,
                    price_per_month REAL,
                    price_per_hour REAL,
                    FOREIGN KEY(product_id) REFERENCES vultr_products(id)
                )
            ''')
            await db.commit()
            logger.info(f"Created new sample.db with Vultr tables.")
        finally:
            await db.close()

# Validate SQL
def validate_query(query: str) -> bool:
    query = query.strip().lower()
    dangerous_keywords = ["drop", "delete", "truncate", "alter", "update", "pragma", "attach", "detach"]
    if READ_ONLY:
        dangerous_keywords.extend(["insert", "create", "update"])

    return not any(keyword in query for keyword in dangerous_keywords)

# Tool: Execute SQL
@app.tool("execute_query")
async def execute_query(request: QueryRequest) -> Dict[str, Any]:
    if not validate_query(request.query):
        return {
            "error": "Query blocked by validation.",
            "read_only_mode": READ_ONLY
        }
    db = await get_db()
    try:
        cursor = await db.execute(request.query)
        rows = await cursor.fetchall()
        columns = [col[0] for col in cursor.description] if cursor.description else []
        return {
            "columns": columns,
            "rows": [dict(zip(columns, row)) for row in rows],
            "row_count": len(rows)
        }
    except Exception as e:
        return {"error": str(e)}
    finally:
        await db.close()

# Tool: List tables
@app.tool("list_tables")
async def list_tables() -> Dict[str, Any]:
    db = await get_db()
    try:
        cursor = await db.execute(
            "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'"
        )
        tables = [row[0] for row in await cursor.fetchall()]
        return {"tables": tables}
    except Exception as e:
        return {"error": str(e)}
    finally:
        await db.close()

# Tool: Describe table
@app.tool("describe_table")
async def describe_table(request: TableRequest) -> Dict[str, Any]:
    db = await get_db()
    try:
        cursor = await db.execute(f"PRAGMA table_info({request.table_name})")
        schema = [{
            "name": col[1],
            "type": col[2],
            "notnull": bool(col[3]),
            "default_value": col[4],
            "is_primary_key": bool(col[5])
        } for col in await cursor.fetchall()]
        return {"table_name": request.table_name, "columns": schema}
    except Exception as e:
        return {"error": str(e)}
    finally:
        await db.close()

# Tool: Count rows
@app.tool("count_rows")
async def count_rows(request: TableRequest) -> Dict[str, Any]:
    db = await get_db()
    try:
        cursor = await db.execute(f"SELECT COUNT(*) FROM {request.table_name}")
        count = (await cursor.fetchone())[0]
        return {"table_name": request.table_name, "row_count": count}
    except Exception as e:
        return {"error": str(e)}
    finally:
        await db.close()

# Tool: Insert Vultr sample data
@app.tool("insert_sample_data")
async def insert_sample_data(request: SampleDataRequest) -> Dict[str, Any]:
    if READ_ONLY:
        return {"error": "Read-only mode enabled"}

    db = await get_db()
    try:
        inserted = 0
        if request.table_name == "vultr_products":
            products = [
                ("Cloud Compute", "Compute"),
                ("High Frequency", "Compute"),
                ("Object Storage", "Storage"),
                ("Load Balancer", "Network"),
                ("Bare Metal", "Dedicated")
            ]
            for name, category in products:
                await db.execute(
                    "INSERT INTO vultr_products (name, category) VALUES (?, ?)", (name, category)
                )
                inserted += 1

        elif request.table_name == "vultr_product_pricing":
            pricing = [
                (1, "New York", 6.00, 0.009),
                (2, "New York", 7.00, 0.010),
                (3, "Chicago", 5.00, 0.007),
                (4, "San Francisco", 10.00, 0.014),
                (5, "London", 120.00, 0.180)
            ]
            for product_id, region, per_month, per_hour in pricing:
                await db.execute(
                    "INSERT INTO vultr_product_pricing (product_id, region, price_per_month, price_per_hour) VALUES (?, ?, ?, ?)",
                    (product_id, region, per_month, per_hour)
                )
                inserted += 1
        else:
            return {"error": f"No sample generator for {request.table_name}"}

        await db.commit()
        return {
            "table_name": request.table_name,
            "inserted_rows": inserted,
            "success": True
        }

    except Exception as e:
        return {"error": str(e)}
    finally:
        await db.close()

# MCP Server Main
async def main():
    await init_db()
    logger.info(f"Starting SQLite MCP Server on port {MCP_PORT}")
    logger.info(f"Using database at {DB_PATH}")
    logger.info(f"Read-only mode: {READ_ONLY}")
    return await app.run_async(transport="stdio")

if __name__ == "__main__":
    asyncio.run(main())
