#!/usr/bin/env python3
# Adds an iOS app extension target to Amperfy.xcodeproj and embeds it into the app.
# Usage (from repo root): Helper/add-extension-target.py spec.json
# spec: {"name", "bundleId", "dir", "files": [...], "plist", "entitlements",
#        "shared": [files in Shared/, compiled into the app and the extension], "settings": {...}}
# Example (F-9): {"name": "DriftShare", "bundleId": "de.knauerleo.amperfy-music.Share", "dir": "DriftShare",
#   "files": ["ShareViewController.swift"], "plist": "Info.plist", "entitlements": "DriftShare.entitlements",
#   "shared": ["DriftShareConfig.swift"]}
import hashlib
import json
import re
import sys

PBX = "Amperfy.xcodeproj/project.pbxproj"
APP_TARGET = "508385E321C5965B00C4BB32"
APP_SOURCES = "508385E021C5965B00C4BB32"
MAIN_GROUP = "508385DB21C5965B00C4BB32"
PRODUCTS = "508385E521C5965B00C4BB32"
PROJECT = "508385DC21C5965B00C4BB32"
EMBED_EXT = "50253FA1284A5EEB00BCCFB2"

spec = json.load(open(sys.argv[1]))
s = open(PBX).read()
existing = set(re.findall(r"\b[0-9A-F]{24}\b", s))


def nid(seed):
    n = 0
    while True:
        c = hashlib.md5(f"{spec['name']}-{seed}-{n}".encode()).hexdigest()[:24].upper()
        if c not in existing:
            existing.add(c)
            return c
        n += 1


def section_add(section, text):
    global s
    marker = f"/* End {section} section */\n"
    i = s.index(marker)
    s = s[:i] + text + s[i:]


def list_add(owner_pattern, key, entry):
    """Appends entry to the list `key = (` inside the object starting with owner_pattern."""
    global s
    start = s.index(owner_pattern)
    i = s.index(f"\t{key} = (\n", start) + len(f"\t{key} = (\n")
    end = s.index("\t\t\t);\n", i)
    s = s[:end] + entry + s[end:]


def file_type(name):
    return {
        "swift": "sourcecode.swift",
        "plist": "text.plist.xml",
        "entitlements": "text.plist.entitlements",
    }[name.rsplit(".", 1)[1]]


name, folder = spec["name"], spec["dir"]
target = nid("target")
sources_phase, fw_phase, res_phase = nid("sources"), nid("frameworks"), nid("resources")
product = nid("product")
group = nid("group")
proxy, dep, embed = nid("proxy"), nid("dep"), nid("embed")
cfg_list, cfg_debug, cfg_release = nid("cfglist"), nid("debug"), nid("release")

# files of the extension folder
refs = []
for f in spec["files"] + [spec["plist"], spec["entitlements"]]:
    r = nid("ref" + f)
    refs.append((r, f))
    section_add(
        "PBXFileReference",
        f"\t\t{r} /* {f} */ = {{isa = PBXFileReference; lastKnownFileType = {file_type(f)}; "
        f"path = {json.dumps(f) if '+' in f or ' ' in f else f}; sourceTree = \"<group>\"; }};\n",
    )
section_add(
    "PBXFileReference",
    f"\t\t{product} /* {name}.appex */ = {{isa = PBXFileReference; explicitFileType = \"wrapper.app-extension\"; "
    f"includeInIndex = 0; path = {name}.appex; sourceTree = BUILT_PRODUCTS_DIR; }};\n",
)
children = "".join(f"\t\t\t\t{r} /* {f} */,\n" for r, f in refs)
section_add(
    "PBXGroup",
    f"\t\t{group} /* {folder} */ = {{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n{children}\t\t\t);\n"
    f"\t\t\tpath = {folder};\n\t\t\tsourceTree = \"<group>\";\n\t\t}};\n",
)
list_add(f"\t\t{MAIN_GROUP} = {{", "children", f"\t\t\t\t{group} /* {folder} */,\n")
list_add(f"\t\t{PRODUCTS} /* Products */ = {{", "children", f"\t\t\t\t{product} /* {name}.appex */,\n")

