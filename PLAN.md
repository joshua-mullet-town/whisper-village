# Whisper Village Plan - What We're Doing

**Purpose:** Active work queue and future plans. Current task always at top. When completed, scoop off top and consolidate into STATE.md.

---

## CURRENT: Mobile Live Coding Platform - Full Vision

**The Complete Workflow:**
GitHub Issue → Automated Droplet → Branch + Dev Server → Mobile Interface → Ship PR

**What We've Proven (2026-01-25):**
✅ **Test 2**: Remote preview hot reload works beautifully - mullet-town loaded perfectly on phone
✅ **Test 3**: Toggle UI works smoothly - instant switching between preview and terminal
✅ **Infrastructure**: Light resource usage (~500MB total for dev server + Claude)

**The Full Vision:**
From your phone, you should be able to:
1. Browse GitHub issues from your connected repos
2. Select an issue
3. System automatically:
   - Spins up DigitalOcean droplet ($6-12/mo)
   - Clones repo and creates branch from main
   - Installs dependencies
   - Starts dev server (Next.js/Vite)
   - Launches Claude Code terminal
   - Exposes everything via public URL
4. Your phone opens the mobile interface (toggle between preview/terminal)
5. You build the feature from anywhere
6. System creates PR when done
7. Droplet destroys itself (no lingering costs)

---

## Architecture: GitHub → Droplet → Mobile

### Part 1: GitHub Integration (Web Dashboard)
**Frontend:** Simple web app (Next.js/React)

```
┌─────────────────────────────────────┐
│  Mobile Browser                     │
│  https://code.your-domain.com       │
│                                     │
│  📱 Your Repositories               │
│  ✓ whisper-village    [12 issues]  │
│  ✓ mullet-town        [5 issues]   │
│  ✓ GiveGrove          [8 issues]   │
│                                     │
│  👆 Tap repo → see issues           │
│  👆 Tap issue → "Start Coding"      │
└─────────────────────────────────────┘
```

**Backend API:**
- `GET /api/repos` - List user's GitHub repos (via OAuth)
- `GET /api/repos/:owner/:repo/issues` - List issues
- `POST /api/start-session` - Spin up droplet for an issue

### Part 2: Droplet Provisioning (Agent Billy Pattern)
**When user clicks "Start Coding" on issue #42:**

```bash
# Backend provisions DigitalOcean droplet
doctl compute droplet create issue-42-whisper-village \
  --size s-2vcpu-2gb \  # $12/mo (only pay while active)
  --image ubuntu-22-04-x64 \
  --region nyc1 \
  --user-data cloud-init.yml

# cloud-init.yml does:
# 1. Install Node.js, git, Claude CLI
# 2. Clone repo: git clone https://github.com/you/whisper-village
# 3. Create branch: git checkout -b issue-42
# 4. Install deps: npm install
# 5. Start dev server: npm run dev -- --host 0.0.0.0
# 6. Start Claude Code terminal server (holler-next or similar)
# 7. Register public URLs (ngrok/Tailscale or DO networking)
```

**Provisioning takes ~2-3 minutes**, then:
- Preview URL: `http://issue-42.code.your-domain.com:3000`
- Terminal URL: `http://issue-42.code.your-domain.com:8080`

### Part 3: Mobile Interface (Proven!)
**The toggle.html pattern but production-ready:**

```
┌─────────────────────────────────────┐
│  Phone Browser                      │
│  https://issue-42.code.your-domain  │
│                                     │
│  State 1: Live Preview              │
│  ┌───────────────────────────────┐  │
│  │                               │  │
│  │   Whisper Village running     │  │
│  │   (Hot reload enabled)        │  │
│  │                               │  │
│  │                    [💬]       │  │
│  └───────────────────────────────┘  │
│                                     │
│  Tap 💬 →                           │
│                                     │
│  State 2: Claude Code Terminal      │
│  ┌───────────────────────────────┐  │
│  │ $ claude                      │  │
│  │ > Add pause button to notch   │  │
│  │ ✓ Edited NotchRecorderPanel   │  │
│  │                               │  │
│  │                    [🌐]       │  │
│  └───────────────────────────────┘  │
└─────────────────────────────────────┘
```

**Features:**
- Full-screen toggle (no split-screen)
- Both iframes pre-loaded (instant switching)
- Works on any device with browser
- Voice input via Whisper Village integration

### Part 4: Completion & Cleanup
**When done coding:**

User says: "Create PR" (or clicks button)

```bash
# Claude Code or backend script:
git add .
git commit -m "Fix: Add pause button to notch recorder (#42)"
git push origin issue-42
gh pr create --title "Fix: Add pause button" --body "Closes #42"

# Backend API:
POST /api/destroy-session
# → Destroys droplet
# → Stops billing
# → Cleans up DNS records
```

**Result:** PR is ready for review, no lingering infrastructure costs.

---

## Implementation Phases

### Phase 1: ✅ PROVEN (Completed 2026-01-25)

