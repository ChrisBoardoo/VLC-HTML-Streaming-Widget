-- MusicWidget.lua
-- VLC Lua Extension — Now Playing HTML Widget with spinning vinyl
--
-- Copyright (C) 2026 CrossWax
-- Licensed under the GNU General Public License v2 (GPL-2.0)
-- See https://www.gnu.org/licenses/gpl-2.0.html
--
-- INSTALL:  Copy this file to  %APPDATA%\vlc\lua\extensions\MusicWidget.lua
-- ENABLE:   VLC → View → Music Widget
-- OUTPUT:   %APPDATA%\vlc\MusicWidget\
--             widget.html    ← Browser Source in OBS (400 × 120 px)
--             nowplaying.js  ← track data  (window.NP global)
--             config.js      ← colours     (window.NPC global)
--             artwork.jpg    ← album art copied from VLC cache
--             background.png ← optional: drop your own 400×120 image here
--
-- DATA NOTE:
--   XHR/fetch from file:// is blocked by all browsers.
--   We use <script> tag injection instead — works everywhere, no server needed.

-- ─────────────────────────────────────────────────────────────────────────────
-- HTML template
-- ─────────────────────────────────────────────────────────────────────────────

local HTML = [==[<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>Music Widget</title>
<style>
@import url('https://fonts.googleapis.com/css2?family=Inter:wght@400;600;700&display=swap');
*{margin:0;padding:0;box-sizing:border-box}
html,body{width:400px;height:120px;overflow:hidden;background:transparent}
body{font-family:'Inter','Segoe UI',Arial,sans-serif}

#bg{
  position:absolute;inset:0;
  background:#1a1a2e;
  background-size:cover;background-position:center;
  z-index:0
}
#overlay{position:absolute;inset:0;pointer-events:none;z-index:1}

.w{
  position:relative;display:flex;align-items:center;
  width:400px;height:120px;
  padding:14px 18px 14px 16px;
  z-index:2;overflow:hidden
}

/* ══════════════════════════════════════
   VINYL DISC — artwork fills the whole disc, groove texture on top
   ══════════════════════════════════════ */
.vinyl-wrap{flex-shrink:0;width:92px;height:92px}

.vinyl{
  width:92px;height:92px;
  border-radius:50%;
  position:relative;
  overflow:hidden;              /* clips all children to the circle */
  background:#111;              /* fallback colour behind artwork */
  box-shadow:
    inset 0 0 0 1px rgba(255,255,255,.06),
    0 6px 28px rgba(0,0,0,.8);

  /* 33 RPM = 60 ÷ 33 ≈ 1.82 s per revolution */
  animation:vspin 1.82s linear infinite;
  animation-play-state:paused;
  will-change:transform;
  -webkit-backface-visibility:hidden;
  backface-visibility:hidden
}
.vinyl.spinning{animation-play-state:running !important}
@keyframes vspin{to{transform:rotate(360deg)}}

/* ── Layer 1: artwork fills entire disc ── */
#art{
  position:absolute;inset:0;
  width:100%;height:100%;
  object-fit:cover;
  display:none
}

/* ── Layer 1 alt: placeholder when no artwork ── */
#ph{
  position:absolute;inset:0;
  display:flex;align-items:center;justify-content:center;
  background:
    radial-gradient(circle at center, rgba(0,0,0,.55) 0%, transparent 38%),
    repeating-radial-gradient(circle at center,
      #191919 0px, #282828 1px, #1c1c1c 2px, #252525 3.5px, #191919 5px)
}
#ph svg{width:28px;height:28px;fill:rgba(255,255,255,.22);position:relative;z-index:1}

/* ── Layer 2: vinyl groove texture overlaid on the artwork ── */
.vgrooves{
  position:absolute;inset:0;
  background:
    /* dark centre (spindle area) */
    radial-gradient(circle at center, rgba(0,0,0,.55) 0%, transparent 10%),
    /* outer edge shadow */
    radial-gradient(circle at center, transparent 78%, rgba(0,0,0,.55) 100%),
    /* groove rings */
    repeating-radial-gradient(circle at center,
      transparent       0px,
      rgba(0,0,0,.25)   1px,
      transparent       2px,
      rgba(0,0,0,.18)   3.5px,
      transparent       5px);
  pointer-events:none;z-index:2
}

/* ── Layer 3: specular highlight ── */
.vsheen{
  position:absolute;inset:0;
  background:radial-gradient(ellipse at 38% 28%,rgba(255,255,255,.10) 0%,transparent 55%);
  pointer-events:none;z-index:3
}

