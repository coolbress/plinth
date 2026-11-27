"""Validate JSON documents against a JSON Schema, standard library only.

    python3 json-schema-check.py <schema.json> <document.json>...

It knows the keywords scripts/floor-check.schema.json uses and no others: a
schema that uses any other keyword is refused, not half-read, so a keyword
added to the schema cannot pass unchecked. One line per error, naming the
document and the path in it; exit 1 when there is any, 2 when the schema
uses a keyword this file does not know.
"""

import json
import re
import sys

KNOWN = {"$schema", "$id", "$defs", "$ref", "title", "description", "type", "enum", "const", "properties",
         "required", "additionalProperties", "items", "minLength", "minimum", "pattern", "allOf", "oneOf",
         "if", "then", "else"}
TYPES = {"object": dict, "array": list, "string": str, "boolean": bool, "null": type(None)}


def keywords(node, path="#"):
    """Every keyword the schema uses that this file does not know."""
    if not isinstance(node, dict):
        return []
    bad = [f"{path}/{k}" for k in node if k not in KNOWN]
    for k in ("properties", "$defs"):
        for name, sub in node.get(k, {}).items():
            bad += keywords(sub, f"{path}/{k}/{name}")
    for k in ("items", "if", "then", "else"):
        if k in node:
            bad += keywords(node[k], f"{path}/{k}")
    for k in ("allOf", "oneOf"):
        for i, sub in enumerate(node.get(k, [])):
            bad += keywords(sub, f"{path}/{k}/{i}")
    if isinstance(node.get("additionalProperties"), dict):
        bad += keywords(node["additionalProperties"], f"{path}/additionalProperties")
    return bad


def is_type(v, t):
    if t == "integer":
        return isinstance(v, int) and not isinstance(v, bool)
    if t == "number":
        return isinstance(v, (int, float)) and not isinstance(v, bool)
    return isinstance(v, TYPES[t]) and not (t != "boolean" and isinstance(v, bool))


def errors(v, s, root, at="$"):
    """The errors of value v against schema node s, as (path, message)."""
    out = []
    if "$ref" in s:
        ref = s["$ref"]
        assert ref.startswith("#/$defs/"), ref
        out += errors(v, root["$defs"][ref[len("#/$defs/"):]], root, at)
    if "type" in s:
        ts = s["type"] if isinstance(s["type"], list) else [s["type"]]
        if not any(is_type(v, t) for t in ts):
            return out + [(at, f"is {json.dumps(v)[:60]}, not {' or '.join(ts)}")]
    if "const" in s and not (v == s["const"] and type(v) is type(s["const"])):
        out.append((at, f"is {json.dumps(v)[:60]}, not {json.dumps(s['const'])}"))
    if "enum" in s and not any(v == e and type(v) is type(e) for e in s["enum"]):
        out.append((at, f"is {json.dumps(v)[:60]}, not one of {s['enum']}"))
    if isinstance(v, str):
        if len(v) < s.get("minLength", 0):
            out.append((at, f"is shorter than {s['minLength']}"))
        if "pattern" in s and not re.search(s["pattern"], v):
            out.append((at, f"{v!r} does not match {s['pattern']}"))
    if is_type(v, "number") and "minimum" in s and v < s["minimum"]:
        out.append((at, f"{v} is below {s['minimum']}"))
    if isinstance(v, dict):
        for k in s.get("required", []):
            if k not in v:
                out.append((at, f"has no {k!r}"))
        props = s.get("properties", {})
        for k, sub in v.items():
            if k in props:
                out += errors(sub, props[k], root, f"{at}.{k}")
            elif s.get("additionalProperties") is False:
                out.append((at, f"has {k!r}, which the schema does not name"))
    if isinstance(v, list) and "items" in s:
        for i, item in enumerate(v):
            out += errors(item, s["items"], root, f"{at}[{i}]")
    for sub in s.get("allOf", []):
        out += errors(v, sub, root, at)
    if "oneOf" in s:
        n = sum(not errors(v, sub, root, at) for sub in s["oneOf"])
        if n != 1:
            out.append((at, f"matches {n} of the oneOf schemas, not exactly one"))
    if "if" in s:
        branch = "then" if not errors(v, s["if"], root, at) else "else"
        if branch in s:
            out += errors(v, s[branch], root, at)
    return out


def main() -> int:
    schema_path, *docs = sys.argv[1:]
    schema = json.load(open(schema_path, encoding="utf-8"))
    unknown = keywords(schema)
    if unknown:
        print(f"{schema_path} uses keywords this validator does not read: {', '.join(unknown)}")
        return 2
    rc = 0
    for d in docs:
        try:
            doc = json.load(open(d, encoding="utf-8"))
        except (OSError, ValueError) as e:
            print(f"{d}: not read as JSON: {e}")
            rc = 1
            continue
        for at, msg in errors(doc, schema, schema):
            print(f"{d}: {at} {msg}")
            rc = 1
    return rc


if __name__ == "__main__":
    sys.exit(main())
