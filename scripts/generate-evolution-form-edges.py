#!/usr/bin/env python3
"""진화 조건·결과가 갈리는 간선의 전수 목록 → 테스트 픽스처. 개발 시 손으로 실행해 산출물을 커밋한다.

두 부류를 센다. ① 쓴 도구가 `evolved_pokemon_form` 을 가르는 간선 ② `required_pokemon_form`
으로 **조건이 실제로 갈리는** 간선. 카탈로그(`EvolvedFormCatalog`·`BirthFormCatalog`)가 이 목록을
다 덮는지 `EvolutionFormCoverageTests` 가 본다. 새 세대가 이런 간선을 하나 더하면 테스트가 깨져서
알려 준다 — 카탈로그를 손으로만 채우면 아무도 모르는 채 나가기 때문이다.

`generate-item-names.py` 와 같은 패턴이다 — 받아서 커밋하고, 테스트는 커밋된 것만 본다(오프라인).
540체인을 받아서 수십 초~몇 분 걸린다.

**0 이 아닌 것을 확인하고 쓴다** — 한 번도 참이 안 되는 가드는 방어가 아니라 장식이다(CLAUDE.md).

**이 쿼리는 이미 한 번 틀렸다 — "필드가 있다"로 세지 마라, "값이 갈린다"로 세라.**
`required_pokemon_form` 이 있는 간선을 세면 **47건**이 나온다. 그중 29건은 지방(`-alola` 등)이라
`PokeAPIClient.isRegional` 이 이미 가르고, 9건(이브이·피카츄)은 그 종 자신의 폼을 가리킨다. 나머지도
대개 **같은 조건을 폼 수만큼 되풀이**할 뿐이다 — Scatterbug(664→665)는 20줄이 전부 같은 조건이라
하나로 접어도 아무것도 안 잃는다(파서가 접는 것이 옳다). Burmy·Shellos·Deerling·Spewpa·Flabebe·Floette·
Pumpkaboo 도 같다. Lycanroc(Rockruff 744→745)은 특히 함정이다: 세 줄이 전부 레벨 25이고 `time_of_day` 만
다른데, 이 앱에는 밤낮이 없어 그 필드를 버리므로 갈 것이 없다. 그래서 세는 기준은 **앱이 읽는
필드에서 조건이 폼마다 다른가**(`app_condition`)다. 그 기준으로 정확히 2건(Sinistea 854→855·
Poltchageist 1012→1013)이다(실측 2026-10-14).

**세 번째 간선이 나오면 기대값을 맞추지 말고 멈춰라** — 이 기준으로는 카탈로그의 진짜 공백이다.
"""
import json
import sys
import urllib.request
from concurrent.futures import ThreadPoolExecutor

OUT = "Tests/PokeDexBarTests/Fixtures/EvolutionForms/form-split-edges.json"


def fetch(url):
    # User-Agent 를 꼭 넣는다 — urllib 기본값은 PokéAPI 가 403 으로 돌려보낸다.
    req = urllib.request.Request(url, headers={"User-Agent": "PokeDexBar-evolution-edges/1.0"})
    for attempt in range(4):
        try:
            with urllib.request.urlopen(req, timeout=30) as response:
                return json.load(response)
        except Exception:
            if attempt == 3:
                raise
    raise AssertionError("unreachable")


def species_id(url):
    return int(url.rstrip("/").rsplit("/", 1)[-1])


REGIONS = ("alola", "galar", "hisui", "paldea")   # `Region` enum 과 같은 집합 — 지방 줄은 isRegional 이 가른다


def app_condition(detail):
    """이 앱이 **실제로 읽는** 필드만. `time_of_day` 는 밤낮이 없어 버리는 값이라 뺀다 —
    넣으면 Lycanroc(세 줄이 전부 레벨 25이고 시간대만 다르다)이 거짓 양성으로 잡힌다."""
    return ((detail.get("item") or {}).get("name"),
            (detail.get("held_item") or {}).get("name"),
            (detail.get("trigger") or {}).get("name") == "trade",
            detail.get("min_level"), detail.get("min_happiness"), detail.get("gender"))


def main():
    index = fetch("https://pokeapi.co/api/v2/evolution-chain?limit=1000")["results"]
    with ThreadPoolExecutor(max_workers=12) as pool:
        chains = list(pool.map(lambda r: fetch(r["url"]), index))

    item_decides, form_decides = {}, {}

    def walk(link):
        parent = species_id(link["species"]["url"])
        for child in link["evolves_to"]:
            target = species_id(child["species"]["url"])
            by_item, by_form = {}, {}
            for detail in child.get("evolution_details") or []:
                form = (detail.get("required_pokemon_form") or {}).get("name")
                if form and not any(form.endswith("-" + r) for r in REGIONS):
                    by_form.setdefault(form, set()).add(app_condition(detail))
                    continue
                if form:
                    continue   # 지방 줄은 isRegional 이 이미 가른다
                evolved = (detail.get("evolved_pokemon_form") or {}).get("name")
                item = ((detail.get("item") or {}).get("name")
                        or (detail.get("held_item") or {}).get("name"))
                if evolved and item:
                    by_item.setdefault(item, set()).add(evolved)
            # 도구가 둘 이상이고 결과 모습도 둘 이상일 때만 "도구가 모습을 가른다".
            if len(by_item) > 1 and len({f for s in by_item.values() for f in s}) > 1:
                item_decides[(parent, target)] = sorted(by_item)
            # **값이 있다고 세지 않는다 — 값이 갈리는지를 센다.** 폼마다 줄이 있어도 조건이
            # 같으면 하나로 접어도 아무것도 안 잃는다(독스트링 참고). 존재로 세면 47건이 나온다.
            if len(by_form) > 1 and len({frozenset(v) for v in by_form.values()}) > 1:
                form_decides[(parent, target)] = sorted(by_form)
            walk(child)

    for chain in chains:
        walk(chain["chain"])

    payload = {
        "itemDecides": [{"from": f, "to": t, "items": items}
                        for (f, t), items in sorted(item_decides.items())],
        "formDecides": [{"from": f, "to": t, "forms": forms}
                        for (f, t), forms in sorted(form_decides.items())],
    }
    if not payload["itemDecides"] or not payload["formDecides"]:
        raise SystemExit("한 부류가 0건이다 — 가드가 장식이 된다. 쿼리를 의심하라")
    with open(OUT, "w") as f:
        json.dump(payload, f, ensure_ascii=False, indent=2)
        f.write("\n")
    print(f'itemDecides {len(payload["itemDecides"])} · formDecides {len(payload["formDecides"])} -> {OUT}')


if __name__ == "__main__":
    sys.exit(main())