/* ── Layer 4: spindle hole ── */
.vhole{
  position:absolute;top:50%;left:50%;
  transform:translate(-50%,-50%);
  width:6px;height:6px;
  border-radius:50%;
  background:#060606;
  z-index:4;
  box-shadow:0 0 0 1px rgba(255,255,255,.18)
}

/* ── Track info ── */
.info{flex:1;padding-left:16px;overflow:hidden}
.ttl{
  font-size:15px;font-weight:700;
  white-space:nowrap;overflow:hidden;
  line-height:1.25;color:#fff;
  text-shadow:0 1px 6px rgba(0,0,0,.6)
}
.aname{
  font-size:13px;font-weight:600;
  white-space:nowrap;overflow:hidden;
  margin-top:5px;color:#1DB954;
  text-shadow:0 1px 5px rgba(0,0,0,.5)
}
.alb{
  font-size:11px;font-weight:400;
  white-space:nowrap;overflow:hidden;
  margin-top:3px;opacity:.60;color:#fff
}

/* ── Bottom playing bar ── */
#bar{
  position:absolute;bottom:0;left:0;right:0;height:3px;
  background:#1DB954;
  transform-origin:left;transform:scaleX(0);
  transition:transform .45s cubic-bezier(.4,0,.2,1);
  z-index:5
}
#bar.on{transform:scaleX(1)}

/* ── Marquee for long text ── */
@keyframes marquee{0%,12%{transform:translateX(0)}80%,100%{transform:translateX(var(--x,0px))}}
.scroll{animation:marquee 9s ease-in-out infinite}
</style>
</head>
<body>
<div id="bg"></div>
<div id="overlay"></div>

<div class="w">
  <div class="vinyl-wrap">
    <div class="vinyl" id="vinyl">
      <!-- Layer 1: artwork (or placeholder) fills the whole disc -->
      <img id="art" src="" alt="">
      <div id="ph">
        <svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
          <path d="M12 3v10.55c-.59-.34-1.27-.55-2-.55-2.21 0-4
                   1.79-4 4s1.79 4 4 4 4-1.79 4-4V7h4V3h-6z"/>
        </svg>
      </div>
      <!-- Layers 2-4: groove texture, sheen, spindle hole — all rotate with disc -->
      <div class="vgrooves"></div>
      <div class="vsheen"></div>
      <div class="vhole"></div>
    </div>
  </div>

  <div class="info">
    <div class="ttl"   id="ttl">—</div>
    <div class="aname" id="aname"></div>
    <div class="alb"   id="alb"></div>
  </div>
</div>

<div id="bar"></div>

<script>
var lastTs = 0, lastStatus = '', artRetryTimer = null;

/*
 * injectScript — <script src> injection works on file:// in all browsers.
 * XHR/fetch from file:// is blocked by Chrome, Edge, Firefox — we never use it.
 */
function injectScript(name, cb) {
  var prev = document.getElementById('_s_' + name);
  if (prev && prev.parentNode) prev.parentNode.removeChild(prev);
  var el = document.createElement('script');
  el.id  = '_s_' + name;
  el.src = name + '?' + Date.now();
  el.onload  = cb || function(){};
  el.onerror = function(){};
  document.head.appendChild(el);
}

/* Colour config + background.png probe */
function applyConfig(c) {
  if (!c) return;
  var bar = document.getElementById('bar');
  var ttl = document.getElementById('ttl');
  var bg  = document.getElementById('bg');
  if (c.accent) { bar.style.background = c.accent; document.getElementById('aname').style.color = c.accent; }
  if (c.text)   { ttl.style.color = c.text; }
  /* Probe for background.png. Image() logs ERR_FILE_NOT_FOUND to the browser
     console when the file is absent — this is expected and harmless. fetch() from
     file:// is blocked by Chrome so it cannot be used as a silent alternative. */
  var probe = new Image();
  probe.onload = function() {
    bg.style.backgroundImage = "url('background.png?" + Date.now() + "')";
    document.getElementById('overlay').style.background = 'rgba(0,0,0,.38)';
  };
  probe.onerror = function() {
    bg.style.backgroundImage  = '';
    bg.style.backgroundColor = c.bg || '#1a1a2e';
    document.getElementById('overlay').style.background = '';
  };
  probe.src = 'background.png?' + Date.now();
}

function tryMarquee(el) {
  el.classList.remove('scroll');
  void el.offsetWidth;
  var ov = el.scrollWidth - el.clientWidth;
  if (ov > 6) { el.style.setProperty('--x', '-' + ov + 'px'); el.classList.add('scroll'); }
}

