-- PlantUML Viewer: mo風サイドバー付き単一エンドポイントビューア
-- PlantumlOpen したファイルだけをビューアに登録 → SVG変換 → browser-syncで配信
-- http://localhost:3100 でサイドバー付きビューアを表示

local augroup = vim.api.nvim_create_augroup("PlantumlViewer", { clear = true })

local output_dir = nil
local server_job_id = nil
local debounce_timer = nil
local registered_files = {} -- { [absolute_path] = true }
local DEBOUNCE_MS = 1000
local SERVER_PORT = 3100

local function jar_path()
	local custom = vim.g["plantuml_previewer#plantuml_jar_path"]
	if custom then
		return custom
	end
	local base = vim.g["plantuml_previewer#viewer_path"]
	if base then
		return vim.fn.fnameescape(base) .. "/../lib/plantuml.jar"
	end
	return vim.fn["plantuml_previewer#default_viewer_path"]() .. "/../lib/plantuml.jar"
end

local function get_project_root()
	return vim.fn.getcwd()
end

local function relative_path(abs_path)
	local root = get_project_root()
	if vim.startswith(abs_path, root) then
		return abs_path:sub(#root + 2)
	end
	return vim.fn.fnamemodify(abs_path, ":.")
end

local function svg_name(puml_path)
	return relative_path(puml_path):gsub("/", "--"):gsub("%.puml$", ".svg")
end

local function write_manifest()
	if not output_dir then
		return
	end
	local entries = {}
	for abs_path, _ in pairs(registered_files) do
		local rel = relative_path(abs_path)
		table.insert(entries, string.format('    {"name": %q, "svg": %q}', rel, svg_name(abs_path)))
	end
	table.sort(entries)
	local json = string.format(
		'{\n  "files": [\n%s\n  ],\n  "updated_at": %d\n}',
		table.concat(entries, ",\n"),
		os.time()
	)
	local fh = io.open(output_dir .. "/manifest.json", "w")
	if fh then
		fh:write(json)
		fh:close()
	end
end

local function unregister_file(abs_path)
	if not registered_files[abs_path] then
		return
	end
	registered_files[abs_path] = nil
	if output_dir then
		local svg = output_dir .. "/" .. svg_name(abs_path)
		vim.fn.delete(svg)
	end
	write_manifest()
end

local function convert_file(puml_path)
	if not output_dir then
		return
	end
	local src_dir = vim.fn.fnamemodify(puml_path, ":h")
	local svg = output_dir .. "/" .. svg_name(puml_path)

	-- バッファが開いていればバッファの内容を使う（未保存の変更を反映）
	local content
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_loaded(buf) and vim.api.nvim_buf_get_name(buf) == puml_path then
			local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
			content = table.concat(lines, "\n")
			break
		end
	end

	local cmd = string.format(
		"java -Djava.awt.headless=true -DPLANTUML_LIMIT_SIZE=32768 -Dplantuml.include.path=%s -jar %s -tsvg -pipe > %s",
		vim.fn.shellescape(src_dir),
		vim.fn.shellescape(jar_path()),
		vim.fn.shellescape(svg)
	)

	if content then
		local job_id = vim.fn.jobstart({ "bash", "-c", cmd }, { stdin = "pipe" })
		if job_id > 0 then
			vim.fn.chansend(job_id, content)
			vim.fn.chanclose(job_id, "stdin")
		end
	else
		local read_cmd = string.format("cat %s | %s", vim.fn.shellescape(puml_path), cmd)
		vim.fn.jobstart({ "bash", "-c", read_cmd })
	end
end

local function register_and_convert(abs_path)
	if not output_dir then
		return
	end
	registered_files[abs_path] = true
	convert_file(abs_path)
	write_manifest()
end

-- browser-syncの設定ファイル（middleware付き）を生成
local function write_bs_config()
	if not output_dir then
		return
	end
	local config = string.format(
		[[
var fs = require('fs');
var path = require('path');
var outputDir = %q;

module.exports = {
  server: outputDir,
  files: [outputDir + '/**/*.svg', outputDir + '/manifest.json'],
  port: %d,
  open: false,
  notify: false,
  ui: false,
  middleware: [
    {
      route: '/api/delete',
      handle: function(req, res) {
        if (req.method !== 'POST') {
          res.writeHead(405);
          res.end('Method not allowed');
          return;
        }
        var body = '';
        req.on('data', function(chunk) { body += chunk; });
        req.on('end', function() {
          try {
            var data = JSON.parse(body);
            var svgFile = data.svg;
            if (!svgFile || svgFile.indexOf('..') !== -1) {
              res.writeHead(400);
              res.end('Invalid filename');
              return;
            }
            var svgPath = path.join(outputDir, svgFile);
            if (fs.existsSync(svgPath)) {
              fs.unlinkSync(svgPath);
            }
            // manifest.json から該当エントリを削除
            var manifestPath = path.join(outputDir, 'manifest.json');
            if (fs.existsSync(manifestPath)) {
              var manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
              manifest.files = manifest.files.filter(function(f) { return f.svg !== svgFile; });
              manifest.updated_at = Math.floor(Date.now() / 1000);
              fs.writeFileSync(manifestPath, JSON.stringify(manifest, null, 2));
            }
            res.writeHead(200, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify({ ok: true }));
          } catch(e) {
            res.writeHead(500);
            res.end('Error: ' + e.message);
          }
        });
      }
    }
  ]
};
]],
		output_dir,
		SERVER_PORT
	)
	local fh = io.open(output_dir .. "/bs-config.js", "w")
	if fh then
		fh:write(config)
		fh:close()
	end
end

-- Neovim側でもmanifest.jsonを監視して registered_files を同期
local function sync_registered_files_from_manifest()
	if not output_dir then
		return
	end
	local manifest_path = output_dir .. "/manifest.json"
	local fh = io.open(manifest_path, "r")
	if not fh then
		return
	end
	local content = fh:read("*a")
	fh:close()

	-- manifest.jsonに残っているファイルだけを registered_files に反映
	local new_registered = {}
	for name in content:gmatch('"name"%s*:%s*"([^"]+)"') do
		local root = get_project_root()
		local abs_path = root .. "/" .. name
		if registered_files[abs_path] then
			new_registered[abs_path] = true
		end
	end
	registered_files = new_registered
end

-- サイドバー付きHTMLビューア（削除ボタン付き）
local VIEWER_HTML = [[<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<title>PlantUML Viewer</title>
<style>
  :root {
    --sidebar-width: 250px;
    --bg: #f5f5f5;
    --sidebar-bg: #fff;
    --sidebar-border: #e0e0e0;
    --text: #333;
    --text-secondary: #888;
    --item-hover: #f0f0f0;
    --item-active: #e3f2fd;
    --item-active-border: #1976d2;
    --controls-bg: white;
    --controls-border: #ccc;
    --status-bg: #fafafa;
    --status-border: #eee;
    --delete-color: #999;
    --delete-hover: #e53935;
  }
  @media (prefers-color-scheme: dark) {
    :root {
      --bg: #1e1e1e;
      --sidebar-bg: #252526;
      --sidebar-border: #3c3c3c;
      --text: #ccc;
      --text-secondary: #888;
      --item-hover: #2a2d2e;
      --item-active: #094771;
      --item-active-border: #4fc3f7;
      --controls-bg: #333;
      --controls-border: #555;
      --status-bg: #1e1e1e;
      --status-border: #333;
      --delete-color: #666;
      --delete-hover: #ef5350;
    }
  }
  * { margin: 0; padding: 0; box-sizing: border-box; }
  html, body { width: 100%; height: 100%; overflow: hidden; background: var(--bg); color: var(--text); font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
  #app { display: flex; width: 100%; height: 100%; }

  /* Sidebar */
  #sidebar {
    width: var(--sidebar-width);
    min-width: var(--sidebar-width);
    height: 100%;
    background: var(--sidebar-bg);
    border-right: 1px solid var(--sidebar-border);
    display: flex;
    flex-direction: column;
    overflow: hidden;
  }
  #sidebar-header {
    padding: 12px 16px;
    font-size: 14px;
    font-weight: 600;
    border-bottom: 1px solid var(--sidebar-border);
  }
  #file-list {
    flex: 1;
    overflow-y: auto;
    list-style: none;
  }
  #file-list li {
    padding: 8px 12px 8px 16px;
    font-size: 13px;
    cursor: pointer;
    border-left: 3px solid transparent;
    display: flex;
    align-items: center;
    gap: 4px;
  }
  #file-list li:hover { background: var(--item-hover); }
  #file-list li.active {
    background: var(--item-active);
    border-left-color: var(--item-active-border);
  }
  #file-list li .file-name {
    flex: 1;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  #file-list li .btn-delete {
    flex-shrink: 0;
    width: 20px;
    height: 20px;
    border: none;
    background: none;
    color: var(--delete-color);
    cursor: pointer;
    font-size: 14px;
    display: flex;
    align-items: center;
    justify-content: center;
    border-radius: 3px;
    opacity: 0;
    transition: opacity 0.15s;
  }
  #file-list li:hover .btn-delete { opacity: 1; }
  #file-list li .btn-delete:hover { color: var(--delete-hover); background: rgba(229,57,53,0.1); }
  #status-bar {
    padding: 6px 16px;
    font-size: 11px;
    color: var(--text-secondary);
    border-top: 1px solid var(--status-border);
    background: var(--status-bg);
  }

  /* Main area */
  #main {
    flex: 1;
    position: relative;
    overflow: hidden;
  }
  #container {
    width: 100%;
    height: 100%;
    overflow: hidden;
    cursor: grab;
    touch-action: none;
  }
  #container.dragging { cursor: grabbing; }
  #svg-wrapper {
    transform-origin: 0 0;
    position: absolute;
    left: 0;
    top: 0;
  }
  #svg-wrapper img {
    display: block;
    max-width: none;
    max-height: none;
  }
  #controls {
    position: absolute;
    top: 10px;
    right: 10px;
    z-index: 1000;
    display: flex;
    flex-direction: column;
    gap: 4px;
  }
  #controls button {
    width: 36px;
    height: 36px;
    border: 1px solid var(--controls-border);
    background: var(--controls-bg);
    color: var(--text);
    border-radius: 4px;
    cursor: pointer;
    font-size: 18px;
    display: flex;
    align-items: center;
    justify-content: center;
  }
  #controls button:hover { opacity: 0.8; }
  #empty-state {
    display: flex;
    align-items: center;
    justify-content: center;
    height: 100%;
    color: var(--text-secondary);
    font-size: 14px;
  }
