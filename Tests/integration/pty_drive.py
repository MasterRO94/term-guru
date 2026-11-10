import os, pty, sys, time, select, re

shell, script, workdir = sys.argv[1], sys.argv[2], sys.argv[3]
pid, fd = pty.fork()
if pid == 0:
    os.chdir(workdir)
    env = dict(os.environ, TERM="xterm-256color", PS1="P> ")
    if shell.endswith("zsh"):
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

drain(0.8)
send(f"source '{script}'\r", 0.8)
send("PS1='P> '\r", 0.5)
for step in sys.argv[4:]:
    step = step.encode().decode("unicode_escape")
    for ch in step:
        send(ch, 0.25)
# Ask the shell itself what the line looks like, instead of parsing terminal escapes.
send("\x01echo \x27[\x05]\x27 # ", 0.3)
out = send("\r", 0.8)
text = re.sub(rb"\x1b\[[0-9;?]*[a-zA-Z]|\x1b[=>]|\r", b"", out).decode(errors="replace")
lines = [l for l in text.splitlines() if l.strip().startswith("[")]
print(lines[-1] if lines else repr(text))
os.write(fd, b"exit\r")
