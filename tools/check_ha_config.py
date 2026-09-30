#!/usr/bin/env python3
"""Consistency check for the Home Assistant files (run by `make lint` and CI).

1. Every Jinja template in homeassistant/ must parse.
2. Every referenced heat exchanger entity ID must exist, either
   - created by the ESPHome device (derived from the entity names in esphome/), or
   - created by the HA package itself (input_number, utility_meter, template, sensor).

Catches the classic silent breakage: renaming a sensor in ESPHome changes its
entity ID in HA, and dashboards/templates quietly show "entity not found".
"""

from __future__ import annotations

import pathlib
import re
import sys

import jinja2
import yaml

ROOT = pathlib.Path(__file__).resolve().parents[1]
ESPHOME_DIR = ROOT / "esphome"
HA_DIR = ROOT / "homeassistant"
ESPHOME_MAIN = ESPHOME_DIR / "heat-exchanger-logger.yaml"
ENTITY_DOMAINS = ("sensor", "binary_sensor", "switch", "button", "text_sensor")
REF_RE = re.compile(r"\b(sensor|binary_sensor|switch|button|input_number)\.(heat_exchanger_\w+)")


class TolerantLoader(yaml.SafeLoader):
    """Loads HA/ESPHome YAML, turning custom tags (!include, !secret, ...) into plain values."""


def _any_tag(loader, _suffix, node):
    if isinstance(node, yaml.ScalarNode):
        return loader.construct_scalar(node)
    if isinstance(node, yaml.SequenceNode):
        return loader.construct_sequence(node)
    return loader.construct_mapping(node)


TolerantLoader.add_multi_constructor("!", _any_tag)


def load(path: pathlib.Path):
    return yaml.load(path.read_text(encoding="utf-8"), Loader=TolerantLoader) or {}


def slugify(text: str) -> str:
    return re.sub(r"[^a-z0-9]+", "_", text.lower()).strip("_")


def esphome_entities() -> set[str]:
    main = load(ESPHOME_MAIN)
    device = slugify(main["substitutions"]["friendly_name"])
    files = [ESPHOME_MAIN, *sorted((ESPHOME_DIR / "packages").glob("*.yaml"))]
    found = set()
    for f in files:
        cfg = load(f)
        for domain in ENTITY_DOMAINS:
            for item in cfg.get(domain) or []:
                if not isinstance(item, dict) or item.get("internal"):
                    continue
                # Direct `name:` or nested sub-entities (e.g. wifi_info: ip_address: name:)
                names = [item["name"]] if "name" in item else []
                names += [v["name"] for v in item.values() if isinstance(v, dict) and "name" in v]
                ha_domain = "sensor" if domain == "text_sensor" else domain
                found.update(f"{ha_domain}.{device}_{slugify(n)}" for n in names)
    return found


def ha_package_entities(pkg: dict) -> set[str]:
    found = {f"input_number.{k}" for k in pkg.get("input_number") or {}}
    found |= {f"sensor.{k}" for k in pkg.get("utility_meter") or {}}
    for block in pkg.get("template") or []:
        for domain in ("sensor", "binary_sensor"):
            found |= {f"{domain}.{slugify(e['name'])}" for e in block.get(domain) or []}
    found |= {f"sensor.{slugify(e['name'])}" for e in pkg.get("sensor") or []}
    return found


def walk_strings(node):
    if isinstance(node, str):
        yield node
    elif isinstance(node, dict):
        for v in node.values():
            yield from walk_strings(v)
    elif isinstance(node, list):
        for v in node:
            yield from walk_strings(v)


def main() -> int:
    errors = []
    known = esphome_entities()
    ha_files = sorted(HA_DIR.rglob("*.yaml"))
    for f in ha_files:
        if f.parent.name == "packages":
            known |= ha_package_entities(load(f))

    env = jinja2.Environment()
    for f in ha_files:
        rel = f.relative_to(ROOT)
        for s in walk_strings(load(f)):
            if "{{" in s or "{%" in s:
                try:
                    env.parse(s)
                except jinja2.TemplateSyntaxError as e:
                    errors.append(f"{rel}: template syntax error: {e.message}\n    {s.strip()[:120]}")
        for m in REF_RE.finditer(f.read_text(encoding="utf-8")):
            entity = f"{m[1]}.{m[2]}"
            if entity not in known:
                errors.append(f"{rel}: unknown entity {entity}")

    for e in sorted(set(errors)):
        print(f"ERROR {e}")
    print(f"checked {len(ha_files)} HA files against {len(known)} known entities: "
          f"{'FAILED' if errors else 'OK'}")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