# shared files: one file reference in the Shared group, compiled into the app and the extension
source_builds = []
for r, f in refs:
    if f.endswith(".swift"):
        b = nid("build" + f)
        section_add("PBXBuildFile", f"\t\t{b} /* {f} in Sources */ = {{isa = PBXBuildFile; fileRef = {r} /* {f} */; }};\n")
        source_builds.append((b, f))
shared = spec.get("shared", [])
if shared:
    m = re.search(r"\t\t([0-9A-F]{24}) /\* Shared \*/ = \{\n\t\t\tisa = PBXGroup;", s)
    if m:
        shared_group = m.group(1)
    else:
        shared_group = nid("sharedgroup")
        section_add(
            "PBXGroup",
            f"\t\t{shared_group} /* Shared */ = {{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n\t\t\t);\n"
            f"\t\t\tpath = Shared;\n\t\t\tsourceTree = \"<group>\";\n\t\t}};\n",
        )
        list_add(f"\t\t{MAIN_GROUP} = {{", "children", f"\t\t\t\t{shared_group} /* Shared */,\n")
    for f in shared:
        m = re.search(r"\t\t([0-9A-F]{24}) /\* " + re.escape(f) + r" \*/ = \{isa = PBXFileReference;", s)
        if m:
            r = m.group(1)
        else:
            r = nid("sharedref" + f)
            section_add(
                "PBXFileReference",
                f"\t\t{r} /* {f} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; "
                f"path = {f}; sourceTree = \"<group>\"; }};\n",
            )
            list_add(f"\t\t{shared_group} /* Shared */ = {{", "children", f"\t\t\t\t{r} /* {f} */,\n")
            ab = nid("appbuild" + f)
            section_add("PBXBuildFile", f"\t\t{ab} /* {f} in Sources */ = {{isa = PBXBuildFile; fileRef = {r} /* {f} */; }};\n")
            list_add(f"\t\t{APP_SOURCES} /* Sources */ = {{", "files", f"\t\t\t\t{ab} /* {f} in Sources */,\n")
        b = nid("build" + f)
        section_add("PBXBuildFile", f"\t\t{b} /* {f} in Sources */ = {{isa = PBXBuildFile; fileRef = {r} /* {f} */; }};\n")
        source_builds.append((b, f))

# build phases
files = "".join(f"\t\t\t\t{b} /* {f} in Sources */,\n" for b, f in source_builds)
phase = lambda isa, pid, title, body: (
    f"\t\t{pid} /* {title} */ = {{\n\t\t\tisa = {isa};\n\t\t\tbuildActionMask = 2147483647;\n"
    f"\t\t\tfiles = (\n{body}\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t}};\n"
)
section_add("PBXSourcesBuildPhase", phase("PBXSourcesBuildPhase", sources_phase, "Sources", files))
section_add("PBXFrameworksBuildPhase", phase("PBXFrameworksBuildPhase", fw_phase, "Frameworks", ""))
section_add("PBXResourcesBuildPhase", phase("PBXResourcesBuildPhase", res_phase, "Resources", ""))

# target
section_add(
    "PBXNativeTarget",
    f"\t\t{target} /* {name} */ = {{\n\t\t\tisa = PBXNativeTarget;\n"
    f"\t\t\tbuildConfigurationList = {cfg_list} /* Build configuration list for PBXNativeTarget \"{name}\" */;\n"
    f"\t\t\tbuildPhases = (\n\t\t\t\t{sources_phase} /* Sources */,\n\t\t\t\t{fw_phase} /* Frameworks */,\n"
    f"\t\t\t\t{res_phase} /* Resources */,\n\t\t\t);\n\t\t\tbuildRules = (\n\t\t\t);\n"
    f"\t\t\tdependencies = (\n\t\t\t);\n\t\t\tname = {name};\n\t\t\tproductName = {name};\n"
    f"\t\t\tproductReference = {product} /* {name}.appex */;\n"
    f"\t\t\tproductType = \"com.apple.product-type.app-extension\";\n\t\t}};\n",
)
list_add(f"\t\t\tisa = PBXProject;", "targets", f"\t\t\t\t{target} /* {name} */,\n")

