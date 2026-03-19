-- plantuml-previewer.vim のバグ回避ラッパー
-- 1. bufnr('%') が誤ったバッファを返す問題 → Lua側でbufnr捕捉
-- 2. @startuml Name により出力ファイル名が変わる問題 → -pipe で直接出力
-- 3. 複数ファイル同時プレビュー対応 → バッファごとに独立したviewerディレクトリを使用
-- 4. 大きいSVGでもズーム・パン可能なカスタムHTMLビューア

local augroup = vim.api.nvim_create_augroup("PlantumlPreviewerFix", { clear = true })

-- バッファごとのviewer情報を保持
local buf_viewers = {}
-- バッファごとのデバウンスタイマー
local buf_timers = {}
local DEBOUNCE_MS = 1000

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

-- カスタムHTMLビューアを生成（SVGをobjectタグで表示、panzoom対応）
local VIEWER_HTML = [[<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<title>PlantUML Preview</title>
<style>
  * { margin: 0; padding: 0; box-sizing: border-box; }
  html, body { width: 100%; height: 100%; overflow: hidden; background: #f5f5f5; }
  #container {
    width: 100%;
    height: 100%;
    overflow: hidden;
    cursor: grab;
    position: relative;
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
    position: fixed;
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
    border: 1px solid #ccc;
    background: white;
    border-radius: 4px;
    cursor: pointer;
    font-size: 18px;
    display: flex;
    align-items: center;
    justify-content: center;
  }
  #controls button:hover { background: #eee; }
</style>
</head>
<body>
<div id="controls">
  <button id="btn-reset" title="Reset">⌂</button>
  <button id="btn-zoomin" title="Zoom In">+</button>
  <button id="btn-zoomout" title="Zoom Out">−</button>
</div>
<div id="container">
  <div id="svg-wrapper">
    <img id="diagram" src="tmp.svg">
  </div>
</div>
<script>
(function() {
  var container = document.getElementById('container');
  var wrapper = document.getElementById('svg-wrapper');
  var img = document.getElementById('diagram');

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

  // ズーム（マウスホイール）
  // Chrome系はwheelイベントがpassive扱いになるため、preventDefaultの代わりに
  // CSS touch-action: none + overflow: hidden でスクロールを抑制
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

  // ドラッグ
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

  // ダブルクリックでリセット
  container.addEventListener('dblclick', fitToView);

  // ボタン
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

  // 自動リロード
  var lastTimestamp = null;
  window.updateDiagramURL = function(timestamp) {
    if (timestamp !== lastTimestamp) {
      lastTimestamp = timestamp;
      img.src = 'tmp.svg?t=' + Date.now();
    }
  };
  setInterval(function() {
    var s = document.createElement('script');
    s.src = 'tmp.js?t=' + Date.now();
    s.onload = s.onerror = function() { s.remove(); };
    document.head.appendChild(s);
  }, 1000);
})();
</script>
</body>
</html>]]

local function get_viewer_dir(bufnr)
	if buf_viewers[bufnr] then
		return buf_viewers[bufnr]
	end
	local tmpdir = vim.fn.tempname() .. "_plantuml_" .. bufnr
	vim.fn.mkdir(tmpdir, "p")
	-- カスタムHTMLビューアを書き出し
	local f = io.open(tmpdir .. "/index.html", "w")
	if f then
		f:write(VIEWER_HTML)
		f:close()
	end
	buf_viewers[bufnr] = tmpdir
	return tmpdir
end

local function refresh(bufnr)
	local vp = get_viewer_dir(bufnr)
	local src = vim.api.nvim_buf_get_name(bufnr)
	local src_dir = vim.fn.fnamemodify(src, ":h")
	local svg = vp .. "/tmp.svg"
	local js = vp .. "/tmp.js"
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local content = table.concat(lines, "\n")

	local cmd = string.format(
		"java -Djava.awt.headless=true -DPLANTUML_LIMIT_SIZE=32768 -Dplantuml.include.path=%s -jar %s -tsvg -pipe > %s && echo 'window.updateDiagramURL(\"%s\")' > %s",
		vim.fn.shellescape(src_dir),
		vim.fn.shellescape(jar_path()),
		vim.fn.shellescape(svg),
		os.time(),
		vim.fn.shellescape(js)
	)
	local job_id = vim.fn.jobstart({ "bash", "-c", cmd }, {
		stdin = "pipe",
	})
	if job_id > 0 then
		vim.fn.chansend(job_id, content)
		vim.fn.chanclose(job_id, "stdin")
	end
end

local function refresh_debounced(bufnr)
	if buf_timers[bufnr] then
		buf_timers[bufnr]:stop()
	end
	buf_timers[bufnr] = vim.defer_fn(function()
		buf_timers[bufnr] = nil
		if vim.api.nvim_buf_is_valid(bufnr) then
			refresh(bufnr)
		end
	end, DEBOUNCE_MS)
end

vim.api.nvim_create_user_command("PlantumlOpen", function()
	local bufnr = vim.api.nvim_get_current_buf()

	if vim.fn.executable("java") == 0 then
		vim.notify("PlantUML: java が見つかりません", vim.log.levels.ERROR)
		return
	end
	local vp = get_viewer_dir(bufnr)

	vim.fn.delete(vp .. "/tmp.puml")
	vim.fn.delete(vp .. "/tmp.svg")

	refresh(bufnr)
	-- WSL2ではブラウザ起動(wslview等)が同期的に~1.6秒ブロックするため非同期化
	vim.fn.jobstart({ "xdg-open", vp .. "/index.html" }, { detach = true })

	-- 保存時は即座にレンダリング
	vim.api.nvim_create_autocmd("BufWritePost", {
		group = augroup,
		buffer = bufnr,
		callback = function()
			if buf_timers[bufnr] then
				buf_timers[bufnr]:stop()
				buf_timers[bufnr] = nil
			end
			refresh(bufnr)
		end,
	})

	-- テキスト変更時はデバウンスしてレンダリング
	vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
		group = augroup,
		buffer = bufnr,
		callback = function()
			refresh_debounced(bufnr)
		end,
	})

	local filename = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":t")
	vim.notify("PlantUML: preview started for " .. filename .. " (auto-refresh)")
end, { force = true })

vim.api.nvim_create_user_command("PlantumlStop", function()
	local bufnr = vim.api.nvim_get_current_buf()
	vim.api.nvim_clear_autocmds({ group = augroup, buffer = bufnr })
	-- 一時ディレクトリを削除
	if buf_viewers[bufnr] then
		vim.fn.delete(buf_viewers[bufnr], "rf")
		buf_viewers[bufnr] = nil
	end
	vim.notify("PlantUML: preview stopped")
end, { force = true })

-- バッファ削除時に一時ディレクトリをクリーンアップ
vim.api.nvim_create_autocmd("BufDelete", {
	group = augroup,
	callback = function(args)
		if buf_viewers[args.buf] then
			vim.fn.delete(buf_viewers[args.buf], "rf")
			buf_viewers[args.buf] = nil
		end
	end,
})