</style>
</head>
<body>
<div id="app">
  <div id="sidebar">
    <div id="sidebar-header">PlantUML Viewer</div>
    <ul id="file-list"></ul>
    <div id="status-bar">0 diagrams</div>
  </div>
  <div id="main">
    <div id="controls">
      <button id="btn-reset" title="Reset">&#8962;</button>
      <button id="btn-zoomin" title="Zoom In">+</button>
      <button id="btn-zoomout" title="Zoom Out">&minus;</button>
    </div>
    <div id="container">
      <div id="svg-wrapper">
        <img id="diagram" src="">
      </div>
    </div>
  </div>
</div>
<script>
(function() {
  var fileList = document.getElementById('file-list');
  var statusBar = document.getElementById('status-bar');
  var container = document.getElementById('container');
  var wrapper = document.getElementById('svg-wrapper');
  var img = document.getElementById('diagram');
  var currentFile = null;
  var manifest = { files: [], updated_at: 0 };

  // --- Sidebar ---
  function getStoredSelection() {
    try { return localStorage.getItem('plantuml-viewer-selected'); } catch(e) { return null; }
  }
  function setStoredSelection(name) {
    try { localStorage.setItem('plantuml-viewer-selected', name); } catch(e) {}
  }

  function selectFile(file) {
    if (!file) return;
    currentFile = file;
    setStoredSelection(file.name);
    img.src = file.svg + '?t=' + Date.now();
    renderFileList();
  }

  function deleteFile(file) {
    fetch('/api/delete', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ svg: file.svg })
    }).then(function() {
      // 削除後にmanifestを再取得
      manifest.files = manifest.files.filter(function(f) { return f.name !== file.name; });
      if (currentFile && currentFile.name === file.name) {
        currentFile = manifest.files.length > 0 ? manifest.files[0] : null;
        if (currentFile) {
          img.src = currentFile.svg + '?t=' + Date.now();
          setStoredSelection(currentFile.name);
        } else {
          img.src = '';
        }
      }
      renderFileList();
    }).catch(function() {});
  }

  function renderFileList() {
    fileList.innerHTML = '';
    manifest.files.forEach(function(f) {
      var li = document.createElement('li');
      if (currentFile && currentFile.name === f.name) li.className = 'active';

      var nameSpan = document.createElement('span');
      nameSpan.className = 'file-name';
      nameSpan.textContent = f.name;
      nameSpan.title = f.name;
      nameSpan.addEventListener('click', function() { selectFile(f); });

      var delBtn = document.createElement('button');
      delBtn.className = 'btn-delete';
      delBtn.title = 'Remove from viewer';
      delBtn.innerHTML = '&#x2715;';
      delBtn.addEventListener('click', function(e) {
        e.stopPropagation();
        deleteFile(f);
      });

      li.appendChild(nameSpan);
      li.appendChild(delBtn);
      fileList.appendChild(li);
    });
    statusBar.textContent = manifest.files.length + ' diagrams';
  }

  function refreshManifest() {
    fetch('manifest.json?t=' + Date.now())
      .then(function(r) { return r.json(); })
      .then(function(data) {
        var changed = data.updated_at !== manifest.updated_at;
        manifest = data;
        if (changed) {
          renderFileList();
          if (currentFile) {
            var found = manifest.files.find(function(f) { return f.name === currentFile.name; });
            if (found) {
              currentFile = found;
              img.src = found.svg + '?t=' + Date.now();
            } else if (manifest.files.length > 0) {
              selectFile(manifest.files[0]);
            }
          }
        }
      })
      .catch(function() {});
  }

  // 初回ロード
  refreshManifest();
  setTimeout(function() {
    var stored = getStoredSelection();
    if (stored) {
      var found = manifest.files.find(function(f) { return f.name === stored; });
      if (found) { selectFile(found); return; }
    }
    if (manifest.files.length > 0) selectFile(manifest.files[0]);
  }, 500);

  // 2秒ポーリング
  setInterval(refreshManifest, 2000);

  // --- Panzoom ---
  var scale = 1, tx = 0, ty = 0;
  var dragging = false, startX, startY, startTx, startTy;

  function applyTransform() {
    wrapper.style.transform = 'translate(' + tx + 'px,' + ty + 'px) scale(' + scale + ')';
  }

  function fitToView() {
    var cw = container.clientWidth, ch = container.clientHeight;
    var iw = img.naturalWidth || img.width, ih = img.naturalHeight || img.height;
    if (!iw || !ih) return;
    scale = Math.min(cw / iw, ch / ih, 1);
    tx = (cw - iw * scale) / 2;
    ty = (ch - ih * scale) / 2;
    applyTransform();
  }

  img.addEventListener('load', function() { fitToView(); });

  container.addEventListener('wheel', function(e) {
    try { e.preventDefault(); } catch(_) {}
    e.stopPropagation();
    var rect = container.getBoundingClientRect();
    var mx = e.clientX - rect.left, my = e.clientY - rect.top;
    var factor = e.deltaY < 0 ? 1.15 : 1 / 1.15;
    var newScale = scale * factor;
    if (newScale < 0.05 || newScale > 20) return;
    tx = mx - (mx - tx) * factor;
    ty = my - (my - ty) * factor;
    scale = newScale;
    applyTransform();
    return false;
  }, { passive: false, capture: true });

  container.addEventListener('mousedown', function(e) {
    dragging = true;
    container.classList.add('dragging');
    startX = e.clientX; startY = e.clientY;
    startTx = tx; startTy = ty;
  });
  window.addEventListener('mousemove', function(e) {
    if (!dragging) return;
    tx = startTx + (e.clientX - startX);
    ty = startTy + (e.clientY - startY);
    applyTransform();
  });
  window.addEventListener('mouseup', function() {
    dragging = false;
    container.classList.remove('dragging');
  });

  container.addEventListener('dblclick', fitToView);

  document.getElementById('btn-reset').addEventListener('click', fitToView);
  document.getElementById('btn-zoomin').addEventListener('click', function() {
    var cw = container.clientWidth, ch = container.clientHeight;
    var mx = cw / 2, my = ch / 2, factor = 1.3;
    tx = mx - (mx - tx) * factor;
    ty = my - (my - ty) * factor;
    scale *= factor;
    applyTransform();
  });
  document.getElementById('btn-zoomout').addEventListener('click', function() {
    var cw = container.clientWidth, ch = container.clientHeight;
    var mx = cw / 2, my = ch / 2, factor = 1 / 1.3;
    tx = mx - (mx - tx) * factor;
    ty = my - (my - ty) * factor;
    scale *= factor;
    applyTransform();
  });
})();
</script>
</body>
</html>]]

