import requests
import re
from collections import defaultdict

BLOCKLIST_URLS = [
    ["https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/adblock/light.txt",          "light",            False],
    ["https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/adblock/multi.txt",          "normal",           True],
    ["https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/adblock/pro.txt",            "extended",         True],
    ["https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/adblock/pro.mini.txt",       "extended_mini",    False],
    ["https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/adblock/pro.plus.txt",       "aggressive",       True],
    ["https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/adblock/pro.plus.mini.txt",  "aggressive_mini",  False],
    ["https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/adblock/ultimate.txt",       "ultimate",         False],
    ["https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/adblock/ultimate.mini.txt",  "ultimate_mini",    False],
    ["https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/adblock/nrd7.txt",           "NRD",              False],
    ["https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/adblock/nrd14-8.txt",        "NRD",              False],
    ["https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/adblock/nrd21-15.txt",       "NRD",              True],
    ["https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/adblock/nrd28-22.txt",       "NRD",              True]
]

OUTPUT_PREFIX = "AG"
CONSOLIDATE = True

def log(msg):
    print(f"[INFO] {msg}")


def fetch_list(url):
    log(f"Fetching list: {url}")
    try:
        response = requests.get(url, timeout=20)
        response.raise_for_status()
        lines = response.text.splitlines()
        log(f"Fetched {len(lines)} lines")
        return lines
    except Exception as e:
        log(f"ERROR fetching {url}: {e}")
        return []


def normalize_line(line):
    line = line.strip()

    # Skip empty or comment lines
    if not line or line.startswith("#") or line.startswith("!"):
        return None

    # Remove inline comments
    line = re.split(r"[#!]", line)[0].strip()

    # Hosts format
    parts = line.split()
    if len(parts) >= 2 and re.match(r"^\d+\.\d+\.\d+\.\d+$", parts[0]):
        domain = parts[1]
        return f"||{domain}^"

    # Already adblock format
    if line.startswith("||"):
        return line

    # Plain domain
    if re.match(r"^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$", line):
        return f"||{line}^"

    return None


def process_tier(urls):
    rules = set()

    for url in urls:
        lines = fetch_list(url)

        valid = 0
        for line in lines:
            normalized = normalize_line(line)
            if normalized:
                rules.add(normalized)
                valid += 1

        log(f"Processed {url} → {valid} valid rules")

    log(f"Total unique rules in tier: {len(rules)}")
    return rules  # return set for easier merging


def group_by_tier(blocklists):
    tier_map = defaultdict(list)

    enabled_count = 0
    skipped_count = 0

    for url, tier, enabled in blocklists:
        if enabled:
            tier_map[tier].append(url)
            enabled_count += 1
        else:
            log(f"Skipping disabled list: {url}")
            skipped_count += 1

    log(f"Enabled lists: {enabled_count}, Skipped lists: {skipped_count}")
    return tier_map


def save_rules(filename, rules):
    log(f"Saving {len(rules)} rules to {filename}")

    with open(filename, "w") as f:
        for rule in sorted(rules):
            f.write(rule + "\n")

    log(f"Finished writing {filename}")


def main():
    log("Starting blocklist consolidation")

    tier_map = group_by_tier(BLOCKLIST_URLS)

    if not tier_map:
        log("No enabled blocklists found. Exiting.")
        return

    log(f"Detected tiers: {', '.join(tier_map.keys())}")

    all_rules = set()
    tier_results = {}

    # Process each tier
    for tier, urls in tier_map.items():
        log(f"--- Processing tier: {tier} ---")
        rules = process_tier(urls)
        tier_results[tier] = rules
        all_rules.update(rules)

    # Output logic
    if CONSOLIDATE:
        log("--- Consolidating all tiers into a single file ---")
        log(f"Total unique rules across all tiers: {len(all_rules)}")

        filename = f"{OUTPUT_PREFIX}_all.txt"
        save_rules(filename, all_rules)

    else:
        log("--- Saving per-tier files ---")
        for tier, rules in tier_results.items():
            filename = f"{OUTPUT_PREFIX}_{tier}.txt"
            save_rules(filename, rules)

    log("All processing completed successfully")


if __name__ == "__main__":
    main()