/*
 * loadArtwork — queue-based multi-source loader with retry.
 *   Tries each non-empty source in order; moves to the next on error.
 *   When all sources are exhausted, shows the placeholder and retries after 2 s.
 *
 * Both sources MUST include a cache-busting query string (e.g. ?_=<ts>) so that
 * the browser reloads the file even when the URL path is identical between tracks
 * (e.g. same album's cover.jpg, or VLC cache entry reused across tracks).
 */
function loadArtwork(primary, fallback) {
  var art = document.getElementById('art');
  var ph  = document.getElementById('ph');
  if (artRetryTimer) { clearTimeout(artRetryTimer); artRetryTimer = null; }

  /* Build ordered source list, skip empty strings */
  var queue = [primary, fallback].filter(function(s) { return s && s !== ''; });
  var idx = 0;

  function tryNext() {
    if (idx >= queue.length) {
      /* All sources failed — show placeholder and retry */
      art.style.display = 'none';
      ph.style.display  = 'flex';
      artRetryTimer = setTimeout(function() {
        if (lastStatus !== 'stopped') { idx = 0; tryNext(); }
      }, 2000);
      return;
    }
    var src = queue[idx++];
    art.onload = function() {
      art.style.display = 'block';
      ph.style.display  = 'none';
      if (artRetryTimer) { clearTimeout(artRetryTimer); artRetryTimer = null; }
      console.log('[MusicWidget] art loaded: ' + src);
    };
    art.onerror = function() { tryNext(); };
    art.src = src;
  }

  tryNext();
}

function applyTrack(d) {
  if (!d) return;
  var status = d.status || 'stopped';
  console.log('[MusicWidget] status=' + status + ' artpath=' + (d.artpath||'') + ' ts=' + d.ts);
  if (status === lastStatus && d.ts === lastTs) return;

  var vinyl = document.getElementById('vinyl');
  var bar   = document.getElementById('bar');
  var ttl   = document.getElementById('ttl');
  var aname = document.getElementById('aname');
  var alb   = document.getElementById('alb');
  var art   = document.getElementById('art');
  var ph    = document.getElementById('ph');

  if (status === 'playing') {
    vinyl.classList.add('spinning');
    bar.classList.add('on');
  } else {
    vinyl.classList.remove('spinning');
    bar.classList.remove('on');
  }

  if (d.ts !== lastTs) {
    lastTs = d.ts;
    if (status === 'stopped') {
      ttl.textContent = '—'; aname.textContent = ''; alb.textContent = '';
      if (artRetryTimer) { clearTimeout(artRetryTimer); artRetryTimer = null; }
      art.style.display = 'none'; ph.style.display = 'flex';
    } else {
      ttl.textContent   = d.title  || '—';
      aname.textContent = d.artist || '';
      alb.textContent   = d.album  || '';
      /* Both sources get ?_=ts so the browser always reloads on track change,
         even when the file path is identical (same album, same VLC cache entry). */
      var ts = d.ts;
      var primary  = d.artpath ? d.artpath + '?_=' + ts : '';
      var fallback = 'artwork.jpg?' + ts;
      loadArtwork(primary, fallback);
      setTimeout(function() { tryMarquee(ttl); tryMarquee(aname); tryMarquee(alb); }, 150);
    }
  }

  lastStatus = status;
}

injectScript('config.js', function() { if (window.NPC) applyConfig(window.NPC); });
function poll() { injectScript('nowplaying.js', function() { if (window.NP) applyTrack(window.NP); }); }
poll();
setInterval(poll, 1000);
</script>
</body>
</html>
]==]

-- ─────────────────────────────────────────────────────────────────────────────
-- Extension state
-- ─────────────────────────────────────────────────────────────────────────────

local VERSION = "1.6.4"

local dlg        = nil
local lbl_status = nil
local inp_bg     = nil
local inp_accent = nil
local inp_text   = nil

local out_dir = ""

-- State tracked by hooks — vlc.playlist.status() is unreliable in extensions.
local play_state = "stopped"

-- Monotonic write counter used as the "ts" field in nowplaying.js.
-- os.time() has 1-second resolution; input_changed and meta_changed both fire
-- within the same second on a track change, producing identical os.time() values.
-- The JS's `d.ts === lastTs` check would then silently drop the second write
-- (which is usually the one with the correct artpath). A counter guarantees every
-- write produces a unique ts regardless of wall-clock resolution.
local write_seq = 0

-- Tracks the last URI for which we attempted direct embedded-art extraction.
-- Prevents re-reading the media file on every meta_changed for the same track.
local art_extracted_uri = ""

