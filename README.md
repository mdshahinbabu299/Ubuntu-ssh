# Railway Ubuntu 24.04 SSH Dev Box

Ubuntu 24.04 container with OpenSSH, Python 3, Go, Node.js, git, build tools.
Made for Railway (TCP Proxy), SSH key login by default.

## Files
- `Dockerfile` – image
- `entrypoint.sh` – creates the user, installs key/password, persists host key, starts sshd
- `sshd_hardening.conf` – root login off, max 3 tries, no X11
- `railway.toml` – Railway build/restart settings

## 1. Make an SSH key (on your phone / Termux)
```
ssh-keygen -t ed25519 -f ~/.ssh/railway_dev
cat ~/.ssh/railway_dev.pub
```
Copy the `.pub` line. Never share `railway_dev` (private key).

## 2. Push to GitHub
```
git init && git add . && git commit -m "ssh dev box"
git branch -M main
git remote add origin https://github.com/<you>/railway-ubuntu-dev.git
git push -u origin main
```

## 3. Railway
1. New Project -> Deploy from GitHub repo -> select this repo.
2. Variables:
   - `SSH_USERNAME` = `shahin` (any lowercase name, not root)
   - `AUTHORIZED_KEYS` = your public key line (password login is then fully disabled)
   - Password only (not recommended): skip AUTHORIZED_KEYS, set `SSH_PASSWORD` (min 12 chars, long random)
3. Settings -> Volumes -> add a volume, mount path `/home`
   (keeps your files AND the host key across redeploys).
4. Settings -> Networking -> TCP Proxy -> port `22` -> Add Proxy.
5. Redeploy. Railway shows a domain and port, e.g. `xxx.proxy.rlwy.net:30899`.

## 4. Connect
```
ssh -i ~/.ssh/railway_dev shahin@xxx.proxy.rlwy.net -p 30899
```
In the Shell app: Type SSH, Host = the domain, Port = the Railway port (not 22),
User = SSH_USERNAME, then add the private key (or password).
Before pinning, compare the fingerprint in the Railway deploy logs
(`host key fingerprint`) with what the app shows, then tap Verify & Pin Host Key.

## Notes
- Anything outside `/home` is lost on redeploy (installed packages too). Add them to the Dockerfile.
- `SUDO_NOPASSWD=false` makes sudo ask for a password (password mode only).
- Railway env vars are not visible inside SSH sessions.
- Billing is by usage while the service runs; stop the service when not needed.