**What we validated:**
- ✅ Remote preview hot reload works (tested with mullet-town)
- ✅ Toggle UI is smooth and instant
- ✅ Infrastructure is light (~500MB RAM total)
- ✅ Concept is viable for mobile development

### Phase 2: GitHub Integration Dashboard (Next Up)
**Goal:** Web app to browse repos and issues

**Components needed:**
- [ ] Next.js frontend (mobile-optimized)
- [ ] GitHub OAuth integration
- [ ] API routes for repos/issues
- [ ] "Start Coding" button that kicks off provisioning

**Timeline:** ~1-2 days of focused work

### Phase 3: Droplet Provisioning Pipeline
**Goal:** Automate the Agent Billy workflow for any issue

**Components needed:**
- [ ] DigitalOcean API integration
- [ ] cloud-init template for environment setup
- [ ] DNS/URL management (ngrok, Tailscale, or DO networking)
- [ ] Status polling (wait for droplet ready)

**This is basically Agent Billy, but triggered from web UI instead of GitHub webhook**

**Timeline:** ~2-3 days (can reuse Agent Billy code)

### Phase 4: Production Mobile Interface
**Goal:** Replace toggle.html with production app

**Components needed:**
- [ ] React/Next.js app with toggle UI
- [ ] WebSocket connection to terminal backend
- [ ] Terminal emulation (holler-next or node-pty based)
- [ ] Session state management
- [ ] Voice input integration (optional but cool)

**Timeline:** ~2-3 days

### Phase 5: Completion & Cleanup Automation
**Goal:** PR creation and droplet destruction

**Components needed:**
- [ ] PR creation via GitHub API or gh CLI
- [ ] Droplet destruction on completion
- [ ] Cost tracking dashboard
- [ ] Session timeout (auto-destroy after X hours)

**Timeline:** ~1 day

---

## Total Timeline: ~1-2 weeks of focused work

**Key insight:** Most pieces already exist in Agent Billy and holler-next. This is integration work, not building from scratch.

---

## Tech Stack

**Frontend:**
- Next.js (mobile-optimized)
- React for UI components
- WebSocket for real-time terminal
- Tailwind CSS for styling

**Backend:**
- Node.js/Express or Next.js API routes
- GitHub API (Octokit)
- DigitalOcean API
- SQLite for session tracking

**Infrastructure:**
- DigitalOcean droplets (on-demand, short-lived)
- DNS management (Cloudflare or DO)
- ngrok/Tailscale for quick public URLs (or DO reserved IPs)

**Terminal:**
- node-pty for terminal emulation
- xterm.js for frontend rendering
- WebSocket for real-time communication

---

## Open Questions

### 1. URL Management
**Options:**
- **ngrok**: Easy, works immediately, free tier limits
- **Tailscale**: Secure, requires user to have Tailscale
- **DO Reserved IPs**: $4/mo per droplet but professional
- **Cloudflare Tunnel**: Free, good option

**Recommendation:** Start with ngrok for POC, move to Cloudflare Tunnel for production

### 2. Authentication
**Who can use this?**
- Just you (simplest - hardcode your GitHub token)
- Multi-user (need proper OAuth, user accounts, billing)

**Recommendation:** Start single-user (you), add multi-user later if desired

### 3. Cost Management
**DigitalOcean costs:**
- $12/mo per droplet while active
- If you work on 3 issues concurrently for 4 hours = $12 * 3 * (4/730) = $0.20
- Very cheap for on-demand usage

**Recommendation:** Add session timeout (auto-destroy after 4 hours of inactivity)

### 4. Terminal Interface
**Options:**
- **holler-next**: Full-featured, complex, voice-enabled, Jarvis mode
- **claude-code-webui**: Lightweight, simple, works
- **Custom build**: Minimal, exactly what we need

**Recommendation:** Start with claude-code-webui (simpler), add holler-next features later if needed

---

## BACKLOG: Original POC Tests (Partially Completed)

### Test 1: Remote Claude Code Speed ⏱️
**Question:** Is Claude Code fast enough when hosted remotely?

**Steps:**
1. Start claude-code-webui on Mac exposed to network:
   ```bash
   cd ~/code/holler/claude-code-webui
   npx claude-code-webui --host 0.0.0.0 --port 8080
   ```

2. Access from phone (same WiFi):
   ```
   http://<mac-ip>:8080
   ```

3. Send test prompt: "Add a console.log to a file"

4. Measure: Prompt → response time

**Success criteria:** Response in < 5 seconds feels usable

**Status:** [ ] Not tested yet

---

### Test 2: Remote Preview Hot Reload 🔥
**Question:** Can you view Vite dev server from phone and see hot reloads?

**Steps:**
1. Start Vite project exposed to network:
   ```bash
   cd ~/code/[some-vite-project]
   npm run dev -- --host 0.0.0.0
   ```

2. Open preview on phone:
   ```
   http://<mac-ip>:5173
   ```

3. In claude-code-webui (from phone), send:
   ```
   "Change the background color to blue"
   ```

