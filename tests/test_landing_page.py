from html.parser import HTMLParser
from pathlib import Path
import re
import unittest
from urllib.parse import urlparse


REPO_ROOT = Path(__file__).resolve().parent.parent
LANDING_PAGE_PATH = REPO_ROOT / "index.html"
SETTINGS_SWIFT_PATH = REPO_ROOT / "glint-app" / "Settings.swift"


class _LandingPageDocumentParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.has_doctype = False
        self.tags: list[str] = []
        self.meta_tags: list[dict[str, str]] = []
        self.links: list[str] = []
        self.media_sources: list[str] = []
        self._in_title = False
        self.title_parts: list[str] = []

    def handle_decl(self, decl: str) -> None:
        if decl.strip().lower().startswith("doctype html"):
            self.has_doctype = True

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        lowered_tag = tag.lower()
        self.tags.append(lowered_tag)
        attr_map = {k.lower(): (v or "") for k, v in attrs}

        if lowered_tag == "title":
            self._in_title = True
        elif lowered_tag == "meta":
            self.meta_tags.append(attr_map)
        elif lowered_tag == "a" and "href" in attr_map:
            self.links.append(attr_map["href"])
        elif lowered_tag in {"img", "video", "source"}:
            for attr_name in ("src", "poster"):
                if attr_map.get(attr_name):
                    self.media_sources.append(attr_map[attr_name])
        elif lowered_tag == "link" and attr_map.get("rel") in {"icon", "apple-touch-icon"}:
            if attr_map.get("href"):
                self.media_sources.append(attr_map["href"])

    def handle_endtag(self, tag: str) -> None:
        if tag.lower() == "title":
            self._in_title = False

    def handle_data(self, data: str) -> None:
        if self._in_title:
            self.title_parts.append(data)

    @property
    def title_text(self) -> str:
        return "".join(self.title_parts).strip()


class _WalkthroughVisualParser(HTMLParser):
    _VOID_TAGS = {
        "area",
        "base",
        "br",
        "col",
        "embed",
        "hr",
        "img",
        "input",
        "link",
        "meta",
        "param",
        "source",
        "track",
        "wbr",
    }

    def __init__(self) -> None:
        super().__init__()
        self._stack: list[tuple[str, dict[str, str]]] = []
        self._walkthrough_section_depth: int | None = None
        self._current_card_depth: int | None = None
        self._current_card: dict[str, object] | None = None
        self.cards: list[dict[str, object]] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        lowered_tag = tag.lower()
        attr_map = {k.lower(): (v or "") for k, v in attrs}

        if lowered_tag not in self._VOID_TAGS:
            self._stack.append((lowered_tag, attr_map))

        if (
            self._walkthrough_section_depth is None
            and lowered_tag == "section"
            and attr_map.get("id") == "walkthrough"
        ):
            self._walkthrough_section_depth = len(self._stack)

        if self._walkthrough_section_depth is not None:
            classes = set(attr_map.get("class", "").split())
            if self._current_card is None and "walkthrough-visual" in classes:
                self._current_card_depth = len(self._stack)
                self._current_card = {
                    "has_zh": False,
                    "has_en": False,
                    "zh_parts": [],
                    "en_parts": [],
                }

            if self._current_card is not None:
                data_lang = attr_map.get("data-lang", "").lower()
                if data_lang == "zh":
                    self._current_card["has_zh"] = True
                elif data_lang == "en":
                    self._current_card["has_en"] = True

    def handle_endtag(self, tag: str) -> None:
        lowered_tag = tag.lower()
        if lowered_tag in self._VOID_TAGS:
            return

        for idx in range(len(self._stack) - 1, -1, -1):
            if self._stack[idx][0] == lowered_tag:
                del self._stack[idx:]
                break

        if (
            self._current_card is not None
            and self._current_card_depth is not None
            and len(self._stack) < self._current_card_depth
        ):
            self.cards.append(self._current_card)
            self._current_card = None
            self._current_card_depth = None

        if (
            self._walkthrough_section_depth is not None
            and len(self._stack) < self._walkthrough_section_depth
        ):
            self._walkthrough_section_depth = None

    def handle_data(self, data: str) -> None:
        if self._current_card is None or self._current_card_depth is None:
            return
        active_subtree = self._stack[self._current_card_depth - 1 :]
        hidden_in_en = any(
            attrs.get("data-lang", "").lower() == "zh" for _, attrs in active_subtree
        )
        hidden_in_zh = any(
            attrs.get("data-lang", "").lower() == "en" for _, attrs in active_subtree
        )
        if not hidden_in_en:
            zh_or_en_list = self._current_card["en_parts"]
            assert isinstance(zh_or_en_list, list)
            zh_or_en_list.append(data)
        if not hidden_in_zh:
            zh_list = self._current_card["zh_parts"]
            assert isinstance(zh_list, list)
            zh_list.append(data)


