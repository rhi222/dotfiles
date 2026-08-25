package session

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

// Marker is one running Neovim process. One file per owner avoids a clean exit
// deleting another Neovim process's restore intent in the same pane.
type Marker struct {
	Version    int      `json:"version"`
	Owner      string   `json:"owner"`
	PaneID     string   `json:"pane_id"`
	SocketPath string   `json:"socket_path"`
	Cwd        string   `json:"cwd"`
	Kind       string   `json:"kind"`
	Args       []string `json:"args,omitempty"`
	SessionTag string   `json:"session_tag,omitempty"`
}

type Pane struct {
	PaneID      string `json:"pane_id"`
	WorkspaceID string `json:"workspace_id"`
	Cwd         string `json:"cwd"`
}

type paneList struct {
	Result struct {
		Panes []Pane `json:"panes"`
	} `json:"result"`
}

type Entry struct {
	Kind    string `json:"kind"`
	PaneID  string `json:"pane_id"`
	Command string `json:"command"`
}

type Plan struct {
	Entries []Entry  `json:"entries"`
	Stale   []string `json:"stale"`
}

type PlanOptions struct {
	MarkerDir        string
	PaneJSON         []byte
	SocketPath       string
	FocusedWorkspace string
	AllowLegacy      bool
}

type candidate struct {
	marker Marker
	path   string
	mtime  int64
	target Pane
}

// BuildPlan reads local process records and maps them onto Herdr's restored
// panes. An exact pane id wins. A unique cwd match is a conservative fallback
// for panes moved between workspaces, because Herdr changes their public id.
func BuildPlan(opts PlanOptions) (Plan, error) {
	var listed paneList
	if err := json.Unmarshal(opts.PaneJSON, &listed); err != nil {
		return Plan{}, fmt.Errorf("pane list JSON: %w", err)
	}
	if listed.Result.Panes == nil {
		return Plan{}, fmt.Errorf("pane list JSON has no panes array")
	}

	byID := make(map[string]Pane, len(listed.Result.Panes))
	byCwd := make(map[string][]Pane)
	for _, pane := range listed.Result.Panes {
		if pane.PaneID == "" {
			continue
		}
		byID[pane.PaneID] = pane
		if pane.Cwd != "" {
			byCwd[pane.Cwd] = append(byCwd[pane.Cwd], pane)
		}
	}

	files, err := os.ReadDir(opts.MarkerDir)
	if err != nil {
		if os.IsNotExist(err) {
			return Plan{Entries: []Entry{}, Stale: []string{}}, nil
		}
		return Plan{}, err
	}

	var stale []string
	byTarget := make(map[string]candidate)
	for _, file := range files {
		if file.IsDir() {
			continue
		}
		path := filepath.Join(opts.MarkerDir, file.Name())
		marker, legacy, err := readMarker(path)
		if err != nil {
			// A partial/corrupt record must never turn into a restore command.
			continue
		}
		if legacy && !opts.AllowLegacy {
			continue
		}
		if !legacy && marker.SocketPath != opts.SocketPath {
			continue
		}

		target, exact := byID[marker.PaneID]
		if !exact {
			matches := byCwd[marker.Cwd]
			if marker.Cwd != "" && len(matches) == 1 {
				target = matches[0]
			} else if len(matches) == 0 {
				stale = append(stale, path)
				continue
			} else {
				// The cwd fallback is ambiguous. Retain the record for diagnosis and
				// refuse to inject a command into an arbitrary pane.
				continue
			}
		}
		info, err := file.Info()
		if err != nil {
			continue
		}
		c := candidate{marker: marker, path: path, mtime: info.ModTime().UnixNano(), target: target}
		if old, ok := byTarget[target.PaneID]; !ok || newer(c, old) {
			byTarget[target.PaneID] = c
		}
	}

	entries := make([]Entry, 0, len(byTarget))
	for _, c := range byTarget {
		cmd, ok := restoreCommand(c.marker, c.target.PaneID)
		if !ok {
			continue
		}
		entries = append(entries, Entry{Kind: "nvim", PaneID: c.target.PaneID, Command: cmd})
	}
	sort.Slice(entries, func(i, j int) bool {
		iFocused := workspaceOf(entries[i].PaneID) == opts.FocusedWorkspace
		jFocused := workspaceOf(entries[j].PaneID) == opts.FocusedWorkspace
		if iFocused != jFocused {
			return iFocused
		}
		return entries[i].PaneID < entries[j].PaneID
	})
	sort.Strings(stale)
	return Plan{Entries: entries, Stale: stale}, nil
}

func readMarker(path string) (Marker, bool, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return Marker{}, false, err
	}
	var marker Marker
	if json.Unmarshal(b, &marker) == nil && marker.Version == 2 && marker.Owner != "" && marker.PaneID != "" {
		return marker, false, nil
	}
	// Version 1 used the pane id as filename and stored only cwd as text.
	name := filepath.Base(path)
	if !strings.Contains(name, ":") {
		return Marker{}, false, fmt.Errorf("invalid marker")
	}
	return Marker{
		Version: 1, Owner: name, PaneID: name, Cwd: strings.TrimSpace(string(b)),
		Kind: "session", SessionTag: name,
	}, true, nil
}

func newer(a, b candidate) bool {
	if a.mtime != b.mtime {
		return a.mtime > b.mtime
	}
	return a.path > b.path
}

func restoreCommand(marker Marker, targetPane string) (string, bool) {
	switch marker.Kind {
	case "session", "":
		if marker.SessionTag != "" && marker.SessionTag != targetPane {
			return "env HERDR_RESTORE_SESSION_TAG=" + shellQuote(marker.SessionTag) + " nvim", true
		}
		return "nvim", true
	case "files":
		if len(marker.Args) == 0 {
			return "", false
		}
		parts := []string{"nvim", "--"}
		for _, arg := range marker.Args {
			parts = append(parts, shellQuote(arg))
		}
		return strings.Join(parts, " "), true
	default:
		return "", false
	}
}

func shellQuote(s string) string {
	return "'" + strings.ReplaceAll(s, "'", "'\"'\"'") + "'"
}

func workspaceOf(paneID string) string {
	if i := strings.IndexByte(paneID, ':'); i >= 0 {
		return paneID[:i]
	}
	return paneID
}
