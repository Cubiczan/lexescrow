import hashlib
import json
import os
import sys
import requests
from datetime import datetime, timezone
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from typing import Optional

# ══════════════════════════════════════════════
# LexEscrow Compliance Oracle
# Adapted from: icohangar-ops/complyai + market-radar
# Hackathon: BLI Legal Tech Hackathon 2026
# ══════════════════════════════════════════════

TAVILY_API_KEY = os.getenv("TAVILY_API_KEY", "tvly-dev-yourKeyHere")
TAVILY_SEARCH_URL = "https://api.tavily.com/search"

app = FastAPI(title="LexEscrow Compliance Oracle", version="0.1.0")

# Legal heuristic: high-risk compliance keywords
BLOCK_KEYWORDS = [
    "sanctioned", "ofac", "indicted", "money laundering",
    "fraud", "pep", "politically exposed", "specially designated nationals",
    "banned", "prohibited", "enforcement action", "criminal charges",
    "seized", "frozen assets", "terrorist financing", "bribery",
    "corruption", "racketeering", "embezzlement",
]

# Keyword weights (some are more severe)
KEYWORD_WEIGHTS = {
    "sanctioned": 20, "ofac": 20, "indicted": 15,
    "money laundering": 20, "terrorist financing": 25,
    "fraud": 15, "bribery": 15, "corruption": 10,
    "pep": 10, "politically exposed": 10,
    "specially designated nationals": 20, "enforcement action": 10,
    "criminal charges": 15, "seized": 15, "frozen assets": 15,
    "banned": 10, "prohibited": 10, "racketeering": 15,
    "embezzlement": 15,
}


def compute_risk_score(ai_summary: str) -> int:
    """
    Compute a risk score (0-100) from the AI compliance summary.
    Higher-weighted keywords contribute more to the score.
    """
    summary_lower = ai_summary.lower()
    score = 0
    for keyword, weight in KEYWORD_WEIGHTS.items():
        if keyword in summary_lower:
            score += weight
    return min(score, 100)


def sha256_hash(data: str) -> list[int]:
    """Return SHA-256 hash as a 32-byte list for on-chain storage."""
    return list(hashlib.sha256(data.encode()).digest())


class ComplianceRequest(BaseModel):
    entity_name: str
    jurisdiction: str  # e.g. "US", "UK", "EU"
    escrow_id: str


class ComplianceResponse(BaseModel):
    escrow_id: str
    entity: str
    jurisdiction: str
    status: str  # "CLEARED" or "BLOCKED"
    risk_score: int
    compliance_summary: str
    summary_hash: list[int]  # 32 bytes
    summary_truncated: str  # max 256 chars for on-chain
    source_count: int
    source_hashes: list[list[int]]  # up to 5 x 32 bytes
    regulatory_sources: list[str]
    checked_at: str  # ISO 8601


@app.post("/api/compliance/check", response_model=ComplianceResponse)
async def check_compliance(req: ComplianceRequest):
    """
    Perform a real-time AI sweep of sanctions, PEP lists, and adverse media
    before a law firm releases escrow funds.
    """
    # Craft jurisdiction-specific legal compliance query
    search_query = f"""
    OFAC sanctions list, {req.jurisdiction} financial enforcement actions,
    PEP (Politically Exposed Person) status, or recent adverse media
    (fraud indictment, bankruptcy filing, money laundering investigation)
    involving entity or person "{req.entity_name}" in the last 30 days.
    """

    payload = {
        "api_key": TAVILY_API_KEY,
        "query": search_query.strip(),
        "search_depth": "advanced",  # Deep search for regulatory databases
        "include_answer": True,
        "max_results": 5,
    }

    try:
        response = requests.post(TAVILY_SEARCH_URL, json=payload, timeout=30)
        response.raise_for_status()
        data = response.json()
    except requests.RequestException as e:
        raise HTTPException(status_code=502, detail=f"Tavily API error: {str(e)}")

    ai_summary = data.get("answer", "No adverse information found.")
    sources = data.get("results", [])

    # Compute risk score
    risk_score = compute_risk_score(ai_summary)
    status = "BLOCKED" if risk_score > 0 else "CLEARED"

    # Prepare on-chain data
    summary_hash = sha256_hash(ai_summary)
    summary_truncated = ai_summary[:256]

    # Hash source URLs for on-chain storage
    source_urls = [s.get("url", "") for s in sources[:5]]
    source_hashes = [sha256_hash(url) for url in source_urls]
    # Pad to 5 if fewer sources
    while len(source_hashes) < 5:
        source_hashes.append([0] * 32)

    checked_at = datetime.now(timezone.utc).isoformat()

    return ComplianceResponse(
        escrow_id=req.escrow_id,
        entity=req.entity_name,
        jurisdiction=req.jurisdiction,
        status=status,
        risk_score=risk_score,
        compliance_summary=ai_summary,
        summary_hash=summary_hash,
        summary_truncated=summary_truncated,
        source_count=len(sources),
        source_hashes=source_hashes,
        regulatory_sources=source_urls,
        checked_at=checked_at,
    )


@app.get("/api/health")
async def health():
    return {"status": "ok", "service": "lexescrow-compliance-oracle", "version": "0.1.0"}


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8001)
