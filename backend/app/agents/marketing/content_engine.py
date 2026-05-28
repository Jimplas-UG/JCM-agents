"""Template-based content generation for JCM marketing (no trading decisions)."""

from datetime import date, datetime, timedelta, timezone
from typing import Any

from app.agents.marketing.brand_kit import (
    CHANNELS,
    COMPLIANCE_FOOTER,
    HASHTAGS,
    MASTER_BRAND_LINE,
    PILLAR_LABELS,
    PODCAST_EPISODES,
    SOCIAL_FOOTER,
    validate_content,
)


class ContentEngine:
    """Generates platform-specific drafts from brand pillars and templates."""

    def generate_weekly_batch(self, week_start: date | None = None) -> list[dict[str, Any]]:
        start = week_start or date.today()
        items: list[dict[str, Any]] = []

        items.append(self.linkedin_infrastructure_post())
        items.append(self.linkedin_tbills_post())
        items.append(self.linkedin_smart_money_2026())
        items.extend(self.x_thread_infrastructure())
        items.extend(self.x_standalone_batch())
        items.append(self.instagram_carousel_tbills())
        items.append(self.instagram_founder_caption())
        items.append(self.instagram_podcast_cta())
        items.append(self.instagram_fintrix_pillars())

        for i, item in enumerate(items):
            scheduled = datetime.combine(
                start + timedelta(days=i % 7),
                datetime.min.time(),
                tzinfo=timezone.utc,
            ).replace(hour=9 + (i % 8))
            item["scheduled_for"] = scheduled.isoformat()
            item["compliance_warnings"] = validate_content(item["body"])

        return items

    def linkedin_infrastructure_post(self) -> dict[str, Any]:
        body = f"""The future of finance is not louder trading. It is better systems.

Most markets still run on delay — capital sitting idle, decisions trapped in spreadsheets, and intelligence scattered across tools that never connect.

At Jimplas Capital Management, we are building financial intelligence infrastructure from Gulu outward:

→ Advisory discipline — portfolios aligned to objectives, risk, and time horizon
→ Systematic technology — automation and observability over emotion
→ Capital-flow intelligence — including Fintrix: Flow · Intelligence · Access

We are not selling guaranteed returns. We are building process, data, and infrastructure — with roots in Uganda and ambition across global markets.

What does "financial infrastructure" mean in your market?{SOCIAL_FOOTER}{COMPLIANCE_FOOTER}"""

        return {
            "platform": "linkedin",
            "content_type": "post",
            "pillar": "infrastructure_first",
            "title": "Financial intelligence infrastructure",
            "body": body,
            "hashtags": HASHTAGS["linkedin"],
        }

    def linkedin_tbills_post(self) -> dict[str, Any]:
        ep = PODCAST_EPISODES[0]
        body = f"""Uganda Treasury bills are one of the most misunderstood "boring" assets in the market.

Boring is often exactly what conservative portfolios need.

On the Jimplas Podcast we break down how Bank of Uganda T-bills and bonds work — structured lending to government with transparency and a role in national development.

Who this is for:
• Investors seeking lower-volatility allocation
• Savers comparing formal fixed income vs informal alternatives
• Anyone building process-first portfolios in Uganda

▶️ {ep['title']}
🎧 Spotify & Apple — Jimplas Podcast{SOCIAL_FOOTER}{COMPLIANCE_FOOTER}"""

        return {
            "platform": "linkedin",
            "content_type": "post",
            "pillar": "african_capital_markets",
            "title": "Uganda T-bills explained",
            "body": body,
            "hashtags": HASHTAGS["linkedin"],
        }

    def linkedin_smart_money_2026(self) -> dict[str, Any]:
        body = f"""The financial world in 2026 is not rewarding the loudest voices. It is rewarding the most adaptive systems.

Three shifts we are watching at Jimplas Capital Management:

1. From speculation to infrastructure — observability and process matter as much as entry price
2. From global copy-paste to local depth — Uganda fixed income deserves serious analysis
3. From tax as afterthought to tax as strategy — structure matters for long-horizon capital

Smart capital builds discipline, technology, and clarity — not hype.

Where is your organization investing in systems this year?{SOCIAL_FOOTER}{COMPLIANCE_FOOTER}"""

        return {
            "platform": "linkedin",
            "content_type": "post",
            "pillar": "macro_literacy",
            "title": "Smart money in 2026",
            "body": body,
            "hashtags": HASHTAGS["linkedin"],
        }

    def x_thread_infrastructure(self) -> list[dict[str, Any]]:
        tweets = [
            "Financial intelligence infrastructure sounds abstract. Here is what it means in practice. 🧵",
            "1/ Advisory discipline — objectives first. Risk second. Returns follow process.",
            "2/ Systematic technology — automation replaces guesswork in volatile markets.",
            "3/ Capital-flow systems — Flow · Intelligence · Access. Capital should not sit idle.",
            "4/ We build from Gulu with global standards. African markets deserve institutional tools.",
            f"5/ 🎧 Jimplas Podcast · 🌐 jimplascapital.com · Educational only.",
        ]
        return [
            {
                "platform": "x",
                "content_type": "thread",
                "pillar": "infrastructure_first",
                "title": f"Infrastructure thread {i + 1}/{len(tweets)}",
                "body": t,
                "hashtags": HASHTAGS["x"] if i == len(tweets) - 1 else [],
                "metadata": {"thread_id": "infra_001", "thread_index": i, "thread_total": len(tweets)},
            }
            for i, t in enumerate(tweets)
        ]

    def x_standalone_batch(self) -> list[dict[str, Any]]:
        posts = [
            (
                "infrastructure_first",
                "The best investors in 2026 won't have the best signals. They'll have the best systems.",
            ),
            (
                "african_capital_markets",
                "Uganda T-bills aren't secret alpha. They're structured fixed income. We break it down on Jimplas Podcast.",
            ),
            (
                "quant_discipline",
                "We don't promise returns on social media. We promise clarity, process, and respect for risk.",
            ),
            (
                "education_trust",
                "African fintech isn't a charity narrative. It's a builder narrative. Global-grade from local roots.",
            ),
        ]
        return [
            {
                "platform": "x",
                "content_type": "post",
                "pillar": pillar,
                "title": f"X post — {pillar}",
                "body": text + f"\n\n🌐 {CHANNELS.website}",
                "hashtags": HASHTAGS["x"],
            }
            for pillar, text in posts
        ]

    def instagram_carousel_tbills(self) -> dict[str, Any]:
        slides = [
            "Slide 1: Uganda Treasury bills — the conservative investor's primer",
            "Slide 2: BOU issues bills on behalf of government",
            "Slide 3: Think short-term lending — structured, transparent",
            "Slide 4: Role in conservative portfolios",
            "Slide 5: Full episode — Jimplas Podcast (link in bio)",
        ]
        body = "Uganda T-bills explained 👇\n\n" + "\n\n".join(slides)
        body += f"\n\nNot advice. Education.\n🎧 Jimplas Podcast\n{CHANNELS.spotify_podcast}"
        return {
            "platform": "instagram",
            "content_type": "carousel",
            "pillar": "african_capital_markets",
            "title": "T-bills carousel",
            "body": body,
            "hashtags": HASHTAGS["instagram"],
            "metadata": {"slides": slides},
        }

    def instagram_founder_caption(self) -> dict[str, Any]:
        body = """2022 — started in Gulu with a belief: African investors deserve institutional-grade thinking.

2026 — building advisory, education, and financial intelligence infrastructure.

Thank you for trusting the journey.

— Billy William Onen
CEO, Jimplas Capital Management"""
        return {
            "platform": "instagram",
            "content_type": "post",
            "pillar": "founder_story",
            "title": "Founder milestone",
            "body": body,
            "hashtags": HASHTAGS["instagram"],
        }

    def instagram_podcast_cta(self) -> dict[str, Any]:
        body = """New to markets? Start on Jimplas Podcast:

1️⃣ Investment guide for beginners
2️⃣ Uganda T-bills & bonds
3️⃣ Bitcoin halving (context, not hype)

Link in bio 🎧"""
        return {
            "platform": "instagram",
            "content_type": "post",
            "pillar": "podcast_repurpose",
            "title": "Podcast start here",
            "body": body,
            "hashtags": HASHTAGS["instagram"],
        }

    def instagram_fintrix_pillars(self) -> dict[str, Any]:
        body = """Fintrix — capital movement reimagined

⚡ Flow — capital moves without friction
🧠 Intelligence — data over delay
🌍 Access — opportunity without borders

Financial infrastructure redesigned.
Built from Gulu."""
        return {
            "platform": "instagram",
            "content_type": "post",
            "pillar": "capital_movement_fintrix",
            "title": "Fintrix pillars",
            "body": body,
            "hashtags": HASHTAGS["instagram"],
        }

    def generate_from_pillar(self, pillar: str, platform: str = "linkedin") -> dict[str, Any]:
        generators = {
            "infrastructure_first": self.linkedin_infrastructure_post,
            "african_capital_markets": self.linkedin_tbills_post,
            "macro_literacy": self.linkedin_smart_money_2026,
        }
        gen = generators.get(pillar, self.linkedin_infrastructure_post)
        item = gen()
        item["platform"] = platform
        item["compliance_warnings"] = validate_content(item["body"])
        return item

    def get_brand_summary(self) -> dict[str, Any]:
        return {
            "master_line": MASTER_BRAND_LINE,
            "channels": {
                "website": CHANNELS.website,
                "linkedin": CHANNELS.linkedin,
                "instagram": CHANNELS.instagram,
                "x": CHANNELS.x_twitter,
                "spotify": CHANNELS.spotify_podcast,
            },
            "pillars": {k: PILLAR_LABELS[k] for k in PILLAR_LABELS},
            "podcast_episodes": PODCAST_EPISODES,
        }