local cfg = {
    bg_color     = "#1a1a2e",
    accent_color = "#1DB954",
    text_color   = "#ffffff",
}

-- ─────────────────────────────────────────────────────────────────────────────
-- VLC extension hooks
-- ─────────────────────────────────────────────────────────────────────────────

function descriptor()
    return {
        title        = "Music HTML Widget by CrossWax",
        version      = VERSION,
        author       = "CrossWax",
        shortdesc    = "Now Playing HTML Widget (by CrossWax)",
        description  = "Outputs a 400x120 px HTML widget with spinning vinyl effect.\n"
                    .. "Use as Browser Source in OBS for streaming overlays.\n"
                    .. "Output: %APPDATA%\\vlc\\MusicWidget\\widget.html\n"
                    .. "Copyright (C) 2026 CrossWax — GPL-2.0",
        capabilities = { "input-listener", "meta-listener", "playing-listener" },
    }
end

function activate()
    local appdata = os.getenv("APPDATA") or "."
    out_dir = appdata .. "\\vlc\\MusicWidget\\"
    os.execute('mkdir "' .. out_dir .. '" 2>nul')

    write_widget_html()
    write_config_js()
    write_nowplaying_js(nil, "stopped")

    -- Detect initial state via VLC input object (best-effort, wrapped in pcall)
    pcall(function()
        local inp = vlc.object.input()
        if inp then
            local n = vlc.var.get(inp, "state")
            if     n == 2 then play_state = "playing"
            elseif n == 3 then play_state = "paused"
            else                play_state = "stopped"
            end
        end
    end)
    if play_state == "stopped" and vlc.input.item() then
        play_state = "playing"
    end

    create_dialog()
    do_update()
end

function deactivate() destroy_dialog() end
function close()      destroy_dialog() end

function meta_changed()
    do_update()
end

function input_changed()
    play_state = "playing"
    art_extracted_uri = ""  -- new track → re-run embedded-art extraction
    do_update()
end

function playing_changed(n)
    -- VLC input_state_e: 0=INIT  1=OPENING  2=PLAYING  3=PAUSED  4=END  5=ERROR
    if     n == 3           then play_state = "paused"
    elseif n == 1 or n == 2 then play_state = "playing"
    else                         play_state = "stopped"
    end
    do_update()
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Core update
-- ─────────────────────────────────────────────────────────────────────────────

function do_update()
    -- Wrap in pcall: any Lua error in a hook callback would otherwise propagate
    -- back into VLC's event loop and can cause instability or crashes.
    local ok, err = pcall(do_update_inner)
    if not ok then set_status("err: " .. tostring(err):sub(1, 60)) end
end

function do_update_inner()
    local item = vlc.input.item()
    if not item then
        play_state = "stopped"
        write_nowplaying_js(nil, "stopped")
        set_status("Stopped")
        return
    end

    local metas  = item:metas()
    local title  = metas["title"]  or ""
    local artist = metas["artist"] or ""
    local album  = metas["album"]  or ""
    local name   = item:name()     or ""

    if title == "" then
        local a, t = name:match("^(.-)%s+%-%s+(.+)$")
        if a and t then
            if artist == "" then artist = str_trim(a) end
            title = str_trim(t)
        else
            title = name
        end
    end

    local arturl = find_arturl(item, metas)

    local art_file = copy_artwork(arturl)

    -- "Smells Like Teen Spirit" — if VLC won't give us the art URL, we'll
    -- rip the JPEG straight out of the file ourselves.
    --
    -- Guard: art_extracted_uri is ONLY set on success. If extraction fails
    -- (file not ready when input_changed fires, file format unsupported, etc.)
    -- the URI stays unset so the NEXT meta_changed call gets another shot.
    -- Once it succeeds we stop retrying for that track.
    local embedded_ok = false
    if arturl == "" then
        local uri = ""
        pcall(function() uri = item:uri() or "" end)
        if uri ~= "" and uri ~= art_extracted_uri then
            pcall(function() embedded_ok = extract_embedded_art(uri) end)
            if embedded_ok then
                art_extracted_uri = uri   -- lock in: don't re-read this track
            end
        end
    end

    write_nowplaying_js({
        title    = title,
        artist   = artist,
        album    = album,
        art_file = art_file,
        arturl   = arturl,   -- raw VLC URL passed through for direct browser loading
    }, play_state)

    local display = (artist ~= "") and (artist .. " - " .. title) or title
    local art_hint
    if arturl ~= "" then
        art_hint = arturl:lower():sub(1,7) == "file://" and " [art\xe2\x9c\x93]"
                or (" [art:" .. arturl:sub(1,14) .. "]")
    elseif embedded_ok then
        art_hint = " [emb\xe2\x9c\x93]"   -- extracted from file directly
    elseif art_extracted_uri ~= "" then
        art_hint = " [no art]"             -- tried extraction, nothing found
    else
        art_hint = " [no art URL]"
    end
    set_status((play_state == "paused" and "|| " or "") .. display .. art_hint)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Artwork URL discovery — five methods, first non-empty wins
