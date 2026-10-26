import os
from pathlib import Path
import subprocess
import tempfile
import unittest


REPO_ROOT = Path(__file__).resolve().parent.parent
CONFIG_SWIFT = REPO_ROOT / "popdict-app" / "Config.swift"
MAIN_SWIFT = REPO_ROOT / "popdict-app" / "main.swift"
SETTINGS_SWIFT = REPO_ROOT / "popdict-app" / "Settings.swift"


def _compile_and_run_swift_probe(probe_source: str) -> subprocess.CompletedProcess[str]:
    with tempfile.TemporaryDirectory() as tmp_dir:
        tmp_path = Path(tmp_dir)
        home_dir = tmp_path / "home"
        home_dir.mkdir(parents=True, exist_ok=True)
        probe_file = tmp_path / "main.swift"
        probe_bin = tmp_path / "probe_language_prompts"
        probe_file.write_text(probe_source, encoding="utf-8")

        compile_proc = subprocess.run(
            [
                "swiftc",
                "-framework",
                "Foundation",
                str(CONFIG_SWIFT),
                str(probe_file),
                "-o",
                str(probe_bin),
            ],
            capture_output=True,
            text=True,
            check=False,
        )
        if compile_proc.returncode != 0:
            return compile_proc

        env = {
            **os.environ,
            "HOME": str(home_dir),
            "CFFIXED_USER_HOME": str(home_dir),
        }
        return subprocess.run(
            [str(probe_bin)],
            capture_output=True,
            text=True,
            env=env,
            check=False,
        )


class TestLanguagePromptResolution(unittest.TestCase):
    def test_supported_languages_include_common_languages_with_english_codes(
        self,
    ) -> None:
        probe_source = """import Foundation

let codes = Set(AppConfig.supportedLanguages.map { $0.code })
let required: [String] = [
    "Simplified Chinese",
    "English",
    "Russian",
    "Japanese",
    "Korean",
    "French",
    "German",
    "Spanish"
]

for req in required {
    guard codes.contains(req) else {
        fputs("FAIL: missing language code \\(req)\\n", stderr)
        exit(1)
    }
}

guard let russian = AppConfig.supportedLanguages.first(where: { $0.code == "Russian" }),
      russian.displayName.contains("俄语") else {
    fputs("FAIL: Russian option missing or displayName does not contain 俄语\\n", stderr)
    exit(1)
}

print("SUPPORTED_LANGUAGES_OK")
"""
        proc = _compile_and_run_swift_probe(probe_source)
        self.assertEqual(
            proc.returncode,
            0,
            f"Supported languages probe failed:\n{proc.stderr}",
        )
        self.assertIn("SUPPORTED_LANGUAGES_OK", proc.stdout)

    def test_default_prompts_contain_languages_placeholder_and_substitute_selected_language(
        self,
    ) -> None:
        probe_source = """import Foundation

guard AppConfig.defaultTranslatePrompt.contains("<languages>") else {
    fputs("FAIL: defaultTranslatePrompt must contain <languages>\\n", stderr)
    exit(1)
}
guard AppConfig.defaultExplainPrompt.contains("<languages>") else {
    fputs("FAIL: defaultExplainPrompt must contain <languages>\\n", stderr)
    exit(1)
}
guard !AppConfig.defaultExplainPrompt.contains("排版纪律") else {
    fputs("FAIL: defaultExplainPrompt must not contain 排版纪律\\n", stderr)
    exit(1)
}

let resolvedTranslate = AppConfig.resolvePrompt(AppConfig.defaultTranslatePrompt, language: "Russian")
let resolvedExplain = AppConfig.resolvePrompt(AppConfig.defaultExplainPrompt, language: "Russian")

guard !resolvedTranslate.contains("<languages>") && resolvedTranslate.contains("Russian") else {
    fputs("FAIL: resolvedTranslate did not substitute <languages> with Russian: \\(resolvedTranslate)\\n", stderr)
    exit(1)
}
guard !resolvedExplain.contains("<languages>") && resolvedExplain.contains("Russian") else {
    fputs("FAIL: resolvedExplain did not substitute <languages> with Russian: \\(resolvedExplain)\\n", stderr)
    exit(1)
}

print("DEFAULT_PROMPTS_SUBSTITUTE_OK")
"""
        proc = _compile_and_run_swift_probe(probe_source)
        self.assertEqual(
            proc.returncode,
            0,
            f"Default prompt placeholder substitution probe failed:\n{proc.stderr}",
        )
        self.assertIn("DEFAULT_PROMPTS_SUBSTITUTE_OK", proc.stdout)

    def test_custom_prompt_without_placeholder_ignores_selected_language(
        self,
    ) -> None:
        probe_source = """import Foundation

let custom = "Translate everything to French directly."
let resolved = AppConfig.resolvePrompt(custom, language: "Russian")

guard resolved == custom && !resolved.contains("Russian") else {
    fputs("FAIL: custom prompt without placeholder was altered: \\(resolved)\\n", stderr)
    exit(1)
}

print("CUSTOM_PROMPT_NO_PLACEHOLDER_OK")
"""
        proc = _compile_and_run_swift_probe(probe_source)
        self.assertEqual(
            proc.returncode,
            0,
            f"Custom prompt without placeholder probe failed:\n{proc.stderr}",
        )
        self.assertIn("CUSTOM_PROMPT_NO_PLACEHOLDER_OK", proc.stdout)