class TestLandingPage(unittest.TestCase):
    def _load_and_parse(self) -> tuple[str, _LandingPageDocumentParser]:
        self.assertTrue(
            LANDING_PAGE_PATH.is_file(),
            f"Missing static landing page at {LANDING_PAGE_PATH}",
        )
        content = LANDING_PAGE_PATH.read_text(encoding="utf-8")
        self.assertGreater(
            len(content.strip()),
            0,
            "Landing page index.html must not be empty",
        )
        parser = _LandingPageDocumentParser()
        parser.feed(content)
        return content, parser

    def test_landing_page_html_document_has_valid_structure_and_glint_metadata(
        self,
    ) -> None:
        content, parser = self._load_and_parse()
        lowered = content.lower()

        self.assertTrue(
            parser.has_doctype or "<!doctype html>" in lowered,
            "index.html must start with <!doctype html>",
        )
        for required_tag in ("html", "head", "body", "header", "main", "footer"):
            self.assertIn(
                required_tag,
                parser.tags,
                f"index.html must include semantic <{required_tag}> tag",
            )

        has_utf8_charset = any(
            meta.get("charset", "").lower() == "utf-8"
            or "charset=utf-8" in meta.get("content", "").lower()
            for meta in parser.meta_tags
        )
        self.assertTrue(
            has_utf8_charset,
            "index.html must declare a UTF-8 charset meta tag",
        )

        has_viewport = any(
            meta.get("name", "").lower() == "viewport"
            and "width=device-width" in meta.get("content", "").lower()
            for meta in parser.meta_tags
        )
        self.assertTrue(
            has_viewport,
            "index.html must include a responsive viewport meta tag",
        )

        self.assertIn(
            "Glint",
            parser.title_text,
            f"Page <title> must include 'Glint', got '{parser.title_text}'",
        )

        description_contents = [
            meta.get("content", "")
            for meta in parser.meta_tags
            if meta.get("name", "").lower() == "description"
        ]
        self.assertGreater(
            len(description_contents),
            0,
            "index.html must include a meta description tag",
        )
        description_text = " ".join(description_contents)
        for keyword in ("划词", "翻译", "解释"):
            self.assertIn(
                keyword,
                description_text,
                f"Meta description must contain '{keyword}'",
            )

    def test_landing_page_theme_tokens_match_claude_warm_paper_palette_and_serif_typography(
        self,
    ) -> None:
        content, _ = self._load_and_parse()
        lowered = content.lower()

        required_colors = {
            "#faf9f5": "warm paper primary background (#FAF9F5)",
            "#f5f4ef": "secondary warm background (#F5F4EF)",
            "#d97757": "Anthropic terracotta accent (#D97757)",
            "#141413": "deep charcoal heading (#141413)",
            "#2d2d2a": "warm dark charcoal body text (#2D2D2A)",
        }
        for hex_color, description in required_colors.items():
            self.assertIn(
                hex_color,
                lowered,
                f"index.html must define {description}",
            )

        self.assertTrue(
            "#e8e6de" in lowered or "#e3e1d8" in lowered,
            "index.html must include warm paper fine border token (#E8E6DE or #E3E1D8)",
        )

        serif_candidates = (
            "source han serif",
            "noto serif",
            "songti sc",
            "georgia",
            "serif",
        )
        self.assertTrue(
            any(font in lowered for font in serif_candidates),
            "index.html must declare a serif font family for Claude Blog bookish styling",
        )

    def test_landing_page_sections_cover_hero_why_glint_walkthrough_and_install_guide(
        self,
    ) -> None:
        content, parser = self._load_and_parse()

        # 1. Hero section & AI providers
        self.assertIn("选中", content, "Hero headline must mention '选中'")
        self.assertTrue(
            "即刻响应" in content or "即译" in content,
            "Hero headline must mention '即刻响应' or '即译'",
        )
        releases_url = "https://github.com/nanzhi84/Glint/releases"
        self.assertTrue(
            any(releases_url in href for href in parser.links) or releases_url in content,
            f"Hero section must link to GitHub Releases ({releases_url})",
        )
        for provider in ("OpenAI", "Gemini", "Vertex AI", "DeepSeek", "MiMo"):
            self.assertIn(
                provider,
                content,
                f"Landing page must showcase supported AI provider '{provider}'",
            )
        self.assertTrue(
            "Anthropic" in content or "Claude" in content,
            "Landing page must showcase Anthropic / Claude compatibility",
        )

        # 2. Why Glint section
        self.assertIn(
            "为什么选择 Glint",
            content,
            "Landing page must include '为什么选择 Glint' section heading",
        )
        for feature_keyword in ("划词", "翻译", "解释", "API Key", "原生"):
            self.assertIn(
                feature_keyword,
                content,
                f"Why Glint section must cover '{feature_keyword}'",
            )

        # 3. Product Walkthrough section
        self.assertIn(
            "产品演示",
            content,
            "Landing page must include '产品演示' section heading",
        )
        self.assertIn(
            "Markdown",
            content,
            "Product Walkthrough must mention streaming Markdown rendering",
        )
        self.assertTrue(
            "追问" in content or "多轮" in content,
            "Product Walkthrough must mention multi-turn follow-up ('追问' or '多轮')",
        )
        self.assertIn(
            "⌃⌥E",
            content,
            "Product Walkthrough must document screenshot explain shortcut '⌃⌥E'",
        )
        self.assertTrue(
            "服务商" in content or "厂商" in content,
            "Product Walkthrough must cover multi-provider settings",
        )
        self.assertIn(
            "语言",
            content,
            "Product Walkthrough must cover target language settings",
        )

        # 4. Installation Guide section (direct single-page scroll section)
        self.assertIn(
            '<section id="install-guide"',
            content,
            'Installation Guide must be rendered directly as <section id="install-guide"',
        )
        self.assertIn(
            "安装引导",
            content,
            "Landing page must include '安装引导' entry and section",
        )
        self.assertTrue(
            "无法验证开发者" in content or "隐私与安全性" in content,
            "Installation Guide must explain macOS Gatekeeper / Privacy & Security handling",
        )
        for install_step_keyword in ("仍要打开", "辅助功能", "屏幕录制"):
            self.assertIn(
                install_step_keyword,
                content,
                f"Installation Guide must include '{install_step_keyword}'",
            )

    def test_landing_page_productized_navigation_provider_logos_and_user_friendly_copy(
        self,
    ) -> None:
        content, _ = self._load_and_parse()

        # 1. Installation guide scrolls directly on the single page without subpage hiding
        self.assertFalse(
            'body[data-view="install-guide"]' in content,
            'Landing page must not hide main sections with body[data-view="install-guide"]',
        )
        self.assertIsNone(
            re.search(r"\.landing-only-section\s*\{\s*display\s*:\s*none", content),
            "Landing page must not hide .landing-only-section via display: none",
        )
        self.assertTrue(
            '<section id="install-guide"' in content,
            'Landing page must include <section id="install-guide" directly in single-page flow',
        )

        # 2. Minimalist header without text nav links or rounded card button backgrounds
        header_match = re.search(
            r"<header\b[^>]*>(.*?)</header>",
            content,
            flags=re.IGNORECASE | re.DOTALL,
        )
        self.assertIsNotNone(header_match, "index.html must contain a <header> block")
        header_html = header_match.group(1) if header_match else ""

        for forbidden_header_nav in ("核心优势", "产品演示", "安装引导"):
            self.assertFalse(
                forbidden_header_nav in header_html,
                f"<header> must not contain text navigation item '{forbidden_header_nav}'",
            )

        header_svg_count = len(re.findall(r"<svg\b", header_html, flags=re.IGNORECASE))
        self.assertGreaterEqual(
            header_svg_count,
            3,
            f"<header> actions (language, theme, GitHub) must each embed an inline <svg> icon, found {header_svg_count}",
        )
        self.assertFalse(
            "icon-circle-btn" in content,
            "Header buttons must not use rounded card class .icon-circle-btn",
        )
        self.assertFalse(
            "header-github-btn" in content,
            "Header GitHub link must not use rounded pill card class .header-github-btn",
        )

        # 3. Mainstream AI providers showcase uses real official high-res icons from Settings.swift
        self.assertFalse(
            "provider-dot" in content,
            "Providers list must not use .provider-dot colored dots",
        )
        providers_match = re.search(
            r'<div\s+class="providers-list"[^>]*>(.*?)</div>',
            content,
            flags=re.IGNORECASE | re.DOTALL,
        )
        self.assertIsNotNone(
            providers_match,
            "index.html must contain a .providers-list container",
        )
        providers_html = providers_match.group(1) if providers_match else ""
        providers_img_count = len(
            re.findall(r"<img\b", providers_html, flags=re.IGNORECASE)
        )
        self.assertGreaterEqual(
            providers_img_count,
            6,
            f".providers-list must include at least 6 <img> provider icons (official app icons + OpenAI & Claude), found {providers_img_count}",
        )

        self.assertTrue(
            SETTINGS_SWIFT_PATH.is_file(),
            f"Missing Settings.swift at {SETTINGS_SWIFT_PATH}",
        )
        settings_swift_text = SETTINGS_SWIFT_PATH.read_text(encoding="utf-8")
        for icon_const in (
            "kIcon_deepseek",
            "kIcon_gemini",
            "kIcon_vertexai",
            "kIcon_xiaomi",
        ):
            const_match = re.search(
                rf'static\s+let\s+{icon_const}\s*=\s*"([^"]+)"',
                settings_swift_text,
            )
            self.assertIsNotNone(
                const_match,
                f"Expected {icon_const} Base64 definition in Settings.swift",
            )
            icon_b64 = const_match.group(1) if const_match else ""
            # Check prefix (64 chars) and payload slice (first 200 chars, where IDAT chunks diverge)
            self.assertTrue(
                icon_b64[:64] in providers_html and icon_b64[:200] in providers_html,
                f".providers-list must embed official {icon_const} Base64 icon from Settings.swift",
            )

        # 4. Concise Why Glint 2x2 feature card descriptions (20 to 62 non-whitespace Chinese chars)
        feature_paragraph_zh_matches = re.findall(
            r'<div\s+class="feature-card"[^>]*>.*?<p>\s*<span\s+data-lang="zh">(.*?)</span>',
            content,
            flags=re.IGNORECASE | re.DOTALL,
        )
        self.assertEqual(
            len(feature_paragraph_zh_matches),
            4,
            f"Expected 4 .feature-card Chinese descriptions, found {len(feature_paragraph_zh_matches)}",
        )
        for idx, raw_zh_html in enumerate(feature_paragraph_zh_matches, start=1):
            plain_zh = re.sub(r"<[^>]+>", "", raw_zh_html)
            compact_zh = re.sub(r"\s+", "", plain_zh)
            self.assertGreaterEqual(
                len(compact_zh),
                20,
                f"Feature card #{idx} Chinese copy is too short ({len(compact_zh)} chars): {compact_zh}",
            )
            self.assertLessEqual(
                len(compact_zh),
                62,
                f"Feature card #{idx} Chinese copy must be concise (<= 62 chars, got {len(compact_zh)}): {compact_zh}",
            )

        # 5. No nested "card-inside-card" structures in Walkthrough, Hero Showcase, or Install Guide
        walkthrough_visual_css_blocks = re.findall(
            r"\.walkthrough-visual\s*\{([^}]*)\}",
            content,
            flags=re.IGNORECASE | re.DOTALL,
        )
        self.assertGreater(
            len(walkthrough_visual_css_blocks),
            0,
            "Expected .walkthrough-visual CSS rule in index.html",
        )
        for css_block in walkthrough_visual_css_blocks:
            self.assertFalse(
                "border: 1px" in css_block.lower(),
                ".walkthrough-visual CSS must not set outer card border 'border: 1px'",
            )
            self.assertFalse(
                "box-shadow: var(--shadow" in css_block.lower(),
                ".walkthrough-visual CSS must not set outer card shadow 'box-shadow: var(--shadow'",
            )

        self.assertTrue(
            "window-titlebar" in content,
            "Hero showcase must retain .window-titlebar macOS window header",
        )
        self.assertIsNotNone(
            re.search(r'<video\b[^>]*class="[^"]*\bshowcase-video\b', content),
            'Hero showcase must retain <video class="showcase-video">',
        )
        for forbidden_nested_wrapper in (
            "showcase-media-wrap",
            "interactive-try-bar",
            "try-sample-text",
            "try-output-card",
            "install-visual-banner",
        ):
            self.assertFalse(
                forbidden_nested_wrapper in content,
                f"Landing page must not contain nested box-in-box element '.{forbidden_nested_wrapper}'",
            )

        # 6. Walkthrough 03 (⌃⌥E Screenshot Vision) Chinese copy trimmed to <= 47 chars (2 lines)
        walkthrough_03_match = re.search(
            r'03\s*·\s*SCREENSHOT VISION.*?<p>\s*<span\s+data-lang="zh">(.*?)</span>',
            content,
            flags=re.IGNORECASE | re.DOTALL,
        )
        self.assertIsNotNone(
            walkthrough_03_match,
            "Expected Walkthrough 03 Chinese description in index.html",
        )
        walkthrough_03_zh_raw = walkthrough_03_match.group(1) if walkthrough_03_match else ""
        walkthrough_03_zh_plain = re.sub(
            r"\s+",
            "",
            re.sub(r"<[^>]+>", "", walkthrough_03_zh_raw),
        )
        for expected_part in (
            "遇到无法选中的报错弹窗、架构图或论文公式？按下",
            "⌃⌥E",
            "框选任意区域，多模态模型即刻看图精讲。",
        ):
            self.assertTrue(
                expected_part in walkthrough_03_zh_plain,
                f"Walkthrough 03 Chinese copy must contain '{expected_part}', got '{walkthrough_03_zh_plain}'",
            )
        self.assertLessEqual(
            len(walkthrough_03_zh_plain),
            47,
            f"Walkthrough 03 Chinese copy must be <= 47 chars to fit 2 lines, got {len(walkthrough_03_zh_plain)}: '{walkthrough_03_zh_plain}'",
        )

        # 7. Standalone Hero Interactive Preview below .hero-showcase (outside the video window)
        hero_section_match = re.search(
            r'<section\s+class="[^"]*\bhero-section\b[^"]*"[^>]*>(.*?)</section>',
            content,
            flags=re.IGNORECASE | re.DOTALL,
        )
        self.assertIsNotNone(
            hero_section_match,
            "Expected <section class=\"hero-section\"> in index.html",
        )
        hero_section_html = hero_section_match.group(1) if hero_section_match else ""
        self.assertIsNotNone(
            re.search(
                r'</video>\s*</div>\s*(?:<!--.*?-->\s*)*<div\s+class="hero-interactive-preview"[^>]*>',
                hero_section_html,
                flags=re.IGNORECASE | re.DOTALL,
            ),
            ".hero-interactive-preview must be placed outside and directly after .hero-showcase inside .hero-section",
        )
        for preview_token in (
            'id="demo-btn-explain"',
            'id="demo-btn-translate"',
            'id="demo-output-explain"',
            'id="demo-output-translate"',
            "交互预览",
        ):
            self.assertTrue(
                preview_token in hero_section_html,
                f"Hero interactive preview must include '{preview_token}'",
            )

        # 8. Productized copy free of low-level engineering jargon
        forbidden_jargon = (
            "AXUIElementCreateSystemWide",
            "~/.config/glint/config.json",
            "arm64 + x86_64",
            "<languages>",
            "&lt;languages&gt;",
            "cd glint-app && bash build.sh",
            "cd glint-app &amp;&amp; bash build.sh",
        )
        for term in forbidden_jargon:
            self.assertFalse(
                term in content,
                f"Landing page copy must be productized and not expose low-level term '{term}'",
            )

    def test_landing_page_i18n_and_local_media_assets_resolve_to_existing_files(
        self,
    ) -> None:
        content, parser = self._load_and_parse()

        for english_phrase in (
            "Why Glint",
            "Product Walkthrough",
            "Installation Guide",
        ):
            self.assertIn(
                english_phrase,
                content,
                f"Landing page must include bilingual English copy '{english_phrase}'",
            )

        local_assets: list[str] = []
        for raw_src in parser.media_sources:
            parsed = urlparse(raw_src)
            if parsed.scheme or raw_src.startswith("//") or raw_src.startswith("data:"):
                continue
            rel_path = parsed.path.lstrip("./")
            if rel_path:
                local_assets.append(rel_path)

        self.assertIn(
            "images/logo.svg",
            local_assets,
            "Landing page must reference local brand icon 'images/logo.svg'",
        )
        self.assertTrue(
            "images/demo.mp4" in local_assets or "images/demo.gif" in local_assets,
            "Landing page must reference local product demo 'images/demo.mp4' or 'images/demo.gif'",
        )

        for rel_asset in sorted(set(local_assets)):
            asset_path = REPO_ROOT / rel_asset
            self.assertTrue(
                asset_path.is_file(),
                f"Referenced local media asset does not exist on disk: {rel_asset}",
            )
            self.assertGreater(
                asset_path.stat().st_size,
                0,
                f"Referenced local media asset must not be empty: {rel_asset}",
            )

    def test_landing_page_switching_to_english_translates_all_walkthrough_preview_cards(
        self,
    ) -> None:
        content, _ = self._load_and_parse()
        walkthrough_parser = _WalkthroughVisualParser()
        walkthrough_parser.feed(content)

        self.assertEqual(
            len(walkthrough_parser.cards),
            4,
            f"Expected 4 .walkthrough-visual preview blocks inside #walkthrough, found {len(walkthrough_parser.cards)}",
        )

        expected_en_tokens: tuple[tuple[str, ...], ...] = (
            ("Translate", "Explain"),
            ("Enter",),
            ("⌃⌥E",),
            ("Providers", "11"),
        )
        expected_zh_tokens: tuple[tuple[str, ...], ...] = (
            ("翻译", "解释"),
            ("继续追问",),
            ("框选",),
            ("服务商",),
        )

        for idx, card in enumerate(walkthrough_parser.cards, start=1):
            self.assertTrue(
                bool(card["has_zh"]),
                f"Walkthrough preview card #{idx} must include data-lang=\"zh\" markup",
            )
            self.assertTrue(
                bool(card["has_en"]),
                f"Walkthrough preview card #{idx} must include data-lang=\"en\" markup",
            )

            en_parts = card["en_parts"]
            zh_parts = card["zh_parts"]
            assert isinstance(en_parts, list)
            assert isinstance(zh_parts, list)
            visible_en_text = " ".join("".join(en_parts).split())
            visible_zh_text = " ".join("".join(zh_parts).split())

            self.assertGreater(
                len(visible_en_text),
                0,
                f"Walkthrough preview card #{idx} visible English text must not be empty",
            )
            self.assertIsNone(
                re.search(r"[\u4e00-\u9fff]", visible_en_text),
                f"Walkthrough preview card #{idx} in English mode must not contain Chinese characters, got: {visible_en_text}",
            )
            for token in expected_en_tokens[idx - 1]:
                self.assertIn(
                    token,
                    visible_en_text,
                    f"Walkthrough preview card #{idx} in English mode must contain '{token}', got: {visible_en_text}",
                )

            self.assertGreater(
                len(visible_zh_text),
                0,
                f"Walkthrough preview card #{idx} visible Chinese text must not be empty",
            )
            for token in expected_zh_tokens[idx - 1]:
                self.assertIn(
                    token,
                    visible_zh_text,
                    f"Walkthrough preview card #{idx} in Chinese mode must contain '{token}', got: {visible_zh_text}",
                )


if __name__ == "__main__":
    unittest.main()