-- ─────────────────────────────────────────────────────────────────────────────

function find_arturl(item, metas)
    local url = ""

    -- 1. Standard API
    pcall(function() url = item:arturl() or "" end)
    if url ~= "" then return url end

    -- 2. Meta-table keys (varies by VLC version / file format)
    for _, k in ipairs({"arturl", "cover", "artwork", "art_url"}) do
        url = metas[k] or ""
        if url ~= "" then return url end
    end

    -- 3. VLC input variable (exposed differently in some builds)
    pcall(function()
        local inp = vlc.object.input()
        if inp then url = vlc.var.get(inp, "arturl") or "" end
    end)
    if url ~= "" then return url end

    -- 4. Common artwork files in the same folder as the track
    --    (cover.jpg, folder.jpg, etc. — very common in local music libraries)
    pcall(function()
        local uri = item:uri() or ""
        if uri == "" then return end
        local dir_url = uri:match("^(.*[/])")
        if not dir_url then return end
        local dir = dir_url
        if     dir:sub(1,8) == "file:///" then dir = dir:sub(9)
        elseif dir:sub(1,7) == "file://"  then dir = dir:sub(8)
        else   return
        end
        dir = dir:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)
        dir = dir:gsub("/", "\\")
        for _, name in ipairs({"cover.jpg","folder.jpg","cover.png","artwork.jpg",
                                "front.jpg","AlbumArt.jpg","thumb.jpg"}) do
            local f = io.open(dir .. name, "rb")
            if f then
                f:close()
                url = "file:///" .. (dir .. name):gsub("\\", "/")
                return
            end
        end
    end)
    if url ~= "" then return url end

    -- 5. VLC art cache lookup — two steps, no CMD window.
    pcall(function()
        local appdata = os.getenv("APPDATA") or ""
        local base    = appdata .. "\\vlc\\art\\"

        -- VLC's own sanitisation: replace Windows-illegal filename chars with _
        local function vlc_safe(s)
            return s:gsub('[\\/:*?"<>|]', '_')
        end

        local a = vlc_safe(metas["artist"] or "")
        local b = vlc_safe(metas["album"]  or "")

        -- 5a: probe known path structures directly (instant, no subprocess)
        local function try(prefix)
            for _, n in ipairs({"art","art.jpg","art.jpeg","art.png","art.gif"}) do
                local f = io.open(prefix .. n, "rb")
                if f then f:close(); url = "file:///" .. (prefix..n):gsub("\\","/"); return true end
            end
            return false
        end

        local tried = {}
        local function probe(prefix)
            if tried[prefix] then return false end
            tried[prefix] = true
            return try(prefix)
        end

        if a ~= "" and b ~= "" then
            if probe(base.."InternalBackup\\"..a.."\\"..b.."\\") then return end
            if probe(base..a.."\\"..b.."\\") then return end
        end
        if a ~= "" then
            if probe(base.."InternalBackup\\"..a.."\\") then return end
            if probe(base..a.."\\") then return end
        end
        if b ~= "" then
            if probe(base.."InternalBackup\\"..b.."\\") then return end
        end

        -- VLC art cache empty / path structure not matched.
        -- extract_embedded_art() in do_update_inner handles this case directly.
    end)

    return url
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Direct embedded-art extraction from media files
-- "I want my MTV" — but I'll settle for JPEG bytes from an ID3 tag.
--
-- VLC 3.023 doesn't write embedded art to its file cache, and item:arturl()
-- returns nil. So we read the media file ourselves — pure Lua binary I/O,
-- zero subprocesses, zero popups.
--
-- Strategy: don't parse MIME types or text encodings (fragile). Instead,
-- hunt directly for image magic bytes inside the frame data:
--   JPEG: \xFF\xD8\xFF  (bytes 255 216 255 in Lua 5.1 decimal escapes)
--   PNG:  \x89PNG       (bytes 137 80 78 71)
-- Whatever bytes precede the magic are APIC header gunk we don't care about.
-- ─────────────────────────────────────────────────────────────────────────────