4. Watch if hot reload happens on phone preview

**Success criteria:** Hot reload visible on phone within 2 seconds

**Status:** [ ] Not tested yet

---

### Test 3: Build Simple Toggle UI 🎨
**Question:** Does full-screen toggle between preview/terminal feel good?

**Steps:**
1. Create minimal HTML proof of concept (toggle.html):
   ```html
   <!DOCTYPE html>
   <html>
   <body style="margin:0;padding:0;overflow:hidden">
     <iframe id="preview" src="http://<mac-ip>:5173"
             style="width:100vw;height:100vh;border:none"></iframe>
     <iframe id="terminal" src="http://<mac-ip>:8080"
             style="display:none;width:100vw;height:100vh;border:none"></iframe>

     <button onclick="toggle()"
             style="position:fixed;bottom:20px;right:20px;width:60px;height:60px;
                    border-radius:50%;font-size:30px;border:none;background:#007AFF;
                    color:white;box-shadow:0 4px 12px rgba(0,0,0,0.3);cursor:pointer">
       💬
     </button>

     <script>
       let showingPreview = true;
       const btn = document.querySelector('button');

       function toggle() {
         const preview = document.getElementById('preview');
         const terminal = document.getElementById('terminal');

         if (showingPreview) {
           preview.style.display = 'none';
           terminal.style.display = 'block';
           btn.textContent = '🌐';
         } else {
           preview.style.display = 'block';
           terminal.style.display = 'none';
           btn.textContent = '💬';
         }

         showingPreview = !showingPreview;
       }
     </script>
   </body>
   </html>
   ```

2. Serve toggle.html (simple python server):
   ```bash
   cd ~/Desktop  # or wherever you save toggle.html
   python3 -m http.server 9000
   ```

3. Open on phone:
   ```
   http://<mac-ip>:9000/toggle.html
   ```

4. Test toggle experience - does it feel fast and smooth?

**Success criteria:** Toggle is instant, no lag, feels native

**Status:** [ ] Not tested yet

---

### Test 4: Infrastructure Requirements 💰
**Question:** What resources does this actually need?

**Steps:**
1. While running both servers, check resource usage:
   ```bash
   # Check RAM usage
   top -l 1 | grep -E "PhysMem|node|vite"

   # Expected:
   # - Vite dev server: ~100-200MB RAM
   # - claude-code-webui: ~50MB RAM
   # - Claude CLI (when active): ~500MB RAM
   ```

2. Test sustained usage:
   - Send 10 prompts to Claude
   - Make 10 edits
   - Watch RAM/CPU usage
   - Does your Mac stay responsive?

**Success criteria:**
- Total < 1GB RAM when active
- Mac stays responsive
- No thermal throttling

**Status:** [ ] Not tested yet

---

**Next Steps After Tests:**
If all 4 tests pass:
1. Build production toggle UI (React/Next.js)
2. Add GitHub integration
3. Deploy to cheap VPS ($6-12/mo)
4. Test from anywhere (not just WiFi)

If any test fails:
- Identify bottleneck
- Find alternative approach
- Re-test before building more

---

## BACKLOG: Spec Browser HUD (`/hud spec`)

**Goal:** Terminal-based navigator for spec-driven projects. Replaces PLAN.md + STATE.md with a visual interface for browsing spec files.

**Tech Stack:**
- **Ink** (React for terminal) - component-based TUI
- Global Claude Code command: `/hud spec`

---

## BACKLOG: Send to Terminal Mode

**Goal:** New mode that sends transcribed text directly to the last-focused terminal window.

**Why:**
- Developers live in the terminal (Claude Code, vim, git, npm, docker)
- Currently have to transcribe → copy → switch to terminal → paste
- This makes voice → CLI a single action

**Implementation Ideas:**
- Track last-focused terminal app (iTerm2, Terminal.app, etc.)
- New hotkey or mode toggle for "Send to Terminal"
- Possibly integrate with Command Mode for voice-driven CLI

**Status:** Attempted but blocked - couldn't get reliable terminal focus/send working. Revisit later.

---

## BACKLOG: Command Mode Phase 2 (Future)

**Ideas explored but deferred:**
- Slack navigation (requires OAuth token per workspace - too complex for now)
- Text commands ("type hello world")
- Complex commands ("open terminal and run npm start")
- Custom user-defined commands

---

## BACKLOG: Bug - Mic Permanently Stolen from Other Apps

**Problem:** When Whisper Village activates, it permanently kills audio input for other apps (e.g., Teams).

**Fix Applied (testing needed):**
Added `audioEngine = nil` and `inputNode = nil` in `StreamingRecorder.stopRecording()` to fully release mic.

---

## FUTURE: Voice-Activated Start

**Goal:** Start transcription with voice alone (no hotkey needed).

---

## FUTURE: Automated Transcription Testing Framework

**Goal:** Automated accuracy testing with TTS-generated audio to identify weaknesses and track improvements.
