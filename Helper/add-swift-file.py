#!/usr/bin/env python3
# Registers a new Swift file in Amperfy.xcodeproj next to an existing sibling file:
# same group, same target(s). Usage (from repo root):
#   Helper/add-swift-file.py <NewFile.swift> <ExistingSibling.swift>
import hashlib
import re
import sys

PBXPROJ = "Amperfy.xcodeproj/project.pbxproj"


def new_id(seed, existing):
    n = 0
    while True:
        candidate = hashlib.md5(f"{seed}-{n}".encode()).hexdigest()[:24].upper()
        if candidate not in existing:
            return candidate
        n += 1


def main():
    new_name, sibling = sys.argv[1], sys.argv[2]
    s = open(PBXPROJ).read()
    if f"/* {new_name} */" in s:
        print(f"{new_name} already registered")
        return
    existing = set(re.findall(r"\b[0-9A-F]{24}\b", s))

    ref = re.search(
        r"\t\t([0-9A-F]{24}) /\* " + re.escape(sibling) + r" \*/ = \{isa = PBXFileReference;[^\n]*\n", s
    )
    if not ref:
        sys.exit(f"sibling {sibling} not found")
    sibling_ref = ref.group(1)
    file_ref = new_id("ref" + new_name, existing)
    existing.add(file_ref)
    ref_line = (
        f"\t\t{file_ref} /* {new_name} */ = {{isa = PBXFileReference; "
        f"lastKnownFileType = sourcecode.swift; path = \"{new_name}\"; sourceTree = \"<group>\"; }};\n"
    )
    s = s[: ref.end()] + ref_line + s[ref.end():]

    # group membership
    group_entry = f"\t\t\t\t{sibling_ref} /* {sibling} */,\n"
    i = s.index(group_entry) + len(group_entry)
    s = s[:i] + f"\t\t\t\t{file_ref} /* {new_name} */,\n" + s[i:]

    # every target that compiles the sibling compiles the new file too
    for build in re.findall(
        r"\t\t([0-9A-F]{24}) /\* " + re.escape(sibling) + r" in Sources \*/ = \{isa = PBXBuildFile; fileRef = "
        + sibling_ref, s
    ):
        build_id = new_id("build" + new_name + build, existing)
        existing.add(build_id)
        decl = re.search(r"\t\t" + build + r" /\* [^\n]*\n", s)
        s = s[: decl.end()] + (
            f"\t\t{build_id} /* {new_name} in Sources */ = {{isa = PBXBuildFile; "
            f"fileRef = {file_ref} /* {new_name} */; }};\n"
        ) + s[decl.end():]
        phase_entry = f"\t\t\t\t{build} /* {sibling} in Sources */,\n"
        j = s.index(phase_entry) + len(phase_entry)
        s = s[:j] + f"\t\t\t\t{build_id} /* {new_name} in Sources */,\n" + s[j:]

    open(PBXPROJ, "w").write(s)
    print(f"registered {new_name} next to {sibling}")


if __name__ == "__main__":
    main()