local function write_index_html()
	if not output_dir then
		return
	end
	local fh = io.open(output_dir .. "/index.html", "w")
	if fh then
		fh:write(VIEWER_HTML)
		fh:close()
	end
end

local function start_server()
	if server_job_id then
		return
	end
	write_bs_config()
	local cmd = {
		"npx", "browser-sync", "start",
		"--config", output_dir .. "/bs-config.js",
	}
	server_job_id = vim.fn.jobstart(cmd, {
		detach = true,
		on_exit = function()
			server_job_id = nil
		end,
	})
end

local function stop_server()
	if server_job_id then
		vim.fn.jobstop(server_job_id)
		server_job_id = nil
	end
end

local function cleanup()
	stop_server()
	vim.api.nvim_clear_autocmds({ group = augroup })
	if debounce_timer then
		debounce_timer:stop()
		debounce_timer = nil
	end
	if output_dir then
		vim.fn.delete(output_dir, "rf")
		output_dir = nil
	end
	registered_files = {}
end

local function convert_and_update_manifest(puml_path)
	if not registered_files[puml_path] then
		return
	end
	convert_file(puml_path)
	write_manifest()
end

local function debounced_convert(puml_path)
	if debounce_timer then
		debounce_timer:stop()
	end
	debounce_timer = vim.defer_fn(function()
		debounce_timer = nil
		convert_and_update_manifest(puml_path)
	end, DEBOUNCE_MS)