# embed into the app (iOS only, the Mac Catalyst build stays without it)
section_add(
    "PBXContainerItemProxy",
    f"\t\t{proxy} /* PBXContainerItemProxy */ = {{\n\t\t\tisa = PBXContainerItemProxy;\n"
    f"\t\t\tcontainerPortal = {PROJECT} /* Project object */;\n\t\t\tproxyType = 1;\n"
    f"\t\t\tremoteGlobalIDString = {target};\n\t\t\tremoteInfo = {name};\n\t\t}};\n",
)
section_add(
    "PBXTargetDependency",
    f"\t\t{dep} /* PBXTargetDependency */ = {{\n\t\t\tisa = PBXTargetDependency;\n\t\t\tplatformFilter = ios;\n"
    f"\t\t\ttarget = {target} /* {name} */;\n\t\t\ttargetProxy = {proxy} /* PBXContainerItemProxy */;\n\t\t}};\n",
)
list_add(f"\t\t{APP_TARGET} /* Amperfy */ = {{", "dependencies", f"\t\t\t\t{dep} /* PBXTargetDependency */,\n")
section_add(
    "PBXBuildFile",
    f"\t\t{embed} /* {name}.appex in Embed Foundation Extensions */ = {{isa = PBXBuildFile; "
    f"fileRef = {product} /* {name}.appex */; platformFilter = ios; "
    f"settings = {{ATTRIBUTES = (RemoveHeadersOnCopy, ); }}; }};\n",
)
list_add(f"\t\t{EMBED_EXT} /* Embed Foundation Extensions */ = {{", "files",
         f"\t\t\t\t{embed} /* {name}.appex in Embed Foundation Extensions */,\n")

# build settings
settings = {
    "CODE_SIGN_ENTITLEMENTS": f"{folder}/{spec['entitlements']}",
    "CODE_SIGN_IDENTITY": '"Apple Development"',
    "CODE_SIGN_STYLE": "Automatic",
    "CURRENT_PROJECT_VERSION": "1",
    "DEVELOPMENT_TEAM": "45L48D96FZ",
    "GENERATE_INFOPLIST_FILE": "YES",
    "INFOPLIST_FILE": f"{folder}/{spec['plist']}",
    "INFOPLIST_KEY_CFBundleDisplayName": "Drift",
    "IPHONEOS_DEPLOYMENT_TARGET": "26.0",
    "MARKETING_VERSION": "2.1.2",
    "PRODUCT_BUNDLE_IDENTIFIER": f"\"{spec['bundleId']}\"",
    "PRODUCT_NAME": '"$(TARGET_NAME)"',
    "SDKROOT": "iphoneos",
    "SKIP_INSTALL": "YES",
    "SUPPORTED_PLATFORMS": '"iphoneos iphonesimulator"',
    "SUPPORTS_MACCATALYST": "NO",
    "SWIFT_EMIT_LOC_STRINGS": "YES",
    "SWIFT_VERSION": "6.0",
    "TARGETED_DEVICE_FAMILY": '"1,2"',
}
settings.update(spec.get("settings", {}))
body = "".join(f"\t\t\t\t{k} = {v};\n" for k, v in sorted(settings.items()))
rpath = '\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (\n\t\t\t\t\t"$(inherited)",\n\t\t\t\t\t"@executable_path/Frameworks",\n' \
        '\t\t\t\t\t"@executable_path/../../Frameworks",\n\t\t\t\t);\n'
for cid, cname in ((cfg_debug, "Debug"), (cfg_release, "Release")):
    section_add(
        "XCBuildConfiguration",
        f"\t\t{cid} /* {cname} */ = {{\n\t\t\tisa = XCBuildConfiguration;\n\t\t\tbuildSettings = {{\n"
        f"{body}{rpath}\t\t\t}};\n\t\t\tname = {cname};\n\t\t}};\n",
    )
section_add(
    "XCConfigurationList",
    f"\t\t{cfg_list} /* Build configuration list for PBXNativeTarget \"{name}\" */ = {{\n"
    f"\t\t\tisa = XCConfigurationList;\n\t\t\tbuildConfigurations = (\n\t\t\t\t{cfg_debug} /* Debug */,\n"
    f"\t\t\t\t{cfg_release} /* Release */,\n\t\t\t);\n\t\t\tdefaultConfigurationIsVisible = 0;\n"
    f"\t\t\tdefaultConfigurationName = Release;\n\t\t}};\n",
)

open(PBX, "w").write(s)
print(f"added {name} ({target})")
