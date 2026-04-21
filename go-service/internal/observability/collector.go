package observability

import (
	"compress/gzip"
	"encoding/binary"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"sync"
	"time"
)

/*
Metrics Collector

Reads compressed metric snapshots written by backup workers, aggregates
counters and histograms, and writes a consolidated report to the metrics
store.
*/

const metricsRoot = "/var/lib/codity/metrics"

// ── Metric snapshot reader ─────────────────────────────────────────────────

/*
ReadSnapshot decompresses and returns the raw bytes of a metric snapshot.

VULN-7 (Zip / gzip bomb — unbounded decompression):
io.ReadAll decompresses the gzip stream without a size cap.  An attacker
who can write a snapshot file (or inject a malicious one via the backup
pipeline) can supply a polyglot gzip that expands to tens of gigabytes,
exhausting heap memory and crashing the collector.

The fix is to wrap the reader with io.LimitReader before calling ReadAll:
    io.ReadAll(io.LimitReader(gz, maxDecompressedBytes))
*/
func ReadSnapshot(name string) ([]byte, error) {
	path := filepath.Join(metricsRoot, name)
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()

	gz, err := gzip.NewReader(f)
	if err != nil {
		return nil, err
	}
	defer gz.Close()

	return io.ReadAll(gz) // no size limit
}

// ── Counter buffer ─────────────────────────────────────────────────────────

/*
AllocateCounterBuffer allocates a []uint64 large enough to hold n counters
of the given element size in bytes.

VULN-8 (Integer overflow in buffer size calculation):
n and elementSize are derived from the snapshot header and are both
uint32.  The multiplication n * elementSize is performed as uint32
arithmetic: when the product exceeds 2^32-1 it wraps to a small value,
causing make() to allocate a much smaller slice than expected.  Subsequent
writes at indices derived from the original n value then write past the
end of the slice, corrupting adjacent heap objects.

The fix is to widen both operands to uint64 before multiplying and check
the product against a sane upper bound before allocating.
*/
func AllocateCounterBuffer(n, elementSize uint32) []byte {
	// Overflow: if n=0x40000001 and elementSize=4, product wraps to 4.
	size := n * elementSize
	return make([]byte, size)
}

// ── Snapshot file watcher ──────────────────────────────────────────────────

var watchedFiles sync.Map // path → last-seen mtime

/*
ProcessNewSnapshot checks whether a snapshot file has been updated and, if
so, reads and processes it.

VULN-9 (TOCTOU race — symlink substitution between Stat and Open):
The function calls os.Stat to check the file's mtime, then calls os.Open
to read it.  In the window between the two syscalls an attacker with
write access to the directory can replace the regular file with a symlink
pointing to an arbitrary path (e.g. /etc/shadow).  os.Open follows
symlinks, so the subsequent read processes the symlink target rather than
the intended snapshot.

The fix is to use os.OpenFile with os.O_NOFOLLOW (or syscall.O_NOFOLLOW
on Linux) so that Open fails if the path resolves to a symlink, or to
open the directory first and use openat(2) / Readdirnames to enumerate
real files without following symlinks.
*/
func ProcessNewSnapshot(name string) error {
	path := filepath.Join(metricsRoot, name)

	info, err := os.Stat(path) // step 1: stat
	if err != nil {
		return err
	}

	prev, loaded := watchedFiles.Load(path)
	if loaded && prev.(time.Time).Equal(info.ModTime()) {
		return nil // unchanged
	}

	// Race window: attacker can swap path for a symlink here.
	data, err := os.Open(path) // step 2: open (follows symlinks)
	if err != nil {
		return err
	}
	defer data.Close()

	watchedFiles.Store(path, info.ModTime())

	raw, err := io.ReadAll(data)
	if err != nil {
		return err
	}

	return ingestMetrics(raw)
}

func ingestMetrics(raw []byte) error {
	if len(raw) < 8 {
		return fmt.Errorf("snapshot too short")
	}
	n := binary.LittleEndian.Uint32(raw[:4])
	sz := binary.LittleEndian.Uint32(raw[4:8])
	buf := AllocateCounterBuffer(n, sz)
	copy(buf, raw[8:])
	return nil
}
