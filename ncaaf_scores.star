"""
Applet: NCAAF Scores
Summary: College football scores
Description: Shows live/recent NCAA Football scores from ESPN's public scoreboard feed, cycling through games. Optionally filter to a favorite team.
Author: Matt
"""

load("render.star", "render")
load("http.star", "http")
load("encoding/json.star", "json")
load("encoding/base64.star", "base64")
load("schema.star", "schema")
load("cache.star", "cache")

ESPN_URL = "https://site.api.espn.com/apis/site/v2/sports/football/college-football/scoreboard"

DEFAULT_COLOR_LIVE = "#FFD700"
DEFAULT_COLOR_FINAL = "#AAAAAA"
DEFAULT_COLOR_UPCOMING = "#55AAFF"

def main(config):
    favorite = config.str("favorite_team", "")
    games = get_games()

    if favorite:
        favorite_lower = favorite.lower()
        filtered = [g for g in games if favorite_lower in g["home"].lower() or favorite_lower in g["away"].lower()]
        if filtered:
            games = filtered

    if not games:
        return render.Root(
            child = render.Box(
                render.WrappedText(
                    content = "No NCAAF games found",
                    color = "#FFFFFF",
                    align = "center",
                ),
            ),
        )

    frames = [render_game(g) for g in games]

    return render.Root(
        delay = 3500,
        child = render.Animation(children = frames),
    )

def get_games():
    cached = cache.get("ncaaf_scores")
    if cached != None:
        return json.decode(cached)

    res = http.get(ESPN_URL, ttl_seconds = 60)
    if res.status_code != 200:
        return []

    data = res.json()
    events = data.get("events", [])
    games = []

    for event in events:
        competitions = event.get("competitions", [])
        if not competitions:
            continue
        comp = competitions[0]
        competitors = comp.get("competitors", [])
        if len(competitors) < 2:
            continue

        home = None
        away = None
        for c in competitors:
            if c.get("homeAway") == "home":
                home = c
            else:
                away = c
        if home == None or away == None:
            continue

        status = comp.get("status", {}).get("type", {})
        state = status.get("state", "pre")  # pre, in, post
        short_detail = status.get("shortDetail", "")

        home_team = home.get("team", {})
        away_team = away.get("team", {})

        games.append({
            "home": home_team.get("abbreviation", "HOM"),
            "away": away_team.get("abbreviation", "AWY"),
            "home_score": home.get("score", "0"),
            "away_score": away.get("score", "0"),
            "home_color": normalize_color(home_team.get("color", "")),
            "away_color": normalize_color(away_team.get("color", "")),
            "home_logo": home_team.get("logo", ""),
            "away_logo": away_team.get("logo", ""),
            "home_rank": get_rank(home),
            "away_rank": get_rank(away),
            "state": state,
            "detail": short_detail,
        })

    cache.set("ncaaf_scores", json.encode(games), ttl_seconds = 60)
    return games

def get_rank(competitor):
    rank = competitor.get("curatedRank", {}).get("current", 99)
    if rank and rank >= 1 and rank <= 25:
        return rank
    return None

def normalize_color(hex_color):
    if not hex_color:
        return "#333333"
    hex_color = hex_color.strip()
    if not hex_color.startswith("#"):
        hex_color = "#" + hex_color
    if len(hex_color) != 7:
        return "#333333"
    if hex_color.lower() == "#000000":
        return "#333333"
    return hex_color

def contrast_text_color(hex_color):
    hex_color = hex_color.lstrip("#")
    r = int(hex_color[0:2], 16)
    g = int(hex_color[2:4], 16)
    b = int(hex_color[4:6], 16)
    luminance = (0.299 * r + 0.587 * g + 0.114 * b)
    if luminance > 140:
        return "#000000"
    return "#FFFFFF"

def get_logo(url):
    if not url:
        return None

    cache_key = "logo_%s" % url
    cached = cache.get(cache_key)
    if cached != None:
        return base64.decode(cached)

    res = http.get(url, ttl_seconds = 86400)
    if res.status_code != 200:
        return None

    body = res.body()
    cache.set(cache_key, base64.encode(body), ttl_seconds = 86400)
    return body

def render_game(g):
    if g["state"] == "in":
        status_color = DEFAULT_COLOR_LIVE
    elif g["state"] == "post":
        status_color = DEFAULT_COLOR_FINAL
    else:
        status_color = DEFAULT_COLOR_UPCOMING

    away_logo_bytes = get_logo(g["away_logo"])
    home_logo_bytes = get_logo(g["home_logo"])

    return render.Column(
        expanded = True,
        children = [
            render_team_row(
                logo_bytes = away_logo_bytes,
                abbrev = g["away"],
                score = g["away_score"],
                team_color = g["away_color"],
                rank = g["away_rank"],
            ),
            render_team_row(
                logo_bytes = home_logo_bytes,
                abbrev = g["home"],
                score = g["home_score"],
                team_color = g["home_color"],
                rank = g["home_rank"],
            ),
            render.Box(
                height = 6,
                child = render.Text(content = g["detail"], color = status_color, font = "tom-thumb"),
            ),
        ],
    )

def render_team_row(logo_bytes, abbrev, score, team_color, rank):
    if logo_bytes:
        logo_chip = render.Box(
            width = 13,
            height = 13,
            color = "#000000",
            child = render.Row(
                expanded = True,
                main_align = "center",
                cross_align = "center",
                children = [render.Image(src = logo_bytes, width = 12, height = 12)],
            ),
        )
    else:
        logo_chip = render.Box(width = 13, height = 13, color = "#000000")

    text_color = contrast_text_color(team_color)

    label = abbrev
    if rank:
        label = "#%d %s" % (rank, abbrev)

    return render.Box(
        width = 64,
        height = 13,
        color = team_color,
        child = render.Row(
            expanded = True,
            main_align = "space_between",
            cross_align = "center",
            children = [
                render.Row(
                    cross_align = "center",
                    children = [
                        logo_chip,
                        render.Box(width = 3, height = 1),
                        render.Text(content = label, color = text_color, font = "tb-8"),
                    ],
                ),
                render.Row(
                    children = [
                        render.Text(content = score, color = text_color, font = "tb-8"),
                        render.Box(width = 2, height = 1),
                    ],
                ),
            ],
        ),
    )

def get_schema():
    return schema.Schema(
        version = "1",
        fields = [
            schema.Text(
                id = "favorite_team",
                name = "Favorite Team",
                desc = "Filter to games involving this team (e.g. 'Colorado', 'Ohio State'). Leave blank to show all games.",
                icon = "football",
            ),
        ],
    )
