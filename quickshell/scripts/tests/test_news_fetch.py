import importlib.util
import pathlib
import unittest


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


if __name__ == "__main__":
    unittest.main()
