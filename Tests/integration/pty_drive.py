import os, pty, sys, time, select, re

shell, script, workdir = sys.argv[1], sys.argv[2], sys.argv[3]
is_zsh = shell.endswith("zsh")
vi = os.environ.get("GURU_VI") == "1"
# Shell code to run before the hook loads, as an rc file would.
pre = os.environ.get("GURU_PRE", "")
# A shell expression printed in front of the line, e.g. $KEYTIMEOUT.
show = os.environ.get("GURU_SHOW", "")

pid, fd = pty.fork()
if pid == 0:
    os.chdir(workdir)
    env = dict(os.environ, TERM="xterm-256color", PS1="P> ")
    if is_zsh:
        os.execve(shell, [shell, "-f", "-i"], env)
    os.execve(shell, [shell, "--norc", "--noprofile", "-i"], env)

def drain(t=0.4):
    out = b""
    end = time.time() + t
    while time.time() < end:
        r, _, _ = select.select([fd], [], [], 0.05)
        if r:
            try: out += os.read(fd, 65536)
            except OSError: break
    return out

def send(s, t=0.4):
    os.write(fd, s.encode())
    return drain(t)

def type_keys(text):
    for ch in text:
        # A lone Esc must outlast KEYTIMEOUT / keyseq-timeout, or it joins the next key.
        send(ch, 0.6 if ch == "\x1b" else 0.25)

drain(0.8)
if vi:
    send(("bindkey -v" if is_zsh else "set -o vi") + "\r", 0.5)
if pre:
    send(pre + "\r", 0.5)
send(f"source '{script}'\r", 0.8)
send("PS1='P> '\r", 0.5)
for step in sys.argv[4:]:
    step = step.encode().decode("unicode_escape")
    # Escape sequences (arrows, Alt-b) arrive in one read, as from a real terminal.
    if step.startswith("\x1b") and len(step) > 1:
        send(step, 0.4)
    else:
        type_keys(step)
# Ask the shell itself what the line looks like, instead of parsing terminal escapes.
prefix = f'"[{show}]" ' if show else ""
wrap = f"\x1b0iecho {prefix}'[\x1bA]' # " if vi else f"\x01echo {prefix}'[\x05]' # "
for i, chunk in enumerate(wrap.split("\x1b")):
    if i: send("\x1b", 0.6)
    send(chunk, 0.3)
out = send("\r", 0.8)
text = re.sub(rb"\x1b\[[0-9;?]*[a-zA-Z]|\x1b[=>]|\r", b"", out).decode(errors="replace")
lines = [l for l in text.splitlines() if l.strip().startswith("[")]
print(lines[-1] if lines else repr(text))
os.write(fd, b"exit\r")