-- Lua 5.1 (VLC's runtime) has no \xNN hex escapes — use decimal \NNN.
local JPEG_MAGIC = "\255\216\255"   -- FF D8 FF  — "We didn't start the fire"
local PNG_MAGIC  = "\137PNG"        -- 89 50 4E 47

-- Writes image bytes to artwork.jpg. Returns true on success.
local function write_art(img)
    if not img or #img < 128 then return false end
    local f = io.open(out_dir .. "artwork.jpg", "wb")
    if not f then return false end
    f:write(img); f:close()
    return true
end

-- Find JPEG or PNG magic inside any binary blob and return from that offset.
local function extract_image(blob)
    local j = blob:find(JPEG_MAGIC, 1, true)
    local p = blob:find(PNG_MAGIC,  1, true)
    local pos = (j and p) and math.min(j, p) or j or p
    if pos then return blob:sub(pos) end
    return nil
end

-- ── MP3 / ID3v2 ──────────────────────────────────────────────────────────────
-- "It's the end of the world as we know it (and I feel fine)" about parsing ID3.
--
-- Handles all three ID3v2 generations:
--   v2.2  — 6-byte frame headers, 3-char IDs, picture frame = "PIC"
--   v2.3  — 10-byte frame headers, 4-char IDs, picture frame = "APIC", plain sizes
--   v2.4  — 10-byte frame headers, 4-char IDs, picture frame = "APIC", syncsafe sizes
local function id3v2_extract(path)
    local f = io.open(path, "rb")
    if not f then return false end

    -- "Are you gonna go my way?" — first check the magic
    if f:read(3) ~= "ID3" then f:close(); return false end

    local hdr = f:read(7)
    if not hdr or #hdr < 7 then f:close(); return false end

    local ver    = hdr:byte(1)
    -- Syncsafe integer: each byte contributes only 7 bits
    local tag_sz = hdr:byte(4)*0x200000 + hdr:byte(5)*0x4000
                 + hdr:byte(6)*0x80     + hdr:byte(7)

    -- "Don't stop believin'" — but do stop at 50 MB
    if tag_sz < 1 or tag_sz > 50*1024*1024 then f:close(); return false end

    local data = f:read(tag_sz)
    f:close()
    if not data then return false end

    local pos = 1

    if ver == 2 then
        -- ── ID3v2.2: 6-byte headers, 3-char IDs ─────────────────────────────
        -- "Video Killed the Radio Star" — and ID3v2.2 tagged the MP3 era.
        while pos + 6 <= #data do
            if data:byte(pos) == 0 then break end
            local b1,b2,b3 = data:byte(pos+3), data:byte(pos+4), data:byte(pos+5)
            local fsz = b1*0x10000 + b2*0x100 + b3
            if fsz < 1 or pos + 6 + fsz > #data + 1 then break end
            if data:sub(pos, pos+2) == "PIC" then
                return write_art(extract_image(data:sub(pos+6, pos+5+fsz)))
            end
            pos = pos + 6 + fsz
        end
    else
        -- ── ID3v2.3 / ID3v2.4: 10-byte headers, 4-char IDs ──────────────────
        -- "Everybody wants to rule the world" — we just want the APIC frame.
        while pos + 10 <= #data do
            if data:byte(pos) == 0 then break end
            local b1,b2,b3,b4 = data:byte(pos+4), data:byte(pos+5),
                                 data:byte(pos+6), data:byte(pos+7)
            if not (b1 and b2 and b3 and b4) then break end
            -- v2.4 uses syncsafe sizes; v2.3 uses plain big-endian
            local fsz = ver >= 4
                and (b1*0x200000 + b2*0x4000 + b3*0x80 + b4)
                 or (b1*0x1000000 + b2*0x10000 + b3*0x100 + b4)
            if fsz < 1 or pos + 10 + fsz > #data + 1 then break end
            if data:sub(pos, pos+3) == "APIC" then
                return write_art(extract_image(data:sub(pos+10, pos+9+fsz)))
            end
            pos = pos + 10 + fsz
        end
    end
    return false
end

-- ── M4A / MP4 ────────────────────────────────────────────────────────────────
-- "Don't You (Forget About Me)" — iTunes users deserve artwork too.
--
-- Cover art lives at: moov → ilst → covr → data (image bytes follow).
-- iTunes puts moov AFTER the mdat audio block (end of file).
-- Other encoders put moov BEFORE mdat (start of file).
-- We read 1.5 MB from both ends to cover both layouts without loading the
-- entire (potentially 50+ MB) audio file into memory.
local function mp4_extract(path)
    local f = io.open(path, "rb")
    if not f then return false end

    -- Verify ftyp box (MP4 magic at bytes 5–8)
    local lead = f:read(8)
    if not lead or lead:sub(5,8) ~= "ftyp" then f:close(); return false end

    local CHUNK = 1536 * 1024   -- 1.5 MB per read

    -- Helper: search a chunk for "covr" and extract the image that follows
    local function scan(chunk)
        if not chunk then return false end
        local covr = chunk:find("covr", 1, true)
        if not covr then return false end
        return write_art(extract_image(chunk:sub(covr)))
    end

    -- Try start of file (moov-first layout)
    f:seek("set", 0)
    if scan(f:read(CHUNK)) then f:close(); return true end

    -- Try end of file (iTunes moov-last layout)
    local file_sz = f:seek("end", 0)
    if file_sz and file_sz > CHUNK then
        f:seek("end", -CHUNK)
        if scan(f:read(CHUNK)) then f:close(); return true end
    end

    f:close()
    return false
end

-- ── FLAC ─────────────────────────────────────────────────────────────────────
-- "I Will Always Love You" — to FLAC's lossless PICTURE block (type 6).
local function flac_extract(path)
    local f = io.open(path, "rb")
    if not f then return false end

    if f:read(4) ~= "fLaC" then f:close(); return false end

    while true do
        local hdr = f:read(4)
        if not hdr or #hdr < 4 then break end
        local b0      = hdr:byte(1)
        local is_last = math.floor(b0 / 128) == 1
        local blk_typ = b0 % 128
        local blk_sz  = hdr:byte(2)*0x10000 + hdr:byte(3)*0x100 + hdr:byte(4)

        if blk_typ == 6 then   -- PICTURE — "One is the loneliest number"
            local bd = f:read(blk_sz)
            f:close()
            if bd then
                -- Magic-byte search bypasses all the length-prefixed fields
                return write_art(extract_image(bd))
            end
            return false
        end

        f:seek("cur", blk_sz)
        if is_last then break end
    end
    f:close()
    return false
end

-- ── Entry point ───────────────────────────────────────────────────────────────
-- Called from do_update_inner when arturl == "".
-- Returns true if artwork.jpg was successfully written.
function extract_embedded_art(uri)
    local lp = uri:lower()
    local path = uri
    if     lp:sub(1,8) == "file:///" then path = path:sub(9)
    elseif lp:sub(1,7) == "file://"  then path = path:sub(8)
    else   return false
    end
    path = path:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)
    path = path:gsub("/", "\\")

    local ext = path:lower():match("%.([^%.\\]+)$") or ""
    if ext == "mp3" or ext == "mp2" or ext == "aac" then
        return id3v2_extract(path)
    elseif ext == "m4a" or ext == "mp4" then
        -- MP4 container (iTunes / Apple); falls back to ID3v2 in case it's
        -- a non-standard M4A that was tagged with ID3v2 instead
        return mp4_extract(path) or id3v2_extract(path)
    elseif ext == "flac" then
        return flac_extract(path)
    end
    return false
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Artwork — copy from VLC's file:// art cache to the widget folder
-- ─────────────────────────────────────────────────────────────────────────────

