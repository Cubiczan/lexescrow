"""
LexEscrow Compliance Oracle - Offline Test Mode
Runs a mock sweep without calling Tavily, for demo/local dev.
"""
import json
import hashlib
from datetime import datetime, timezone
from main import compute_risk_score, sha256_hash


def mock_tavily_response(entity_name: str, jurisdiction: str, blocked: bool = False) -> dict:
    """Simulate a Tavily API response for demo purposes."""
    if blocked:
        ai_summary = (
            f"{entity_name} appears on the OFAC Specially Designated Nationals "
            f"(SDN) list as of June 2026. The entity was indicted for money "
            f"laundering in {jurisdiction} federal court. Multiple enforcement "
            f"actions have been filed by FinCEN."
        )
        sources = [
            {"url": "https://home.treasury.gov/policy-issues/financial-sanctions/specially-designated-nationals-list"},
            {"url": "https://www.fincen.gov/news/news-releases/fincen-enforcement-action-2026"},
            {"url": "https://www.justice.gov/opa/pr/indictment-money-laundering-scheme"},
        ]
    else:
        ai_summary = (
            f"No adverse information found for {entity_name} in jurisdiction "
            f"{jurisdiction}. Entity does not appear on OFAC SDN list, has no "
            f"PEP (Politically Exposed Person) status, and no recent fraud "
            f"indictments, money laundering investigations, or enforcement "
            f"actions were identified in regulatory databases."
        )
        sources = [
            {"url": "https://home.treasury.gov/policy-issues/financial-sanctions/specially-designated-nationals-list"},
            {"url": "https://www.fincen.gov/"},
            {"url": "https://ec.europa.eu/info/business-economy-euro/banking-and-finance/financial-sanctions-list"},
            {"url": "https://www.gov.uk/government/collections/financial-sanctions-consolidated-list"},
            {"url": "https://www.fatf-gafi.org/en/publications/high-risk-and-other-monitored-jurisdictions.html"},
        ]

    return {"answer": ai_summary, "results": sources}


def run_offline_test():
    """Run offline test with mock data."""
    print("=" * 60)
    print("LexEscrow Compliance Oracle - Offline Test")
    print("=" * 60)

    # Test Case 1: Clean entity
    print("\n--- Test 1: Clean Entity ---")
    entity = "Meridian Capital Holdings"
    jurisdiction = "US"
    resp = mock_tavily_response(entity, jurisdiction, blocked=False)
    risk = compute_risk_score(resp["answer"])
    print(f"  Entity: {entity}")
    print(f"  Jurisdiction: {jurisdiction}")
    print(f"  Risk Score: {risk}")
    print(f"  Status: {'BLOCKED' if risk > 0 else 'CLEARED'}")
    print(f"  Summary: {resp['answer'][:120]}...")
    assert risk == 0, "Clean entity should have risk 0"

    # Test Case 2: Blocked entity
    print("\n--- Test 2: Blocked Entity (OFAC) ---")
    entity = "Nordic Shipping AS"
    jurisdiction = "EU"
    resp = mock_tavily_response(entity, jurisdiction, blocked=True)
    risk = compute_risk_score(resp["answer"])
    print(f"  Entity: {entity}")
    print(f"  Jurisdiction: {jurisdiction}")
    print(f"  Risk Score: {risk}")
    print(f"  Status: {'BLOCKED' if risk > 0 else 'CLEARED'}")
    print(f"  Summary: {resp['answer'][:120]}...")
    assert risk > 0, "Blocked entity should have risk > 0"

    # Test Case 3: On-chain data format
    print("\n--- Test 3: On-Chain Data Format ---")
    entity = "Apex Ventures Fund II LP"
    jurisdiction = "US"
    resp = mock_tavily_response(entity, jurisdiction, blocked=False)
    summary_hash = sha256_hash(resp["answer"])
    source_urls = [s["url"] for s in resp["results"][:5]]
    source_hashes = [sha256_hash(url) for url in source_urls]
    while len(source_hashes) < 5:
        source_hashes.append([0] * 32)

    on_chain_payload = {
        "summary_hash": summary_hash,
        "summary_truncated": resp["answer"][:256],
        "risk_score": 0,
        "source_count": len(source_urls),
        "source_hashes": source_hashes,
        "checked_at": datetime.now(timezone.utc).isoformat(),
    }
    print(f"  Summary hash (first 8): {summary_hash[:8]}")
    print(f"  Sources: {on_chain_payload['source_count']}")
    print(f"  Truncated length: {len(on_chain_payload['summary_truncated'])}")
    assert len(summary_hash) == 32, "Hash must be 32 bytes"
    assert len(source_hashes) == 5, "Must have 5 source hash slots"

    print("\n" + "=" * 60)
    print("All tests passed!")
    print("=" * 60)


if __name__ == "__main__":
    run_offline_test()
