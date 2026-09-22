#!/usr/bin/env python3
"""Derive Quark's architecture facts from the repository itself.

Every number this prints is read out of the tree at the moment you run it, so it
cannot go stale the way a hand-written table does. Three maps:

    api   every live backend route, its auth, and its swagger entry
    db    every SQLite table, migration and sqlc query
    app   every Flutter route, the page behind it, and its controller

Run it from anywhere; it locates the repository root itself.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from collections import defaultdict
from pathlib import Path

# --------------------------------------------------------------------------
# Repository root
# --------------------------------------------------------------------------


def repo_root() -> Path:
    """The repository root, from git, falling back to walking up from here."""
    try:
        out = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            capture_output=True,
            text=True,
            check=True,
            cwd=Path(__file__).resolve().parent,
        )
        return Path(out.stdout.strip())
    except (subprocess.CalledProcessError, FileNotFoundError):
        for parent in Path(__file__).resolve().parents:
            if (parent / "go.mod").is_file() and (parent / "AGENTS.md").is_file():
                return parent
    sys.exit("error: could not locate the repository root")


ROOT = repo_root()

# --------------------------------------------------------------------------
# Go source helpers
# --------------------------------------------------------------------------

API_DIR = ROOT / "internal" / "server" / "api"
ROUTES_GO = ROOT / "internal" / "server" / "routes.go"
MIDDLEWARE_GO = ROOT / "internal" / "server" / "middleware" / "middleware.go"
SWAGGER_JSON = ROOT / "docs" / "swagger" / "swagger.json"
API_PREFIX = "/api/v0"

# Routes are declared two ways. Most are a package-level var:
#     var listAlbumsRoute = serverutil.ApiRoute("GET", "/albums", listAlbums)
# A router that needs state returns one from a method instead:
#     func (r *router) getHealthRoute() *serverutil.Route { return serverutil.ApiRoute(...) }
# Read both, or the second kind silently vanishes from the map.
ROUTE_ASSIGN = re.compile(
    r"(\w+)\s*=\s*serverutil\.(?:Api|New)Route\(\s*(.+?)\s*,\s*(.+?)\s*,\s*\w",
    re.S,
)
ROUTE_RETURN = re.compile(
    r"func\s*\([^)]*\)\s*(\w+)\s*\([^)]*\)\s*\*serverutil\.Route\s*\{\s*"
    r"return\s+serverutil\.(?:Api|New)Route\(\s*(.+?)\s*,\s*(.+?)\s*,\s*\w",
    re.S,
)
ROUTE_ANY = re.compile(r"serverutil\.(?:Api|New)Route\(")
# `const sessionIDParam = "sessionId"` and its var/grouped forms
GO_CONST = re.compile(r'^\s*(?:const|var)?\s*(\w+)\s*(?::)?=\s*("(?:[^"\\]|\\.)*")\s*$', re.M)
ROUTER_METHOD = re.compile(r"func\s*\(\s*\w+\s*\*(\w+)\s*\)\s*Routes\(\)[^{]*\{(.*?)\n\}", re.S)
CONSTRUCTOR = re.compile(r"func\s+(New\w*Router)\s*\([^)]*\)[^{]*\{(.*?)\n\}", re.S)
SWAG_BLOCK = re.compile(r"@Router\s+(\S+)\s+\[(\w+)\]")
SWAG_SUMMARY = re.compile(r"@Summary\s+(.+)")

HTTP_METHOD_CONST = {
    "http.MethodGet": "GET",
    "http.MethodHead": "HEAD",
    "http.MethodPost": "POST",
    "http.MethodPut": "PUT",
    "http.MethodPatch": "PATCH",
    "http.MethodDelete": "DELETE",
    "http.MethodOptions": "OPTIONS",
}


def unquote(literal: str) -> str:
    return json.loads(literal)


def resolve_expr(expr: str, consts: dict[str, str]) -> str | None:
    """Resolve a Go string expression built from literals, consts and `+`.

    Routes are written both as `"/files/upload"` and as
    `"/files/upload-session/:" + sessionIDParam`, so a literal-only reader
    silently loses routes. Returns None when a part cannot be resolved.
    """
    # Deliberately no `//` comment stripping: a route path may legitimately
    # contain a double slash ("/files//upload/*rootDir"), and gin cleans it.
    expr = expr.strip()
    if expr in HTTP_METHOD_CONST:
        return HTTP_METHOD_CONST[expr]
    parts = []
    for part in expr.split("+"):
        part = part.strip()
        if not part:
            return None
        if part.startswith('"'):
            try:
                parts.append(unquote(part))
            except json.JSONDecodeError:
                return None
        elif part in consts:
            parts.append(consts[part])
        elif part in HTTP_METHOD_CONST:
            parts.append(HTTP_METHOD_CONST[part])
        else:
            return None
    return "".join(parts)


def normalize_path(path: str) -> str:
    """gin's `:id` / `*filePath` in swagger's `{id}` spelling, slashes collapsed."""
    path = re.sub(r"/{2,}", "/", path)
    path = re.sub(r"[:*](\w+)", r"{\1}", path)
    return path.rstrip("/") or "/"


def go_files(directory: Path):
    for path in sorted(directory.rglob("*.go")):
        if path.name.endswith("_test.go"):
            continue
        yield path


def package_consts(directory: Path) -> dict[str, str]:
    """Every package-level string constant, so route paths can be resolved."""
    consts: dict[str, str] = {}
    for path in go_files(directory):
        for name, literal in GO_CONST.findall(path.read_text()):
            try:
                consts[name] = unquote(literal)
            except json.JSONDecodeError:
                continue
    return consts


# --------------------------------------------------------------------------
# api
# --------------------------------------------------------------------------


def admin_router_constructors() -> set[str]:
    """`pkg.NewRouter` names that routes.go mounts behind RequireAdmin."""
    source = ROUTES_GO.read_text()
    marker = source.find("adminGroup")
    if marker == -1:
        return set()
    return set(re.findall(r"v0_(\w+)\.(New\w*Router)\(", source[marker:]))


def mounted_constructors() -> set[tuple[str, str]]:
    """Every `pkg.NewRouter` routes.go registers, admin or not."""
    return set(re.findall(r"v0_(\w+)\.(New\w*Router)\(", ROUTES_GO.read_text()))


def admin_route_vars(directory: Path, pkg: str, admin_ctors: set[str]) -> set[str]:
    """Route variables reachable from an admin-mounted constructor.

    routes.go names a constructor; the constructor returns a router type; the
    type's Routes() lists the route variables. Follow that chain rather than
    guessing from the file name.
    """
    text = "\n".join(path.read_text() for path in go_files(directory))
    ctor_type = {}
    for name, body in CONSTRUCTOR.findall(text):
        match = re.search(r"&(\w+)\{", body)
        if match:
            ctor_type[name] = match.group(1)
    type_routes = {
        type_name: set(re.findall(r"\b(\w+Route)\b", body))
        for type_name, body in ROUTER_METHOD.findall(text)
    }
    admin_vars: set[str] = set()
    for pkg_name, ctor in admin_ctors:
        if pkg_name != pkg:
            continue
        admin_vars |= type_routes.get(ctor_type.get(ctor, ""), set())
    return admin_vars


def public_paths() -> set[str]:
    """Paths the auth middleware exempts, relative to the API prefix."""
    source = MIDDLEWARE_GO.read_text()
    block = re.search(r"authExemptPaths\s*=\s*map\[string\]bool\{(.*?)\n\}", source, re.S)
    if not block:
        return set()
    return {
        unquote(literal).removeprefix(API_PREFIX)
        for literal in re.findall(r'("(?:[^"\\]|\\.)*")\s*:\s*true', block.group(1))
    }


def named_path_set(name: str) -> set[str]:
    source = MIDDLEWARE_GO.read_text()
    block = re.search(rf"{name}\s*=\s*map\[string\]bool\{{(.*?)\n\}}", source, re.S)
    if not block:
        return set()
    return {
        unquote(literal).removeprefix(API_PREFIX)
        for literal in re.findall(r'("(?:[^"\\]|\\.)*")\s*:\s*true', block.group(1))
    }


def collect_routes() -> list[dict]:
    """Every route declared under internal/server/api, with its context."""
    admin_ctors = admin_router_constructors()
    mounted = mounted_constructors()
    exempt = public_paths()
    auth_limited = named_path_set("authRateLimitedPaths")
    vault_limited = named_path_set("vaultRateLimitedPaths")

    routes: list[dict] = []
    blind: list[tuple[str, int, int]] = []
    for pkg_dir in sorted(p for p in (API_DIR / "v0").iterdir() if p.is_dir()):
        pkg = pkg_dir.name
        consts = package_consts(pkg_dir)
        admin_vars = admin_route_vars(pkg_dir, pkg, admin_ctors)
        is_mounted = any(name == pkg for name, _ in mounted)
        for path in go_files(pkg_dir):
            text = path.read_text()
            summaries = {}
            for chunk in text.split("\nfunc "):
                router = SWAG_BLOCK.search(chunk)
                summary = SWAG_SUMMARY.search(chunk)
                if router:
                    key = (router.group(2).upper(), normalize_path(router.group(1)))
                    summaries[key] = summary.group(1).strip() if summary else ""
            declared = ROUTE_ASSIGN.findall(text) + ROUTE_RETURN.findall(text)
            found = len(ROUTE_ANY.findall(text))
            if found != len(declared):
                blind.append((str(path.relative_to(ROOT)), found, len(declared)))
            for var, method_expr, path_expr in declared:
                method = resolve_expr(method_expr, consts)
                route_path = resolve_expr(path_expr, consts)
                if not method or route_path is None:
                    routes.append(
                        {
                            "package": pkg,
                            "file": str(path.relative_to(ROOT)),
                            "var": var,
                            "method": method or f"?({method_expr.strip()})",
                            "path": route_path
                            if route_path is not None
                            else f"?({path_expr.strip()})",
                            "unresolved": True,
                        }
                    )
                    continue
                normalized = normalize_path(route_path)
                key = (method, normalized)
                if normalized in exempt:
                    auth = "public"
                elif var in admin_vars:
                    auth = "admin"
                else:
                    auth = "user"
                routes.append(
                    {
                        "package": pkg,
                        "file": str(path.relative_to(ROOT)),
                        "var": var,
                        "method": method,
                        "path": normalized,
                        "auth": auth,
                        "mounted": is_mounted,
                        "summary": summaries.get(key),
                        "documented": key in summaries,
                        "rateLimited": "vault"
                        if normalized in vault_limited
                        else ("auth" if normalized in auth_limited else None),
                        "unresolved": False,
                    }
                )
    return routes, blind


def swagger_operations() -> dict[tuple[str, str], dict]:
    if not SWAGGER_JSON.is_file():
        return {}
    spec = json.loads(SWAGGER_JSON.read_text())
    return {
        (verb.upper(), normalize_path(path)): op
        for path, methods in spec.get("paths", {}).items()
        for verb, op in methods.items()
    }


def cmd_api(args) -> int:
    routes, blind = collect_routes()
    swagger = swagger_operations()
    for route in routes:
        route["inSwagger"] = (route["method"], route["path"]) in swagger

    if args.json:
        print(json.dumps({"routes": routes, "swaggerOperations": len(swagger)}, indent=2))
        return 0

    if args.audit:
        return audit(routes, swagger, blind)

    by_package = defaultdict(list)
    for route in routes:
        by_package[route["package"]].append(route)

    print(f"{len(routes)} routes under {API_PREFIX}, {len(swagger)} swagger operations\n")
    for pkg in sorted(by_package):
        entries = sorted(by_package[pkg], key=lambda r: (r["path"], r["method"]))
        print(f"{pkg}/  ({len(entries)})")
        for route in entries:
            flags = route.get("auth", "?")
            if route.get("rateLimited"):
                flags += f",rate:{route['rateLimited']}"
            if not route.get("inSwagger"):
                flags += ",UNDOCUMENTED"
            summary = route.get("summary") or ""
            print(
                f"  {route['method']:<6} {API_PREFIX}{route['path']:<46} "
                f"[{flags}]  {summary}"
            )
            print(f"         {route['file']}")
        print()
    return 0


def audit(routes: list[dict], swagger: dict, blind: list) -> int:
    problems = 0
    live = {(r["method"], r["path"]) for r in routes if not r["unresolved"]}

    if blind:
        problems += len(blind)
        print("Files declaring routes in a shape this script cannot read:")
        for filename, found, parsed in blind:
            print(f"  {filename}: {found} Route calls, {parsed} parsed")
        print("  Teach scripts/map.py the new shape before trusting the counts below.\n")

    unresolved = [r for r in routes if r["unresolved"]]
    if unresolved:
        problems += len(unresolved)
        print("Routes this script could not resolve (fix the script, not the code):")
        for route in unresolved:
            print(f"  {route['method']} {route['path']}  {route['file']}")
        print()

    undocumented = [r for r in routes if not r["unresolved"] and not r["inSwagger"]]
    if undocumented:
        problems += len(undocumented)
        print(f"Live routes missing from swagger ({len(undocumented)}):")
        for route in sorted(undocumented, key=lambda r: r["file"]):
            print(f"  {route['method']:<6} {API_PREFIX}{route['path']:<46} {route['file']}")
        print()

    stale = sorted(key for key in swagger if key not in live)
    if stale:
        problems += len(stale)
        print(f"Swagger operations with no live route ({len(stale)}):")
        for method, path in stale:
            print(f"  {method:<6} {API_PREFIX}{path}")
        print()

    unmounted = [r for r in routes if not r.get("mounted", True)]
    if unmounted:
        problems += len(unmounted)
        print(f"Route packages routes.go never mounts ({len(unmounted)}):")
        for route in unmounted:
            print(f"  {route['method']:<6} {API_PREFIX}{route['path']:<46} {route['file']}")
        print()

    if problems == 0:
        print(
            f"api: {len(routes)} routes, {len(swagger)} swagger operations, "
            "no discrepancies."
        )
    else:
        print(f"api: {problems} discrepancies.")
    return 1 if problems else 0


# --------------------------------------------------------------------------
# db
# --------------------------------------------------------------------------

MIGRATIONS = ROOT / "internal" / "db" / "migrations"
QUERIES = ROOT / "sql" / "queries"
CREATE_TABLE = re.compile(r"CREATE\s+TABLE(?:\s+IF\s+NOT\s+EXISTS)?\s+[`\"']?(\w+)", re.I)
QUERY_NAME = re.compile(r"^--\s*name:\s*(\w+)\s+(:\w+)", re.M)


def cmd_db(args) -> int:
    migrations = defaultdict(dict)
    for path in sorted(MIGRATIONS.glob("*.sql")):
        number, _, rest = path.stem.partition("_")
        name, _, direction = rest.rpartition(".")
        migrations[(number, name)][direction] = path

    tables: dict[str, str] = {}
    for (number, name), pair in sorted(migrations.items()):
        up = pair.get("up")
        if up:
            for table in CREATE_TABLE.findall(up.read_text()):
                tables[table] = f"{number}_{name}"

    queries = {}
    for path in sorted(QUERIES.glob("*.sql")):
        queries[path.name] = QUERY_NAME.findall(path.read_text())

    if args.json:
        print(
            json.dumps(
                {
                    "migrations": [
                        {"number": n, "name": m, "down": "down" in p}
                        for (n, m), p in sorted(migrations.items())
                    ],
                    "tables": tables,
                    "queries": {k: [{"name": n, "kind": c} for n, c in v] for k, v in queries.items()},
                },
                indent=2,
            )
        )
        return 0

    print(f"{len(migrations)} migrations, highest {max(n for n, _ in migrations)}\n")
    for (number, name), pair in sorted(migrations.items()):
        missing = "" if "down" in pair and "up" in pair else "   <-- MISSING PAIR"
        print(f"  {number}  {name}{missing}")

    print(f"\n{len(tables)} tables (table -> the migration that creates it)\n")
    for table, migration in sorted(tables.items()):
        print(f"  {table:<28} {migration}")

    total = sum(len(v) for v in queries.values())
    print(f"\n{total} sqlc queries across {len(queries)} files\n")
    for filename, entries in queries.items():
        print(f"  sql/queries/{filename}  ({len(entries)})")
        for name, kind in entries:
            print(f"    {name:<44} {kind}")
    print(
        "\nRaw SQL outside sqlc is an exception that needs a comment "
        "(AGENTS.md, 'SQL goes through sqlc')."
    )
    return 0


# --------------------------------------------------------------------------
# app
# --------------------------------------------------------------------------

ROUTER_DART = ROOT / "lib" / "router.dart"
APP_ROUTE_CONST = re.compile(r"static\s+const\s+(\w+)\s*=\s*'([^']*)'")
DART_INTERP = re.compile(r"\$\{?AppRoutes\.(\w+)\}?")


def dart_route_bodies(source: str) -> list[tuple[str, int | None]]:
    """The argument list of every GoRoute(...), nested ones included.

    Routes nest (`/files` owns `/files/:path`), so a regex that stops at the
    first `)` loses the children. Match parentheses instead.
    """
    spans = []
    for match in re.finditer(r"GoRoute\(", source):
        depth, index = 0, match.end() - 1
        while index < len(source):
            char = source[index]
            if char == "(":
                depth += 1
            elif char == ")":
                depth -= 1
                if depth == 0:
                    spans.append((match.end(), index))
                    break
            index += 1
    # A child's span sits inside its parent's, which is how the parent path gets
    # prefixed onto `:path(.*)` to give the URL a reader would actually type.
    return [
        (
            source[start:end],
            next(
                (
                    i
                    for i, (s2, e2) in enumerate(spans)
                    if s2 < start and end < e2
                ),
                None,
            ),
        )
        for start, end in spans
    ]


def resolve_dart_path(raw: str, consts: dict[str, str]) -> str:
    """`AppRoutes.docs` or `'${AppRoutes.docs}/:path(.*)'` to a real path."""
    if raw.startswith("AppRoutes."):
        return consts.get(raw.split(".", 1)[1], raw)
    return DART_INTERP.sub(lambda m: consts.get(m.group(1), m.group(0)), raw)


def cmd_app(args) -> int:
    source = ROUTER_DART.read_text()
    consts = dict(APP_ROUTE_CONST.findall(source))

    entries = []
    paths_by_index: dict[int, str] = {}
    for index, (body, parent) in enumerate(dart_route_bodies(source)):
        path_match = re.search(r"path:\s*(AppRoutes\.\w+|'[^']*')", body)
        if not path_match:
            continue
        raw = path_match.group(1).strip("'")
        path = resolve_dart_path(raw, consts)
        if not path.startswith("/"):
            path = f"{paths_by_index.get(parent, '').rstrip('/')}/{path}"
        paths_by_index[index] = path
        builder = re.search(r"builder:.*?(\w+Page)\(", body, re.S)
        redirect = re.search(r"redirect:.*?AppRoutes\.(\w+)", body, re.S)
        entries.append(
            {
                "path": path,
                "page": builder.group(1) if builder else None,
                "redirectsTo": consts.get(redirect.group(1)) if redirect else None,
            }
        )

    public_block = re.search(r"publicRoutes\s*=\s*\{(.*?)\}", source, re.S)
    public = (
        {consts.get(name, name) for name in re.findall(r"AppRoutes\.(\w+)", public_block.group(1))}
        if public_block
        else set()
    )
    admin_block = re.search(r"adminRoutes\s*=\s*\{(.*?)\}", source, re.S)
    admin = (
        {consts.get(name, name) for name in re.findall(r"AppRoutes\.(\w+)", admin_block.group(1))}
        if admin_block
        else set()
    )

    def gate(path: str) -> str:
        if path in public:
            return "public"
        if path in admin:
            return "admin"
        return "auth"

    controllers = sorted(p.name for p in (ROOT / "lib" / "controllers").glob("*.dart"))
    pages = sorted(p.name for p in (ROOT / "lib" / "pages").glob("*.dart"))
    app_widgets = sum(1 for _ in (ROOT / "lib" / "widgets").rglob("*.dart"))
    pkg_widgets = sum(1 for _ in (ROOT / "packages/quark_widgets/lib/src").rglob("*.dart"))

    if args.json:
        print(
            json.dumps(
                {
                    "routes": [{**e, "gate": gate(e["path"])} for e in entries],
                    "controllers": controllers,
                    "pages": pages,
                    "appWidgetFiles": app_widgets,
                    "packageWidgetFiles": pkg_widgets,
                },
                indent=2,
            )
        )
        return 0

    print(f"{len(entries)} go_router routes in lib/router.dart")
    print("(gate: public = in publicRoutes, admin = in adminRoutes, auth = needs a session)\n")
    for entry in entries:
        if entry["page"]:
            target = entry["page"]
        elif entry["redirectsTo"]:
            target = f"-> {entry['redirectsTo']}"
        else:
            target = "-"
        print(f"  {entry['path']:<34} {target:<26} [{gate(entry['path'])}]")

    print(f"\n{len(pages)} pages, {len(controllers)} controllers\n")
    for controller in controllers:
        print(f"  lib/controllers/{controller}")
    print(
        f"\n{app_widgets} widget files still in lib/widgets (service-coupled), "
        f"{pkg_widgets} in packages/quark_widgets/lib/src."
        "\nlib/widgets/README.md is the live inventory of what is waiting on #1600."
    )
    return 0


# --------------------------------------------------------------------------


def main() -> int:
    parser = argparse.ArgumentParser(
        prog="map.py", description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    sub = parser.add_subparsers(dest="command", required=True)

    api = sub.add_parser("api", help="every live backend route, auth and swagger entry")
    api.add_argument("--audit", action="store_true", help="print only swagger/router discrepancies")
    api.add_argument("--json", action="store_true")
    api.set_defaults(func=cmd_api)

    db = sub.add_parser("db", help="migrations, tables and sqlc queries")
    db.add_argument("--json", action="store_true")
    db.set_defaults(func=cmd_db)

    app = sub.add_parser("app", help="Flutter routes, pages and controllers")
    app.add_argument("--json", action="store_true")
    app.set_defaults(func=cmd_app)

    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