function copy_artwork(arturl)
    local default = "artwork.jpg"
    if not arturl or arturl == "" then return default end

    -- Only handle file:// URLs; other schemes (attachment://, vlc-art://, http://)
    -- require vlc.stream() which is unsafe to call from hook callbacks during
    -- playlist transitions — it can race with VLC's input pipeline and crash VLC.
    local lp = arturl:lower()
    local path = arturl
    if     lp:sub(1, 8) == "file:///" then path = path:sub(9)
    elseif lp:sub(1, 7) == "file://"  then path = path:sub(8)
    else   return default
    end

    path = path:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)
    path = path:gsub("/", "\\")

    local dst = out_dir .. "artwork.jpg"

    -- Attempt 1: pure-Lua binary copy — no shell, no VLC API, safe at any call site
    -- io.open binary copy: safe, no shell, no visible window.
    -- Shell copy fallback (os.execute) was removed — it caused a cmd.exe window
    -- to flash on every track change when called from VLC (a GUI process).
    -- Non-ASCII paths that io.open can't handle are covered by the artpath
    -- direct-load strategy in the browser, which handles Unicode natively.
    local src_f = io.open(path, "rb")
    if src_f then
        local data = src_f:read("*all")
        src_f:close()
        if data and #data > 0 then
            local dst_f = io.open(dst, "wb")
            if dst_f then dst_f:write(data); dst_f:close() end
        end
    end

    return "artwork.jpg"
end

