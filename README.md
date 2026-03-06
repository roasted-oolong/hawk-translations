# Hawk Translations — Console Runner

Runs the full translation workflow from your WSL terminal.  
Uses **Claude Sonnet 4.6** for all phases except Phase 2, which uses **Claude Opus 4.6**.

---

## One-Time Setup

### 1. Get an Anthropic API key

1. Go to [console.anthropic.com](https://console.anthropic.com)
2. Sign up or log in
3. Navigate to **API Keys** in the left sidebar
4. Click **Create Key** — give it a name like `hawk-translations`
5. Copy the key immediately (you won't see it again)

### 2. Add billing

The API requires a payment method even for small usage.  
Go to **Settings → Billing** in the console and add a card.  
For reference, a full chapter session will typically cost under $0.50.

### 3. Install dependencies

```bash
cd ~/hawk-translations
pip install anthropic python-dotenv
```

### 4. Create your .env file

```bash
cp .env.example .env
nano .env
```

Replace `your_api_key_here` with your actual key. Save with `Ctrl+X → Y → Enter`.

### 5. Verify config.py

Open `config.py` and confirm `PROJECT_ROOT` matches your actual project path:

```python
PROJECT_ROOT = "/home/jenna/hawk-translations"
```

---

## Running a Session

```bash
cd ~/hawk-translations
python translate.py
```

The script will:
1. Auto-detect the next untranslated chapter
2. Ask you to confirm before starting
3. Walk through all 11 steps with checkpoint pauses
4. Use Opus only for the Phase 2 rewrite
5. Write the final output file and update all bible files

### At checkpoints

Type `CONFIRM` to proceed.  
Type any corrections or notes to have them incorporated before continuing.

---

## File layout expected

```
hawk-translations/
  translate.py
  config.py
  .env
  [series name]/
    [novel name]/
      novel_info.md
      translation_guidelines.md
      /bible/
        characters.md
        cultural_phrases.md
        locations.md
        story.md
        terminology.md
      /chapters/
        chapter01_korean.txt       ← untranslated source
        Chapter 1 - Title.txt      ← output (created by script)
        Chapter 1 - ANOTHER TRANSLATION.txt  ← style reference (optional)
```

---

## Adjusting token limits

If chapters are very long and responses are getting cut off, increase `MAX_TOKENS` in `config.py`:

```python
MAX_TOKENS = 12000
```

---

## Costs (approximate)

| Phase | Model | Cost per chapter |
|-------|-------|-----------------|
| All other steps | Sonnet 4.6 | ~$0.05–0.15 |
| Phase 2 rewrite | Opus 4.6 | ~$0.15–0.35 |
| **Total** | | **~$0.20–0.50** |

Bible files are prompt-cached, which cuts repeated input costs by ~90%.