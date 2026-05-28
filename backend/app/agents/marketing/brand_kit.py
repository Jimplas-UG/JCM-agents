"""JCM brand kit — canonical voice, channels, compliance."""

from dataclasses import dataclass


@dataclass(frozen=True)
class ChannelLinks:
    website: str = "https://www.jimplascapital.com"
    linkedin: str = "https://www.linkedin.com/company/jimplas-capital-management"
    instagram: str = "https://www.instagram.com/Jimplascapital/"
    x_twitter: str = "https://x.com/JimplasE"
    spotify_podcast: str = "https://open.spotify.com/show/1614437575"
    apple_podcast: str = "https://podcasts.apple.com/us/podcast/jimplas-podcast/id1614437575"
    email: str = "info@jimplascapital.com"
    phone: str = "+256 775 477 555"
    hq: str = "Plot 29 Gulu Avenue, P.O. Box 362868, Gulu, Uganda"


CHANNELS = ChannelLinks()

MASTER_BRAND_LINE = (
    "Jimplas Capital Management builds and deploys financial intelligence "
    "infrastructure — from advisory and portfolio discipline to systematic "
    "technology, automation, and capital-flow systems — with roots in Gulu "
    "and ambition across global markets."
)

COMPLIANCE_FOOTER = (
    "\n\n—\nEducational content only. Not personalized investment advice. "
    "Past performance does not guarantee future results. Investing involves risk."
)

SOCIAL_FOOTER = (
    "\n\n🌐 jimplascapital.com\n🎧 Jimplas Podcast (Spotify & Apple)\n📍 Gulu, Uganda"
)

CONTENT_PILLARS = [
    "infrastructure_first",
    "african_capital_markets",
    "quant_discipline",
    "education_trust",
    "capital_movement_fintrix",
    "macro_literacy",
    "podcast_repurpose",
    "founder_story",
]

PILLAR_LABELS = {
    "infrastructure_first": "Infrastructure-first finance",
    "african_capital_markets": "African capital markets",
    "quant_discipline": "Quant discipline & risk",
    "education_trust": "Education & trust",
    "capital_movement_fintrix": "Capital movement / Fintrix",
    "macro_literacy": "Macro literacy",
    "podcast_repurpose": "Jimplas Podcast",
    "founder_story": "Founder & company story",
}

HASHTAGS = {
    "linkedin": [
        "#Fintech",
        "#QuantitativeFinance",
        "#AfricanFintech",
        "#CapitalMarkets",
        "#Uganda",
        "#InvestmentManagement",
    ],
    "instagram": [
        "#JimplasCapital",
        "#Gulu",
        "#UgandaFinance",
        "#InvestingEducation",
        "#FintechAfrica",
        "#Podcast",
    ],
    "x": ["#Markets", "#Macro", "#Uganda", "#Fintech", "#JimplasCapital"],
}

FORBIDDEN_PHRASES = [
    "guaranteed returns",
    "get rich",
    "passive income",
    "100% win",
    "can't lose",
    "financial freedom overnight",
    "secret strategy",
    "insider signal",
]

PODCAST_EPISODES = [
    {
        "title": "Invest in Bank of Uganda T-bills and T-Bonds",
        "hook": "Lending to government, explained for conservative portfolios",
        "pillar": "african_capital_markets",
    },
    {
        "title": "Jimplas Investment guide for Beginners",
        "hook": "Goals, diversification, discipline before returns",
        "pillar": "education_trust",
    },
    {
        "title": "Bitcoin Halving",
        "hook": "Supply mechanics without the hype",
        "pillar": "macro_literacy",
    },
]

TREND_TOPICS = [
    {"topic": "AI in financial infrastructure", "category": "ai_finance", "score": 0.92},
    {"topic": "African fintech and capital markets", "category": "african_fintech", "score": 0.95},
    {"topic": "Quantitative trading systems", "category": "quant_trading", "score": 0.88},
    {"topic": "Central bank digital currencies", "category": "cbdc", "score": 0.75},
    {"topic": "Uganda Treasury bills and bonds", "category": "fixed_income", "score": 0.98},
    {"topic": "Trading automation and VPS infrastructure", "category": "infra", "score": 0.85},
    {"topic": "Macro regime shifts 2026", "category": "macro", "score": 0.90},
    {"topic": "Institutional risk management", "category": "risk", "score": 0.87},
]


def validate_content(text: str) -> list[str]:
    """Return list of compliance warnings for draft content."""
    warnings = []
    lower = text.lower()
    for phrase in FORBIDDEN_PHRASES:
        if phrase in lower:
            warnings.append(f"Contains discouraged phrase: '{phrase}'")
    if "guarantee" in lower and "does not guarantee" not in lower:
        warnings.append("Uses 'guarantee' — ensure compliance context")
    return warnings