-- ─────────────────────────────────────────────────────────────────────────────
-- File writers
-- ─────────────────────────────────────────────────────────────────────────────

local function je(s)
    if not s or s == "" then return "" end
    return (s:gsub('[\\"]', function(c) return "\\" .. c end)
              :gsub('\n', '\\n'):gsub('\r', '\\r'))
end

function write_nowplaying_js(info, status)
    status  = status or "stopped"
    write_seq = write_seq + 1          -- unique per write, not per second
    local f = io.open(out_dir .. "nowplaying.js", "w")
    if not f then return end
    if info and status ~= "stopped" then
        f:write(string.format(
            'window.NP={"status":"%s","title":"%s","artist":"%s","album":"%s","art":"%s","artpath":"%s","ts":%d};',
            status,
            je(info.title), je(info.artist), je(info.album),
            je(info.art_file), je(info.arturl or ""),
            write_seq
        ))
    else
        f:write(string.format(
            'window.NP={"status":"stopped","title":"","artist":"","album":"","art":"artwork.jpg","artpath":"","ts":%d};',
            write_seq
        ))
    end
    f:close()
end

function write_config_js()
    local f = io.open(out_dir .. "config.js", "w")
    if not f then return end
    f:write(string.format(
        'window.NPC={"bg":"%s","accent":"%s","text":"%s"};',
        je(cfg.bg_color), je(cfg.accent_color), je(cfg.text_color)
    ))
    f:close()
end

function write_widget_html()
    local f = io.open(out_dir .. "widget.html", "w")
    if not f then return end
    f:write(HTML)
    f:close()
end

-- ─────────────────────────────────────────────────────────────────────────────
-- VLC dialog
-- ─────────────────────────────────────────────────────────────────────────────

function create_dialog()
    dlg = vlc.dialog("Music Widget")
    local r = 1

    dlg:add_label("<b>Music HTML Widget</b>  v" .. VERSION .. "  -  by CrossWax",
                  1, r, 2, 1); r = r + 1
    dlg:add_label(" ", 1, r, 2, 1); r = r + 1

    dlg:add_label("<b>Status</b>", 1, r, 1, 1)
    lbl_status = dlg:add_label("Starting\xe2\x80\xa6", 2, r, 1, 1); r = r + 1
    dlg:add_label(" ", 1, r, 2, 1); r = r + 1

    dlg:add_label("<b>Widget folder</b>", 1, r, 1, 1)
    dlg:add_label(out_dir, 2, r, 1, 1); r = r + 1
    dlg:add_label("  OBS: Add widget.html as Browser Source - 400x120 px.",
                  1, r, 2, 1); r = r + 1
    dlg:add_label(" ", 1, r, 2, 1); r = r + 1

    dlg:add_label("<b>Customise</b>", 1, r, 2, 1); r = r + 1

    dlg:add_label("Background color (#rrggbb):", 1, r, 1, 1)
    inp_bg = dlg:add_text_input(cfg.bg_color, 2, r, 1, 1); r = r + 1

    dlg:add_label("Accent / artist color (#rrggbb):", 1, r, 1, 1)
    inp_accent = dlg:add_text_input(cfg.accent_color, 2, r, 1, 1); r = r + 1

    dlg:add_label("Text / title color (#rrggbb):", 1, r, 1, 1)
    inp_text = dlg:add_text_input(cfg.text_color, 2, r, 1, 1); r = r + 1

    dlg:add_label("  Or drop background.png (400x120 px) in the widget folder.",
                  1, r, 2, 1); r = r + 1
    dlg:add_label(" ", 1, r, 2, 1); r = r + 1

    dlg:add_button("Apply Colors", on_apply_colors, 1, r, 1, 1)
    dlg:add_button("Open Folder",  on_open_folder,  2, r, 1, 1); r = r + 1

    dlg:show()
end

function destroy_dialog()
    if dlg then dlg:delete(); dlg = nil end
    lbl_status = nil; inp_bg = nil; inp_accent = nil; inp_text = nil
end

function on_apply_colors()
    if inp_bg     then cfg.bg_color     = inp_bg:get_text()     end
    if inp_accent then cfg.accent_color = inp_accent:get_text() end
    if inp_text   then cfg.text_color   = inp_text:get_text()   end
    write_config_js()
    set_status("Colors saved \xe2\x80\x94 reload the page (F5) to apply.")
end

function on_open_folder()
    os.execute('explorer "' .. out_dir .. '"')
end

function set_status(msg)
    if lbl_status then lbl_status:set_text(msg) end
end

function str_trim(s)
    return s:match("^%s*(.-)%s*$")
end