class TestLanguageConfigPersistenceAndUI(unittest.TestCase):
    def test_legacy_config_json_defaults_and_custom_prompts_roundtrip(self) -> None:
        probe_source = """import Foundation

let configDir = ("~/.config/popdict" as NSString).expandingTildeInPath
let configPath = configDir + "/config.json"
let fm = FileManager.default
let backupData = fm.contents(atPath: configPath)
defer {
    if let data = backupData {
        try? fm.createDirectory(atPath: configDir, withIntermediateDirectories: true)
        try? data.write(to: URL(fileURLWithPath: configPath), options: .atomic)
    } else {
        try? fm.removeItem(atPath: configPath)
    }
}

try? fm.createDirectory(atPath: configDir, withIntermediateDirectories: true)
let legacyJSON = \"\"\"
{
  "active": "DeepSeek",
  "providers": [
    {
      "name": "DeepSeek",
      "format": "openai",
      "baseURL": "https://api.deepseek.com/v1",
      "apiKey": "sk-test",
      "model": "deepseek-chat",
      "vision": false
    }
  ]
}
\"\"\"
try! legacyJSON.write(toFile: configPath, atomically: true, encoding: .utf8)

AppConfig.shared.load()
guard AppConfig.shared.language == "Simplified Chinese" else {
    fputs("FAIL: legacy config should default language to Simplified Chinese, got \\(AppConfig.shared.language)\\n", stderr)
    exit(1)
}
guard !AppConfig.shared.resolvedTranslatePrompt.contains("<languages>")
        && AppConfig.shared.resolvedTranslatePrompt.contains("Simplified Chinese") else {
    fputs("FAIL: default resolvedTranslatePrompt invalid: \\(AppConfig.shared.resolvedTranslatePrompt)\\n", stderr)
    exit(1)
}
guard !AppConfig.shared.resolvedExplainPrompt.contains("<languages>")
        && AppConfig.shared.resolvedExplainPrompt.contains("Simplified Chinese") else {
    fputs("FAIL: default resolvedExplainPrompt invalid: \\(AppConfig.shared.resolvedExplainPrompt)\\n", stderr)
    exit(1)
}

let customTranslate = "Custom translate into <languages> only."
let customExplain = "Custom explain in <languages> clearly."
let saved = AppConfig.shared.setLanguageAndPrompts(
    language: "Russian",
    translatePrompt: customTranslate,
    explainPrompt: customExplain
)
guard saved else {
    fputs("FAIL: setLanguageAndPrompts returned false\\n", stderr)
    exit(1)
}
guard AppConfig.shared.language == "Russian"
        && AppConfig.shared.translatePrompt == customTranslate
        && AppConfig.shared.explainPrompt == customExplain else {
    fputs("FAIL: in-memory properties not updated after setLanguageAndPrompts\\n", stderr)
    exit(1)
}
guard AppConfig.shared.resolvedTranslatePrompt == "Custom translate into Russian only." else {
    fputs("FAIL: unexpected resolvedTranslatePrompt: \\(AppConfig.shared.resolvedTranslatePrompt)\\n", stderr)
    exit(1)
}
guard AppConfig.shared.resolvedExplainPrompt == "Custom explain in Russian clearly." else {
    fputs("FAIL: unexpected resolvedExplainPrompt: \\(AppConfig.shared.resolvedExplainPrompt)\\n", stderr)
    exit(1)
}

guard let diskText = try? String(contentsOfFile: configPath, encoding: .utf8),
      diskText.contains("Russian"),
      diskText.contains(customTranslate),
      diskText.contains(customExplain) else {
    fputs("FAIL: config.json on disk missing saved language or custom prompts\\n", stderr)
    exit(1)
}

print("PERSISTENCE_ROUNDTRIP_OK")
"""
        proc = _compile_and_run_swift_probe(probe_source)
        self.assertEqual(
            proc.returncode,
            0,
            f"Config persistence roundtrip probe failed:\n{proc.stderr}",
        )
        self.assertIn("PERSISTENCE_ROUNDTRIP_OK", proc.stdout)

    def test_main_and_settings_use_shared_language_prompts_without_single_hanzi_heuristic(
        self,
    ) -> None:
        main_content = MAIN_SWIFT.read_text(encoding="utf-8")
        self.assertNotIn(
            "hasChinese(",
            main_content,
            "popdict-app/main.swift must not use legacy single-hanzi heuristic hasChinese(",
        )
        self.assertIn(
            "AppConfig.shared.resolvedTranslatePrompt",
            main_content,
            "popdict-app/main.swift must use AppConfig.shared.resolvedTranslatePrompt for translation",
        )
        self.assertIn(
            "AppConfig.shared.resolvedExplainPrompt",
            main_content,
            "popdict-app/main.swift must use AppConfig.shared.resolvedExplainPrompt for explanation",
        )

        settings_content = SETTINGS_SWIFT.read_text(encoding="utf-8")
        self.assertIn(
            '"语言"',
            settings_content,
            'popdict-app/Settings.swift must include the "语言" tab in Preferences',
        )


if __name__ == "__main__":
    unittest.main()