end

-- manifest.json のポーリングタイマー（GUI側の削除をNeovim側に同期）
local manifest_poll_timer = nil
local function start_manifest_poll()
	if manifest_poll_timer then
		return
	end
	manifest_poll_timer = vim.uv.new_timer()
	manifest_poll_timer:start(3000, 3000, vim.schedule_wrap(function()
		sync_registered_files_from_manifest()
	end))
end

local function stop_manifest_poll()
	if manifest_poll_timer then
		manifest_poll_timer:stop()
		manifest_poll_timer:close()
		manifest_poll_timer = nil
	end
end

local function ensure_server_and_autocmds()
	if not server_job_id then
		-- 出力ディレクトリ作成
		output_dir = vim.fn.tempname() .. "_plantuml_viewer"
		vim.fn.mkdir(output_dir, "p")
		write_index_html()
		start_server()
		start_manifest_poll()

		-- ブラウザ起動（WSL2非同期、WSL環境ではwslviewを使用）
		vim.defer_fn(function()
			local open_cmd = vim.fn.has("wsl") == 1 and "wslview" or "xdg-open"
			vim.fn.jobstart({ open_cmd, "http://localhost:" .. SERVER_PORT }, { detach = true })
		end, 2000)

		-- 保存時に該当ファイルを再変換（登録済みのみ）
		vim.api.nvim_create_autocmd("BufWritePost", {
			group = augroup,
			pattern = "*.puml",
			callback = function(args)
				local path = vim.api.nvim_buf_get_name(args.buf)
				if registered_files[path] then
					if debounce_timer then
						debounce_timer:stop()
						debounce_timer = nil
					end
					convert_and_update_manifest(path)
				end
			end,
		})

		-- テキスト変更時はデバウンスで再変換（登録済みのみ）
		vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
			group = augroup,
			pattern = "*.puml",
			callback = function(args)
				local path = vim.api.nvim_buf_get_name(args.buf)
				if path ~= "" and registered_files[path] then
					debounced_convert(path)
				end
			end,
		})

		-- VimLeave時にクリーンアップ
		vim.api.nvim_create_autocmd("VimLeave", {
			group = augroup,
			callback = function()
				stop_manifest_poll()
				cleanup()
			end,
		})
	end
