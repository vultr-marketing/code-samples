#!/usr/bin/env python3
import os
import aiosqlite
import asyncio
from fastmcp import FastMCP
from pydantic import BaseModel
from typing import Dict, Any
from dotenv import load_dotenv
import logging

# Setup logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s [%(levelname)s] %(message)s')
logger = logging.getLogger(__name__)

# Load environment variables
load_dotenv()
DB_PATH = os.getenv("DB_PATH", "sample.db")
MCP_PORT = int(os.getenv("MCP_PORT", "8080"))
READ_ONLY = os.getenv("READ_ONLY", "true").lower() == "true"

# Pydantic models for requests
class QueryRequest(BaseModel):
    query: str

class TableRequest(BaseModel):
    table_name: str

class SampleDataRequest(BaseModel):
    table_name: str
    count: int = 5

# Init FastMCP app
app = FastMCP(
    title="Remote SQLite MCP Server",
    description="An MCP Server to run SQLite queries remotely",
    version="1.0.0"
)

# Connect to database
async def get_db():
    db = await aiosqlite.connect(DB_PATH)
    db.row_factory = aiosqlite.Row
    return db

# Create initial tables if DB doesn't exist
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
            logger.info("Database initialized.")
        finally:
            await db.close()

# Query validator
def validate_query(query: str) -> bool:
    query = query.strip().lower()
    bad_keywords = ["drop", "delete", "truncate", "alter", "pragma", "attach", "detach"]
    if READ_ONLY:
        bad_keywords += ["insert", "update", "create"]
    return not any(k in query for k in bad_keywords)

# Tool: Execute query
@app.tool("execute_query")
async def execute_query(req: QueryRequest) -> Dict[str, Any]:
    if not validate_query(req.query):
        return {"error": "Query blocked by validation.", "read_only_mode": READ_ONLY}
    db = await get_db()
    try:
        cursor = await db.execute(req.query)
        rows = await cursor.fetchall()
        cols = [col[0] for col in cursor.description] if cursor.description else []
        return {
            "columns": cols,
            "rows": [dict(zip(cols, row)) for row in rows],
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
        cursor = await db.execute("SELECT name FROM sqlite_master WHERE type='table'")
        tables = [row[0] for row in await cursor.fetchall()]
        return {"tables": tables}
    finally:
        await db.close()

# Tool: Describe table
@app.tool("describe_table")
async def describe_table(req: TableRequest) -> Dict[str, Any]:
    db = await get_db()
    try:
        cursor = await db.execute(f"PRAGMA table_info({req.table_name})")
        info = [{
            "name": col[1],
            "type": col[2],
            "notnull": bool(col[3]),
            "default": col[4],
            "pk": bool(col[5])
        } for col in await cursor.fetchall()]
        return {"columns": info}
    finally:
        await db.close()

# Tool: Insert sample data
@app.tool("insert_sample_data")
async def insert_sample_data(req: SampleDataRequest) -> Dict[str, Any]:
    if READ_ONLY:
        return {"error": "Server is in read-only mode."}
    db = await get_db()
    try:
        inserted = 0
        if req.table_name == "vultr_products":
            data = [("Cloud Compute", "Compute"), ("Object Storage", "Storage")]
            for name, cat in data:
                await db.execute("INSERT INTO vultr_products (name, category) VALUES (?, ?)", (name, cat))
                inserted += 1
        elif req.table_name == "vultr_product_pricing":
            data = [(1, "New York", 5.0, 0.007), (2, "Amsterdam", 6.0, 0.008)]
            for pid, reg, mon, hr in data:
                await db.execute("INSERT INTO vultr_product_pricing (product_id, region, price_per_month, price_per_hour) VALUES (?, ?, ?, ?)", (pid, reg, mon, hr))
                inserted += 1
        await db.commit()
        return {"inserted_rows": inserted}
    finally:
        await db.close()

# Start the server using SSE transport for remote access
async def main():
    await init_db()
    logger.info(f"Starting SQLite MCP Server on port {MCP_PORT}")
    logger.info(f"Using database at {DB_PATH}")
    logger.info(f"Read-only mode: {READ_ONLY}")
    await app.run_async(transport="sse", host="0.0.0.0", port=MCP_PORT)

if __name__ == "__main__":
    asyncio.run(main())
