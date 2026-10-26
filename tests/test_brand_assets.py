from pathlib import Path
import subprocess
import tempfile
import unittest
import xml.etree.ElementTree as ET


REPO_ROOT = Path(__file__).resolve().parent.parent


class TestBrandLogo(unittest.TestCase):
    def test_svg_logo_file_contains_warm_paper_and_terracotta_palette(self) -> None:
        svg_path = REPO_ROOT / "images" / "logo.svg"
        self.assertTrue(svg_path.is_file(), f"Missing SVG logo file: {svg_path}")

        content = svg_path.read_text(encoding="utf-8").strip()
        self.assertGreater(len(content), 0, "images/logo.svg must not be empty")
        self.assertIn("<svg", content.lower(), "images/logo.svg must contain <svg tag")

        root = ET.fromstring(content)
        self.assertTrue(
            root.tag.endswith("svg"),
            f"Root XML tag of images/logo.svg must be <svg>, got {root.tag}",
        )

        lowered = content.lower()
        self.assertIn(
            "#faf9f5",
            lowered,
            "images/logo.svg must include warm paper primary color #FAF9F5",
        )
        self.assertIn(
            "#d97757",
            lowered,
            "images/logo.svg must include terracotta accent color #D97757",
        )

    def test_icns_file_has_valid_magic_header_and_bundle_plist_entry(self) -> None:
        icns_path = REPO_ROOT / "popdict-app" / "popdict.icns"
        self.assertTrue(icns_path.is_file(), f"Missing app icon file: {icns_path}")

        icns_bytes = icns_path.read_bytes()
        self.assertGreater(
            len(icns_bytes),
            1024,
            "popdict.icns must be larger than 1024 bytes",
        )
        self.assertEqual(
            icns_bytes[:4],
            b"icns",
            "popdict.icns must start with 'icns' magic header",
        )

        bundle_icns_path = (
            REPO_ROOT
            / "popdict-app"
            / "popdict.app"
            / "Contents"
            / "Resources"
            / "popdict.icns"
        )
        self.assertTrue(
            bundle_icns_path.is_file(),
            f"Missing bundled icon file in app bundle: {bundle_icns_path}",
        )
        self.assertEqual(bundle_icns_path.read_bytes()[:4], b"icns")

        plist_path = (
            REPO_ROOT / "popdict-app" / "popdict.app" / "Contents" / "Info.plist"
        )
        self.assertTrue(plist_path.is_file(), f"Missing Info.plist: {plist_path}")
        plist_text = plist_path.read_text(encoding="utf-8")
        self.assertIn("<key>CFBundleIconFile</key>", plist_text)
        self.assertIn("<string>popdict.icns</string>", plist_text)

    def test_brand_logo_module_renders_template_menubar_icon_and_app_icon_png(
        self,
    ) -> None:
        brand_logo_swift = REPO_ROOT / "popdict-app" / "BrandLogo.swift"
        self.assertTrue(
            brand_logo_swift.is_file(),
            f"Missing Swift brand logo module: {brand_logo_swift}",
        )

        probe_source = """import Cocoa
import Foundation

let menuIcon = BrandLogo.menuBarIcon()
guard Int(menuIcon.size.width.rounded()) == 18 && Int(menuIcon.size.height.rounded()) == 18 else {
    fputs("FAIL: menuBarIcon size is \\(menuIcon.size)\\n", stderr)
    exit(1)
}
guard menuIcon.isTemplate == true else {
    fputs("FAIL: menuBarIcon.isTemplate must be true\\n", stderr)
    exit(1)
}

let appIcon = BrandLogo.appIconImage(size: NSSize(width: 256, height: 256))
guard Int(appIcon.size.width.rounded()) == 256 && Int(appIcon.size.height.rounded()) == 256 else {
    fputs("FAIL: appIconImage size is \\(appIcon.size)\\n", stderr)
    exit(1)
}
guard appIcon.isTemplate == false else {
    fputs("FAIL: appIconImage.isTemplate must be false\\n", stderr)
    exit(1)
}

guard let png = BrandLogo.pngData(pixelSize: 128), png.count > 8 else {
    fputs("FAIL: pngData(pixelSize: 128) returned nil or too few bytes\\n", stderr)
    exit(1)
}
let header = Array(png.prefix(8))
let expectedHeader: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
guard header == expectedHeader else {
    fputs("FAIL: PNG signature mismatch: \\(header)\\n", stderr)
    exit(1)
}

print("BRAND_LOGO_CONTRACT_OK")
"""
        with tempfile.TemporaryDirectory() as tmp_dir:
            tmp_path = Path(tmp_dir)
            probe_file = tmp_path / "main.swift"
            probe_bin = tmp_path / "probe_brand_logo"
            probe_file.write_text(probe_source, encoding="utf-8")

            compile_proc = subprocess.run(
                [
                    "swiftc",
                    "-framework",
                    "Cocoa",
                    str(brand_logo_swift),
                    str(probe_file),
                    "-o",
                    str(probe_bin),
                ],
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertEqual(
                compile_proc.returncode,
                0,
                f"Failed to compile BrandLogo.swift: {compile_proc.stderr}",
            )

            run_proc = subprocess.run(
                [str(probe_bin)],
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertEqual(
                run_proc.returncode,
                0,
                f"BrandLogo runtime contract failed: {run_proc.stderr}",
            )
            self.assertIn("BRAND_LOGO_CONTRACT_OK", run_proc.stdout)


class TestReadmePortal(unittest.TestCase):
    def test_readme_banner_includes_centered_logo_and_intro(self) -> None:
        readme_path = REPO_ROOT / "README.md"
        self.assertTrue(readme_path.is_file(), "README.md must exist")

        content = readme_path.read_text(encoding="utf-8")
        self.assertNotIn(
            "images/explain.png",
            content,
            "README.md must not reference legacy static screenshot images/explain.png",
        )
        self.assertNotIn(
            "images/settings.png",
            content,
            "README.md must not reference legacy static screenshot images/settings.png",
        )

        head_chunk = "\n".join(content.splitlines()[:30])
        self.assertIn(
            '<div align="center">',
            head_chunk,
            "README.md top banner must use <div align=\"center\">",
        )
        self.assertIn(
            "images/logo.svg",
            head_chunk,
            "README.md top banner must reference images/logo.svg",
        )
        self.assertTrue(
            "images/demo.gif" in head_chunk or "images/demo.mp4" in head_chunk,
            "README.md top banner must reference images/demo.gif or images/demo.mp4",
        )

    def test_demo_video_and_gif_assets_have_valid_headers_and_non_trivial_size(
        self,
    ) -> None:
        mp4_path = REPO_ROOT / "images" / "demo.mp4"
        self.assertTrue(mp4_path.is_file(), f"Missing demo MP4 video: {mp4_path}")
        mp4_bytes = mp4_path.read_bytes()
        self.assertGreater(
            len(mp4_bytes),
            10000,
            "images/demo.mp4 must be larger than 10000 bytes",
        )
        self.assertIn(
            b"ftyp",
            mp4_bytes[:16],
            "images/demo.mp4 must contain MP4 'ftyp' header signature in first 16 bytes",
        )

        gif_path = REPO_ROOT / "images" / "demo.gif"
        self.assertTrue(gif_path.is_file(), f"Missing demo GIF animation: {gif_path}")
        gif_bytes = gif_path.read_bytes()
        self.assertGreater(
            len(gif_bytes),
            10000,
            "images/demo.gif must be larger than 10000 bytes",
        )
        self.assertEqual(
            gif_bytes[:6],
            b"GIF89a",
            "images/demo.gif must start with 'GIF89a' magic header",
        )

    def test_readme_sections_cover_core_ideas_get_started_and_learn_more(self) -> None:
        readme_path = REPO_ROOT / "README.md"
        content = readme_path.read_text(encoding="utf-8")
        lowered = content.lower()

        for section in ("core ideas", "get started", "learn more"):
            self.assertIn(
                section,
                lowered,
                f"README.md must contain section heading '{section}'",
            )

        for provider in ("DeepSeek", "Gemini", "Vertex AI", "MiMo"):
            self.assertIn(
                provider,
                content,
                f"README.md must document built-in provider '{provider}'",
            )

        self.assertIn(
            "⌃⌥E",
            content,
            "README.md must document the screenshot explain shortcut ⌃⌥E",
        )


if __name__ == "__main__":
    unittest.main()