end

vim.api.nvim_create_user_command("PlantumlOpen", function()
	local bufnr = vim.api.nvim_get_current_buf()
	local path = vim.api.nvim_buf_get_name(bufnr)

	if path == "" or not path:match("%.puml$") then
		vim.notify("PlantUML: 現在のバッファは .puml ファイルではありません", vim.log.levels.ERROR)
		return
	end

	if vim.fn.executable("java") == 0 then
		vim.notify("PlantUML: java が見つかりません", vim.log.levels.ERROR)
		return
	end
	if vim.fn.executable("npx") == 0 then
		vim.notify("PlantUML: npx が見つかりません（Node.jsが必要です）", vim.log.levels.ERROR)
		return
	end

	-- サーバーとautocmdを初期化（初回のみ）
	ensure_server_and_autocmds()

	-- 現在のファイルをビューアに登録・変換
	register_and_convert(path)

	local count = 0
	for _ in pairs(registered_files) do
		count = count + 1
	end

	if server_job_id and count > 1 then
		-- 既にサーバーが動いている場合はブラウザを開かない（追加登録のみ）
		vim.notify(string.format("PlantUML: added %s (%d files total)", vim.fn.fnamemodify(path, ":t"), count))
	else
		vim.notify(string.format("PlantUML: viewer started at http://localhost:%d", SERVER_PORT))
	end
end, { force = true })

vim.api.nvim_create_user_command("PlantumlStop", function()
	if not server_job_id then
		vim.notify("PlantUML: viewer is not running")
		return
	end
	stop_manifest_poll()
	cleanup()
	vim.notify("PlantUML: viewer stopped")
end, { force = true })
