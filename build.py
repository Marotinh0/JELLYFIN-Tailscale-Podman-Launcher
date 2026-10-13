import re, sys, pathlib
here = pathlib.Path(__file__).resolve().parent
tmpl = (here / "jellyfin.tmpl.sh").read_text()
VERSION = "2.0.0"
flavors = {
 "nvidia": dict(FLAVOR="NVIDIA", FILENAME="jellyfin-nvidia.sh",
   GPU_LINE="NVIDIA (NVENC/NVDEC) through CDI — needs the NVIDIA driver + nvidia-container-toolkit",
   GPU_FEATURE="NVIDIA GPU via CDI (NVENC/NVDEC), CDI spec checked for freshness",
   GPU_REQ="nvidia driver + nvidia-container-toolkit"),
 "amd": dict(FLAVOR="AMD", FILENAME="jellyfin-amd.sh",
   GPU_LINE="AMD (VA-API via Mesa) — the same script also works for Intel iGPU/Arc (JELLYFIN_GPU_VENDOR=intel)",
   GPU_FEATURE="AMD GPU via VA-API (render node only, auto-picks the right GPU)",
   GPU_REQ="mesa VA-API drivers (usually installed)"),
}
def process(text, flavor):
    out, stack = [], []   # stack of (active, branch_taken_flag)
    def active(): return all(a for a in stack)
    for line in text.split("\n"):
        s = line.strip()
        m = re.match(r"#@if (\w+)$", s)
        if m: stack.append(m.group(1) == flavor); continue
        if s == "#@else":
            stack[-1] = not stack[-1]; continue
        if s == "#@endif": stack.pop(); continue
        if active(): out.append(line)
    assert not stack
    return "\n".join(out)
for fl, d in flavors.items():
    t = process(tmpl, fl)
    for k, v in {**d, "VERSION": VERSION}.items():
        t = t.replace(f"@@{k}@@", v)
    assert "@@" not in t, re.findall(r"@@\w+@@", t)
    p = here.parent / d["FILENAME"]; p.write_text(t); p.chmod(0o755)
    print("built", p.name, len(t.splitlines()), "lines")
