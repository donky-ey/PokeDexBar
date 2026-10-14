#!/usr/bin/env python3
"""PokéAPI 공식 아이템 이름(ko/en/ja) → 테스트 픽스처. 개발 시 손으로 실행해 산출물을 커밋한다.

왜 있나: 도구 라벨 109개를 기억으로 적었더니 37개가 공식 이름과 달랐다 — 번개의돌(→천둥의돌),
생크림(→휘핑팝), 유석(→운석), 백금옥(→큰백금옥) 같은 식이다. 사람 눈으로는 안 잡히는 부류라
기계로 막는다: 이 스크립트가 공식 이름을 받아 픽스처로 떨어뜨리고, `ItemNameTests` 가 앱 라벨을
그 픽스처와 대조한다. 테스트는 네트워크를 안 탄다(test-gate 는 오프라인이어야 한다).

`generate-slugs.py` 와 같은 패턴이다 — 받아서 커밋하고, 테스트는 커밋된 것만 본다.
"""
import json
import re
import sys
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor

SRC = "Sources/PokeDexBar/Player/"
OUT = "Tests/PokeDexBarTests/Fixtures/ItemNames/official-item-names.json"
LANGS = ("ko", "en", "ja")

# 앱 키 → PokéAPI 슬러그. `EvolutionItem` 은 PokéAPI 이름을 그대로 쓰므로(파서가 그 이름으로
# 조회한다) 매핑이 필요 없다. `FormItem` 은 `form-` 접두 + 앱이 고른 어순이라 여기서 잇는다.
APP_TO_API = {
    # 아르세우스 플레이트 — 타입명이 아니라 각자의 고유명이다(불꽃=flame, 물=splash …).
    "form-plate-fire": "flame-plate",
    "form-plate-water": "splash-plate",
    "form-plate-electric": "zap-plate",
    "form-plate-grass": "meadow-plate",
    "form-plate-ice": "icicle-plate",
    "form-plate-fighting": "fist-plate",
    "form-plate-poison": "toxic-plate",
    "form-plate-ground": "earth-plate",
    "form-plate-flying": "sky-plate",
    "form-plate-psychic": "mind-plate",
    "form-plate-bug": "insect-plate",
    "form-plate-rock": "stone-plate",
    "form-plate-ghost": "spooky-plate",
    "form-plate-dragon": "draco-plate",
    "form-plate-dark": "dread-plate",
    "form-plate-steel": "iron-plate",
    "form-plate-fairy": "pixie-plate",
    # 실버디 메모리 · 게노세크트 카세트 · 오거폰 가면 — 어순만 뒤집히거나 접두만 다르다.
    **{f"form-memory-{t}": f"{t}-memory" for t in (
        "fire", "water", "electric", "grass", "ice", "fighting", "poison", "ground",
        "flying", "psychic", "bug", "rock", "ghost", "dragon", "dark", "steel", "fairy")},
    **{f"form-drive-{d}": f"{d}-drive" for d in ("douse", "shock", "burn", "chill")},
    **{f"form-mask-{m}": f"{m}-mask" for m in ("wellspring", "hearthflame", "cornerstone")},
    # 전설 폼 도구 — 접두만 떼면 된다.
    **{f"form-{k}": k for k in (
        "meteorite", "griseous-core", "gracidea", "adamant-crystal", "lustrous-globe",
        "red-orb", "blue-orb", "prison-bottle", "reveal-glass", "dna-splicers",
        "zygarde-cube", "reins-of-unity", "rusted-sword", "rusted-shield", "tera-orb")},
    # 가방 아이템과 지닌 물건이 따로 등록돼 있다 — 이 앱이 쓰는 건 가방 쪽이다.
    "form-ultranecrozium-z": "ultranecrozium-z--bag",
}

# PokéAPI 에 대응 아이템이 **없는** 키. 원작에 아이템으로 존재하지 않거나(로토무의 가전은 가방
# 아이템이 아니라 가전이고, 소울하트는 특성이다) 이 앱이 만든 것(피카츄 변장 트렁크)이다.
# 공식 이름이 없다는 사실 자체를 적어 둬야 "빠뜨린 것"과 구별된다.
INVENTED = {
    "form-appliance-heat", "form-appliance-wash", "form-appliance-frost",
    "form-appliance-fan", "form-appliance-mow",   # 로토무 — PokéAPI 는 rotom-catalog 하나뿐
    "form-costume-trunk",                          # 피카츄 변장 — 원작에 아이템이 없다
    "form-gs-ball",                                # 애니 설정 — PokéAPI 아이템 목록에 없다
    "form-soul-heart",                             # 마기아나 — 아이템이 아니라 특성
}


def fetch(url):
    req = urllib.request.Request(url, headers={"User-Agent": "PokeDexBar-item-names/1.0"})
    for attempt in range(4):
        try:
            with urllib.request.urlopen(req, timeout=30) as response:
                return json.load(response)
        except Exception:
            if attempt == 3:
                raise
    raise AssertionError("unreachable")


def app_keys(filename):
    """enum 의 raw value 가 곧 앱 키다 — 어떤 도구가 있는지는 소스가 단일 소스다."""
    source = open(SRC + filename).read()
    return re.findall(r'case \w+ = "([a-z0-9-]+)"', source)


def main():
    keys = app_keys("EvolutionItem.swift") + app_keys("FormItem.swift")
    if len(keys) != len(set(keys)):
        raise SystemExit("앱 키가 겹친다 — 인벤토리 한 칸을 두고 다툰다")

    wanted = {}
    for key in keys:
        if key in INVENTED:
            continue
        slug = APP_TO_API.get(key, key)
        if slug.startswith("form-"):
            raise SystemExit(f"{key} 를 PokéAPI 슬러그로 이을 수 없다 — APP_TO_API 나 INVENTED 에 넣어라")
        wanted[key] = slug

    with ThreadPoolExecutor(max_workers=8) as pool:
        fetched = dict(zip(wanted, pool.map(
            lambda s: fetch(f"https://pokeapi.co/api/v2/item/{s}"), wanted.values())))

    official = {}
    for key, dto in fetched.items():
        by_lang = {n["language"]["name"]: n["name"] for n in dto["names"]}
        missing = [lang for lang in LANGS if not by_lang.get(lang)]
        if missing:
            raise SystemExit(f"{key}({wanted[key]}): {missing} 이름이 없다")
        official[key] = {lang: by_lang[lang] for lang in LANGS}

    payload = {"official": dict(sorted(official.items())), "invented": sorted(INVENTED)}
    with open(OUT, "w") as f:
        json.dump(payload, f, ensure_ascii=False, indent=2, sort_keys=False)
        f.write("\n")
    print(f"{len(official)} items (+{len(INVENTED)} invented) -> {OUT}")


if __name__ == "__main__":
    sys.exit(main())
