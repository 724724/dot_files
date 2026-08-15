import importlib.util
import io
import json
import pathlib
import tempfile
import unittest
from contextlib import redirect_stdout
from datetime import datetime, timedelta, timezone
from unittest import mock


MODULE_PATH = pathlib.Path(__file__).resolve().parents[1] / "news-fetch.py"
SPEC = importlib.util.spec_from_file_location("news_fetch", MODULE_PATH)
NEWS_FETCH = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(NEWS_FETCH)


class NewsFetchTests(unittest.TestCase):
    def test_clean_text_preserves_quoted_korean_headline(self):
        title = "[반론보도] <피감기관 감사 과정에 일부 개입한 경찰공제회 팀장…징계 받았다> 관련"
        raw = "<strong>[반론보도]</strong> &lt;피감기관 감사 과정에 일부 개입한 경찰공제회 팀장…징계 받았다&gt; 관련"
        self.assertEqual(NEWS_FETCH.clean_text(raw), title)
        self.assertEqual(NEWS_FETCH.clean_text(title), title)

    def test_joongang_html_item_keeps_angle_bracket_text(self):
        title = "[반론보도] <피감기관 감사 과정에 일부 개입한 경찰공제회 팀장…징계 받았다> 관련"
        page = (
            '<a href="https://www.joongang.co.kr/article/25445967">'
            '[반론보도] &lt;피감기관 감사 과정에 일부 개입한 경찰공제회 팀장…징계 받았다&gt; 관련'
            "</a>"
        )
        items = NEWS_FETCH.html_items(page, "joongang", "society")
        self.assertEqual(items[0]["title"], title)

    def test_joongang_visible_headline_replaces_image_alt(self):
        title = "“읽고 쓰는 법 못배운다” 초등생 AI 아예 금지시킨 나라"
        url = "https://www.joongang.co.kr/article/25446040"
        page = (
            f'<a href="{url}"><img src="https://example.com/t.jpg" '
            'alt="t.jpg&ldquo;읽고 쓰는 법 못배운다&rdquo; 초등생 AI 아예 금지시킨 나라"></a>'
            f'<h2><a href="{url}">&ldquo;읽고 쓰는 법 못배운다&rdquo; 초등생 AI 아예 금지시킨 나라</a></h2>'
        )
        items = NEWS_FETCH.html_items(page, "joongang", "culture")
        self.assertEqual(items[0]["title"], title)

    def test_stock_news_keeps_only_selected_company_within_three_days(self):
        now = 1_800_000_000
        recent = datetime.fromtimestamp(now - 60, timezone.utc).isoformat(timespec="minutes")
        old = datetime.fromtimestamp(now - NEWS_FETCH.STOCK_NEWS_WINDOW - 60, timezone.utc).isoformat(timespec="minutes")
        items = [
            {"title": "삼성전자, 신규 반도체 공개", "summary": "", "url": "https://example.com/1", "published": recent},
            {"title": "SK하이닉스 주가 상승", "summary": "", "url": "https://example.com/2", "published": recent},
            {"title": "삼성전자 과거 기사", "summary": "", "url": "https://example.com/3", "published": old},
        ]
        result = NEWS_FETCH.recent_stock_items(items, "삼성전자", "005930", now=now)
        self.assertEqual([item["url"] for item in result], ["https://example.com/1"])

    def test_stock_news_drops_aggregator_and_gambling_story_noise(self):
        now = 1_800_000_000
        recent = datetime.fromtimestamp(now - 60, timezone.utc).isoformat(timespec="minutes")
        items = [
            {"title": "삼성전자, 갤럭시 신제품 공개", "summary": "", "url": "https://example.com/1", "published": recent},
            {"title": "2026-07-22 코스피 오늘 인기종목 30개 주식시황 알아보기 (+ 삼성전자)", "summary": "", "url": "https://example.com/2", "published": recent},
            {"title": "곽범 \"삼성전자 주식 6만원 때 1억 투자\" 첫 투자 대박에도 씁쓸한 이유", "summary": "", "url": "https://example.com/3", "published": recent},
            {"title": "엇갈린 초고수 투심…삼성전자 담고 SK하이닉스는 던졌다", "summary": "", "url": "https://example.com/4", "published": recent},
            {"title": "삼성전자 2분기 실적 발표", "summary": "", "url": "https://example.com/5", "published": recent},
        ]
        result = NEWS_FETCH.recent_stock_items(items, "삼성전자", "005930", now=now)
        self.assertEqual(
            [item["url"] for item in result],
            ["https://example.com/1", "https://example.com/5"],
        )

    def test_stock_feed_fetches_company_news_without_stock_anchor(self):
        calls = []

        def record(query, market, relation_type, relation_topic):
            calls.append(query)
            return []

        with mock.patch.object(NEWS_FETCH, "fetch_google_stock_feed", side_effect=record):
            NEWS_FETCH.fetch_stock_feed("삼성전자", "005930", "KRX")

        self.assertTrue(any("주식" not in call for call in calls))
        self.assertTrue(any("주식" in call for call in calls))

    def test_google_stock_feed_does_not_treat_publisher_name_as_naver_evidence(self):
        feed = """<?xml version="1.0" encoding="UTF-8"?>
        <rss><channel><item>
          <title>가민 사상 최대 분기 실적 - 네이버 프리미엄콘텐츠</title>
          <link>https://example.com/premium</link>
          <description><![CDATA[<a>가민 사상 최대 분기 실적</a> 네이버 프리미엄콘텐츠]]></description>
          <pubDate>Sun, 02 Aug 2026 12:00:00 GMT</pubDate>
          <source>네이버 프리미엄콘텐츠</source>
        </item><item>
          <title>아우디 Q9 공개 : 네이버 블로그 - Naver Blog</title>
          <link>https://example.com/blog</link>
          <description><![CDATA[<a>아우디 Q9 공개 : 네이버 블로그</a> Naver Blog]]></description>
          <pubDate>Sun, 02 Aug 2026 12:00:00 GMT</pubDate>
          <source>Naver Blog</source>
        </item></channel></rss>"""
        with mock.patch.object(NEWS_FETCH, "fetch_url", return_value=feed):
            items = NEWS_FETCH.fetch_google_stock_feed(
                '"네이버" when:2d', "KRX", "direct", "네이버"
            )

        self.assertEqual([item["summary"] for item in items], ["", ""])
        self.assertEqual(items[1]["title"], "아우디 Q9 공개")
        self.assertTrue(all(
            NEWS_FETCH.stock_relevance(item, "네이버", "035420", "KRX")["score"] == 0
            for item in items
        ))

    def test_stock_feed_builds_one_precise_query_for_each_naver_industry(self):
        queries = NEWS_FETCH.stock_feed_queries("네이버", "035420", "KRX")
        sector_queries = {
            topic.removeprefix("sector:"): query
            for query, relation_type, topic in queries
            if relation_type == "theme" and topic.startswith("sector:")
        }
        expected = NEWS_FETCH.stock_profile("KRX", "035420")["sectors"]

        self.assertEqual(set(sector_queries), set(expected))
        self.assertEqual(len(sector_queries), len(expected))
        self.assertIn('"검색광고 시장"', sector_queries["internet-platform"])
        self.assertIn('"웹툰 플랫폼"', sector_queries["digital-content"])
        self.assertIn('"간편결제 시장"', sector_queries["fintech-payments"])
        self.assertIn('"이커머스 시장"', sector_queries["ecommerce-retail"])
        self.assertTrue(all(query.count('"') <= 16 for query in sector_queries.values()))

    def test_stock_feed_keeps_partial_results_when_one_query_fails(self):
        def partial(query, market, relation_type, relation_topic):
            if "주식" in query:
                raise RuntimeError("temporary feed failure")
            return [{
                "title": "삼성전자 2분기 실적 발표",
                "summary": "",
                "source": "연합뉴스",
                "url": "https://example.com/result",
                "published": datetime.now(timezone.utc).isoformat(),
            }]

        with mock.patch.object(NEWS_FETCH, "fetch_google_stock_feed", side_effect=partial):
            result = NEWS_FETCH.fetch_stock_feed("삼성전자", "005930", "KRX")

        self.assertTrue(result)
        self.assertEqual(result[0]["relationType"], "direct")

    def test_stock_news_keeps_the_full_second_previous_calendar_day(self):
        local_now = datetime.now().astimezone().replace(hour=18, minute=0, second=0, microsecond=0)
        published = (local_now.replace(hour=0, minute=5) - timedelta(days=2)).isoformat()
        item = {
            "title": "삼성전자 새 반도체 발표",
            "summary": "",
            "url": "https://example.com/full-day",
            "published": published,
        }

        result = NEWS_FETCH.recent_stock_items(
            [item], "삼성전자", "005930", now=int(local_now.timestamp())
        )

        self.assertEqual([entry["url"] for entry in result], [item["url"]])

    def test_stock_news_uses_persistent_cache(self):
        now = int(NEWS_FETCH.time.time())
        published = datetime.fromtimestamp(now - 60, timezone.utc).isoformat(timespec="minutes")
        item = {
            "title": "삼성전자 실적 발표",
            "summary": "삼성전자 분기 실적",
            "url": "https://example.com/cache",
            "published": published,
            "publishedText": "12:00",
        }
        with tempfile.TemporaryDirectory() as directory:
            with mock.patch.object(NEWS_FETCH, "STOCK_CACHE_DIR", pathlib.Path(directory)):
                with mock.patch.object(NEWS_FETCH, "fetch_stock_feed", return_value=[item]) as fetcher:
                    with redirect_stdout(io.StringIO()):
                        NEWS_FETCH.fetch_stock_news(["005930", "KRX", "삼성전자", "30", "0"])
                    output = io.StringIO()
                    with redirect_stdout(output):
                        NEWS_FETCH.fetch_stock_news(["005930", "KRX", "삼성전자", "30", "0"])
        self.assertEqual(fetcher.call_count, 1)
        self.assertTrue(json.loads(output.getvalue())["cached"])

    def test_sk_hynix_news_includes_memory_and_edge_ai_themes(self):
        now = 1_800_000_000
        recent = datetime.fromtimestamp(now - 60, timezone.utc).isoformat(timespec="minutes")
        items = [
            {
                "title": "작은 메모리에서도 실행되는 경량 AI 모델 공개",
                "summary": "온디바이스 AI의 메모리 사용량을 줄였다",
                "url": "https://example.com/theme",
                "published": recent,
                "relationType": "theme",
            },
            {
                "title": "신형 전기차 공개",
                "summary": "배터리 효율 개선",
                "url": "https://example.com/unrelated",
                "published": recent,
                "relationType": "theme",
            },
        ]
        result = NEWS_FETCH.recent_stock_items(items, "SK하이닉스", "000660", "KRX", now=now)
        self.assertEqual([item["url"] for item in result], ["https://example.com/theme"])

    def test_naver_related_industries_are_precise_and_not_generic_keyword_hits(self):
        related = (
            "검색광고 시장, 생성형 검색 확대로 재편",
            "웹툰 플랫폼 해외 매출 성장세",
            "소버린 AI 수요에 공공 클라우드 시장 확대",
            "간편결제 시장 성장과 핀테크 규제 개편",
            "이커머스 시장, 온라인 거래액 회복",
        )
        for title in related:
            with self.subTest(title=title):
                relevance = NEWS_FETCH.stock_relevance(
                    {"title": title, "summary": ""},
                    "네이버", "035420", "KRX",
                )
                self.assertEqual(relevance["relationType"], "theme")
                self.assertNotEqual(relevance["relationClass"], "unrelated")

        unrelated = NEWS_FETCH.stock_relevance(
            {"title": "백화점 온라인 할인 행사 확대", "summary": "여름 의류 할인"},
            "네이버", "035420", "KRX",
        )
        self.assertEqual(unrelated["relationClass"], "unrelated")

    def test_news_limit_reserves_balanced_connected_industries(self):
        now = 1_900_000_000
        direct = [
            {
                "title": f"direct {index}",
                "published": datetime.fromtimestamp(now - index, timezone.utc).isoformat(),
                "relationType": "direct",
            }
            for index in range(35)
        ]
        sectors = NEWS_FETCH.stock_profile("KRX", "035420")["sectors"]
        connected = [
            {
                "title": sector_id,
                "published": datetime.fromtimestamp(now - 1000 - index, timezone.utc).isoformat(),
                "relationType": "theme",
                "querySector": sector_id,
            }
            for index, sector_id in enumerate(sectors)
        ]

        result = NEWS_FETCH.balanced_stock_items(direct + connected, 30, sectors)

        self.assertEqual(len(result), 30)
        self.assertEqual(
            {item.get("querySector") for item in result if item.get("relationType") == "theme"},
            set(sectors),
        )

    def test_major_company_profiles_are_data_driven(self):
        companies = NEWS_FETCH.STOCK_PROFILES["companies"]
        self.assertGreaterEqual(len(companies), 40)
        self.assertIn("KRX:005380", companies)
        self.assertIn("NASDAQ:NVDA", companies)
        self.assertIn("NYSE:JPM", companies)
        self.assertIn("전기차", NEWS_FETCH.stock_theme_terms("KRX", "005380"))
        self.assertIn("ai accelerator", NEWS_FETCH.stock_theme_terms("NASDAQ", "NVDA"))

    def test_company_profile_aliases_match_local_headlines(self):
        item = {"title": "하이닉스 HBM 공급 확대", "summary": ""}
        self.assertTrue(NEWS_FETCH.stock_item_matches(item, "SK hynix", "000660", "KRX"))

    def test_stock_relevance_distinguishes_direct_product_and_indirect_evidence(self):
        direct = NEWS_FETCH.stock_relevance(
            {"title": "삼성전자, 분기 실적 발표", "summary": ""},
            "삼성전자", "005930", "KRX",
        )
        product = NEWS_FETCH.stock_relevance(
            {"title": "갤럭시 신제품 사전 판매 시작", "summary": ""},
            "삼성전자", "005930", "KRX",
        )
        supply = NEWS_FETCH.stock_relevance(
            {"title": "AI 서버 수요 증가로 HBM 공급 부족", "summary": ""},
            "SK하이닉스", "000660", "KRX",
        )
        competitor = NEWS_FETCH.stock_relevance(
            {"title": "마이크론, 메모리 점유율 확대 계획 공개", "summary": ""},
            "SK하이닉스", "000660", "KRX",
        )
        regulation = NEWS_FETCH.stock_relevance(
            {"title": "미국, 대중 반도체 규제 강화", "summary": ""},
            "SK하이닉스", "000660", "KRX",
        )
        macro = NEWS_FETCH.stock_relevance(
            {"title": "메모리 업황 회복 기대", "summary": ""},
            "SK하이닉스", "000660", "KRX",
        )

        self.assertEqual((direct["relationType"], direct["relationClass"]), ("direct", "company"))
        self.assertEqual((product["relationType"], product["relationClass"]), ("direct", "product"))
        self.assertEqual((supply["relationType"], supply["relationClass"]), ("theme", "supply_chain"))
        self.assertEqual(competitor["relationClass"], "competitor")
        self.assertEqual(regulation["relationClass"], "regulation")
        self.assertEqual(macro["relationClass"], "macro")
        self.assertGreater(direct["score"], product["score"])
        self.assertGreater(product["score"], supply["score"])

    def test_ambiguous_company_names_and_bare_tickers_are_suppressed(self):
        fruit = NEWS_FETCH.stock_relevance(
            {"title": "Apple harvest grows as orchard output reaches record", "summary": ""},
            "Apple", "AAPL", "NASDAQ",
        )
        travel = NEWS_FETCH.stock_relevance(
            {"title": "Tourist visa processing times improve", "summary": ""},
            "Visa", "V", "NYSE",
        )
        bare_ticker = NEWS_FETCH.stock_relevance(
            {"title": "AAPL-inspired phone case arrives", "summary": ""},
            "Apple", "AAPL", "NASDAQ",
        )
        explicit_ticker = NEWS_FETCH.stock_relevance(
            {"title": "$AAPL shares rise after earnings", "summary": ""},
            "Apple", "AAPL", "NASDAQ",
        )
        short_name_collision = NEWS_FETCH.stock_relevance(
            {"title": "Ko Ji-yong returns to television", "summary": ""},
            "KO", "KO", "NYSE",
        )

        self.assertEqual(fruit["score"], 0)
        self.assertEqual(travel["score"], 0)
        self.assertEqual(bare_ticker["score"], 0)
        self.assertEqual(short_name_collision["score"], 0)
        self.assertEqual(explicit_ticker["relationClass"], "company")

    def test_incidental_brand_analyst_and_giveaway_mentions_are_suppressed(self):
        merchant = NEWS_FETCH.stock_relevance(
            {"title": "네이버페이 결제 고객에게 카페 10% 할인", "summary": "가맹점의 주말 행사다"},
            "네이버", "035420", "KRX",
        )
        product_event = NEWS_FETCH.stock_relevance(
            {"title": "네이버페이, 해외 결제 신제품 출시", "summary": ""},
            "네이버", "035420", "KRX",
        )
        fund_holding = NEWS_FETCH.stock_relevance(
            {"title": "JPMorgan Has $4.2 Million Stock Holdings in Nvidia", "summary": ""},
            "JPMorgan", "JPM", "NYSE",
        )
        analyst_note = NEWS_FETCH.stock_relevance(
            {"title": "JPMorgan Raises Apple Price Target", "summary": ""},
            "JPMorgan", "JPM", "NYSE",
        )
        giveaway = NEWS_FETCH.stock_relevance(
            {"title": "신규 고객에게 삼성전자 주식 증정 이벤트", "summary": ""},
            "삼성전자", "005930", "KRX",
        )
        celebrity = NEWS_FETCH.stock_relevance(
            {"title": "방송인 A씨, 삼성전자 주식 1억원 보유 고백", "summary": ""},
            "삼성전자", "005930", "KRX",
        )

        self.assertEqual(merchant["score"], 0)
        self.assertEqual(product_event["relationClass"], "product")
        self.assertEqual(fund_holding["score"], 0)
        self.assertEqual(analyst_note["score"], 0)
        self.assertEqual(giveaway["score"], 0)
        self.assertEqual(celebrity["score"], 0)

        for title in (
            "JPMorgan Trims Burlington Stake",
            "JPMorgan Boosts DigitalOcean Holdings",
            "JPMorgan Asia Growth & Income PLC Declares Distribution",
            "JPMorgan Chinese Investment Trust Reports Net Asset Value",
            "JPMorgan ETFs Announce Monthly Distributions",
            "Form FWP JPMorgan Chase Financial Company LLC",
            "JPMorgan Forecasts Strong Quarter for Bel Fuse",
        ):
            with self.subTest(title=title):
                result = NEWS_FETCH.stock_relevance(
                    {"title": title, "summary": ""}, "JPMorgan", "JPM", "NYSE"
                )
                self.assertEqual(result["score"], 0)

    def test_stock_story_clustering_merges_syndicated_title_and_description(self):
        published = "2027-01-15T10:00:00+09:00"
        items = [
            {
                "title": "삼성전자, 갤럭시 신제품 공개",
                "summary": "삼성전자가 서울 행사에서 새 갤럭시 제품을 공개했다",
                "source": "Source A",
                "url": "https://example.com/a",
                "published": published,
                "relevanceScore": 100,
                "relationType": "direct",
            },
            {
                "title": "삼성전자 갤럭시 신제품 공개",
                "summary": "서울 행사에서 삼성전자가 새로운 갤럭시 제품을 공개했다",
                "source": "Source B",
                "url": "https://example.com/b",
                "published": published,
                "relevanceScore": 100,
                "relationType": "direct",
            },
        ]

        clustered = NEWS_FETCH.cluster_stock_items(items)

        self.assertEqual(len(clustered), 1)
        self.assertEqual(clustered[0]["duplicateCount"], 2)
        self.assertEqual(clustered[0]["duplicateSources"], ["Source A", "Source B"])

    def test_company_mention_requires_material_event_for_verified_evidence(self):
        commentary = NEWS_FETCH.stock_relevance(
            {"title": "JPMorgan publishes its annual workplace survey", "summary": ""},
            "JPMorgan", "JPM", "NYSE",
        )
        earnings = NEWS_FETCH.stock_relevance(
            {"title": "JPMorgan earnings beat guidance", "summary": ""},
            "JPMorgan", "JPM", "NYSE",
        )

        self.assertEqual(commentary["relationClass"], "company")
        self.assertFalse(commentary["materialEvent"])
        self.assertLess(commentary["score"], earnings["score"])
        self.assertTrue(earnings["materialEvent"])

    def test_attention_baseline_uses_prior_hourly_windows_only(self):
        now = 1_900_000_000
        published = datetime.fromtimestamp(now - 60, timezone.utc).isoformat()
        cached = {"attentionHistory": [
            {"hour": now // 3600 - 4, "eventWeight6h": 1.0},
            {"hour": now // 3600 - 3, "eventWeight6h": 2.0},
            {"hour": now // 3600 - 2, "eventWeight6h": 3.0},
            {"hour": now // 3600 - 1, "eventWeight6h": 4.0},
        ]}
        items = [{
            "published": published,
            "relevanceWeight": 1,
            "sourceWeight": 0.9,
        }]

        history, baseline = NEWS_FETCH.stock_attention_history(cached, items, now)

        self.assertEqual(baseline["sampleWindowCount"], 4)
        self.assertEqual(baseline["expectedEventWeight6h"], 2.5)
        self.assertEqual(history[-1]["hour"], now // 3600)
        self.assertEqual(history[-1]["eventWeight6h"], 0.9)

    def test_specific_low_quality_source_wins_over_aggregator_substring(self):
        self.assertEqual(
            NEWS_FETCH.stock_source_quality("Naver Blog")["tier"],
            "low",
        )

    def test_korean_theme_term_does_not_match_inside_an_unrelated_brand(self):
        result = NEWS_FETCH.stock_relevance(
            {
                "title": "루쏘클라우드, 여행용 리커버리 슈즈 출시",
                "summary": "새 신발을 공개했다",
            },
            "NAVER", "035420", "KRX",
        )
        self.assertEqual(result["relationClass"], "unrelated")

    def test_external_analyst_commentary_is_not_a_material_company_event(self):
        result = NEWS_FETCH.stock_relevance(
            {
                "title": "Bank of America doubles down on Apple stock ahead of earnings",
                "summary": "",
            },
            "Apple", "AAPL", "NASDAQ",
        )
        self.assertEqual(result["relationClass"], "company")
        self.assertFalse(result["materialEvent"])

    def test_real_world_stock_news_regressions(self):
        cases = (
            (
                {"title": "WSJ SK하이닉스 ADR 프리미엄, AI 투자 과열 신호", "summary": ""},
                "SK하이닉스", "000660", "KRX", "company", False,
            ),
            (
                {
                    "title": "JPMorgan drawn into football controversy; NatWest lifts guidance after profits rise",
                    "summary": "JPMorgan drawn into football controversy; NatWest lifts guidance after profits rise thebanker.com",
                    "source": "thebanker.com",
                },
                "JPMorgan", "JPM", "NYSE", "company", False,
            ),
            (
                {"title": "Apple earnings preview: what to look for next week", "summary": ""},
                "Apple", "AAPL", "NASDAQ", "company", False,
            ),
            (
                {"title": "삼성전자 출신 임원, 현대차 신임 대표로 선임", "summary": ""},
                "삼성전자", "005930", "KRX", "unrelated", False,
            ),
            (
                {"title": "지역 학교 급식 교육 : 네이버 블로그", "summary": "", "source": "네이버 블로그"},
                "NAVER", "035420", "KRX", "unrelated", False,
            ),
            (
                {"title": "Coca-Cola earnings beat estimates as demand rises", "summary": ""},
                "Coca-Cola", "KO", "NYSE", "company", True,
            ),
        )

        for item, name, symbol, market, relation_class, material in cases:
            with self.subTest(title=item["title"]):
                result = NEWS_FETCH.stock_relevance(item, name, symbol, market)
                self.assertEqual(result["relationClass"], relation_class)
                self.assertEqual(result["materialEvent"], material)

    def test_other_company_as_headline_subject_is_connected_not_direct(self):
        result = NEWS_FETCH.stock_relevance(
            {
                "title": "Qualcomm forecasts weak profit and expects Apple revenue to drop",
                "summary": "",
            },
            "Apple", "AAPL", "NASDAQ",
        )

        self.assertEqual(result["relationType"], "theme")
        self.assertEqual(result["relationClass"], "competitor")
        self.assertFalse(result["materialEvent"])

    def test_material_event_is_attributed_to_the_nearest_company(self):
        cases = (
            ("SK hynix rises as Samsung reports record earnings", "SK하이닉스", "000660", "KRX"),
            ("Apple shares rise after Microsoft reports record earnings", "Apple", "AAPL", "NASDAQ"),
            ("JPMorgan gains as Goldman Sachs announces buyback", "JPMorgan", "JPM", "NYSE"),
        )

        for title, name, symbol, market in cases:
            with self.subTest(title=title):
                result = NEWS_FETCH.stock_relevance(
                    {"title": title, "summary": ""}, name, symbol, market,
                )
                self.assertFalse(result["materialEvent"])

    def test_compound_korean_particles_and_english_event_inflections_match(self):
        cases = (
            ("삼성전자에서 분기 실적 발표", "삼성전자", "005930", "KRX"),
            ("SK하이닉스로부터 HBM 공급 확대", "SK하이닉스", "000660", "KRX"),
            ("Apple launches new iPhone", "Apple", "AAPL", "NASDAQ"),
        )

        for title, name, symbol, market in cases:
            with self.subTest(title=title):
                result = NEWS_FETCH.stock_relevance(
                    {"title": title, "summary": ""}, name, symbol, market,
                )
                self.assertNotEqual(result["relationClass"], "unrelated")
                self.assertTrue(result["materialEvent"])

    def test_attention_history_backfills_elapsed_hours_from_prior_cache(self):
        now = 1_900_000_000
        current_hour = now // 3600
        cached = {
            "updatedAt": (current_hour - 4) * 3600,
            "attentionHistory": [{"hour": current_hour - 4, "eventWeight6h": 1.0}],
            "items": [],
        }

        history, baseline = NEWS_FETCH.stock_attention_history(cached, [], now)

        self.assertEqual([entry["hour"] for entry in history[-5:]], list(range(current_hour - 4, current_hour + 1)))
        self.assertEqual(baseline["sampleWindowCount"], 4)
        self.assertEqual(baseline["expectedEventWeight6h"], 0.25)

    def test_manual_stock_refresh_replaces_cached_articles(self):
        now = int(NEWS_FETCH.time.time())
        published = datetime.fromtimestamp(now - 60, timezone.utc).isoformat(timespec="minutes")
        first = {"title": "삼성전자 이전 기사", "summary": "", "url": "https://example.com/old", "published": published}
        second = {"title": "삼성전자 새 기사", "summary": "", "url": "https://example.com/new", "published": published}
        with tempfile.TemporaryDirectory() as directory:
            with mock.patch.object(NEWS_FETCH, "STOCK_CACHE_DIR", pathlib.Path(directory)):
                with mock.patch.object(NEWS_FETCH, "fetch_stock_feed", side_effect=[[first], [second]]) as fetcher:
                    with redirect_stdout(io.StringIO()):
                        NEWS_FETCH.fetch_stock_news(["005930", "KRX", "삼성전자", "30", "cache"])
                    output = io.StringIO()
                    with redirect_stdout(output):
                        NEWS_FETCH.fetch_stock_news(["005930", "KRX", "삼성전자", "30", "force"])
        payload = json.loads(output.getvalue())
        self.assertEqual(fetcher.call_count, 2)
        self.assertEqual([item["url"] for item in payload["items"]], ["https://example.com/new"])
        self.assertFalse(payload["cached"])


if __name__ == "__main__":
    unittest.main()
