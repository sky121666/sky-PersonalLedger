package database

import (
	"context"
	"database/sql"
	"fmt"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"gorm.io/gorm"
)

func r6Open(t *testing.T, path string) (*gorm.DB, *sql.DB) {
	t.Helper()
	db, err := Init(path)
	if err != nil {
		t.Fatal(err)
	}
	pool, err := db.DB()
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		if err := pool.Close(); err != nil {
			t.Error(err)
		}
	})
	return db, pool
}

func r6Engine(t *testing.T, db *sql.DB) string {
	t.Helper()
	var version, source, mode, integrity string
	for query, target := range map[string]*string{
		"SELECT sqlite_version()":   &version,
		"SELECT sqlite_source_id()": &source,
		"PRAGMA journal_mode":       &mode,
		"PRAGMA integrity_check":    &integrity,
	} {
		if err := db.QueryRow(query).Scan(target); err != nil {
			t.Fatal(err)
		}
	}
	if mode != "wal" || integrity != "ok" {
		t.Fatalf("journal=%s integrity=%s", mode, integrity)
	}
	t.Logf("sqlite_version=%s sqlite_source_id=%s journal_mode=%s integrity_check=%s",
		version, source, mode, integrity)
	return version
}

func TestR6SQLiteWALResetFixedEngine(t *testing.T) {
	_, db := r6Open(t, filepath.Join(t.TempDir(), "engine.db"))
	version := r6Engine(t, db)
	parts := strings.Split(version, ".")
	if len(parts) != 3 {
		t.Fatalf("unexpected SQLite version %q", version)
	}
	var n [3]int
	for i := range n {
		var err error
		n[i], err = strconv.Atoi(parts[i])
		if err != nil {
			t.Fatal(err)
		}
	}
	// SQLite's WAL documentation names these two backports and the mainline fix.
	fixed := n[0] == 3 && (n[1] == 44 && n[2] >= 6 ||
		n[1] == 50 && n[2] >= 7 || n[1] == 51 && n[2] >= 3 || n[1] > 51)
	if !fixed {
		t.Fatalf("SQLite %s is outside the known WAL-reset fixed versions (3.44.6, 3.50.7, >=3.51.3)", version)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	var conns []*sql.Conn
	defer func() {
		for _, conn := range conns {
			_ = conn.Close()
		}
	}()
	for range 2 {
		conn, err := db.Conn(ctx)
		if err != nil {
			t.Fatal(err)
		}
		conns = append(conns, conn)
		var fk, busy, auto int
		for query, target := range map[string]*int{
			"PRAGMA foreign_keys":       &fk,
			"PRAGMA busy_timeout":       &busy,
			"PRAGMA wal_autocheckpoint": &auto,
		} {
			if err := conn.QueryRowContext(ctx, query).Scan(target); err != nil {
				t.Fatal(err)
			}
		}
		if fk != 1 || busy != 5000 || auto != 1000 {
			t.Fatalf("foreign_keys=%d busy_timeout=%d wal_autocheckpoint=%d", fk, busy, auto)
		}
		t.Logf("independent_connection=%d foreign_keys=%d busy_timeout=%d wal_autocheckpoint=%d",
			len(conns), fk, busy, auto)
	}
}

func TestR6SQLiteWALConcurrentReadersWritersCheckpoint(t *testing.T) {
	r6ConcurrentCheckpoint(t, true)
}

func TestR6SQLiteWALConcurrentResetCheckpoint(t *testing.T) {
	r6ConcurrentCheckpoint(t, false)
}

func r6ConcurrentCheckpoint(t *testing.T, pinSnapshot bool) {
	t.Helper()
	path := filepath.Join(t.TempDir(), "wal.db")
	_, primary := r6Open(t, path)
	r6Engine(t, primary)
	for _, query := range []string{
		"CREATE TABLE r6_balance (id INTEGER PRIMARY KEY, cents INTEGER NOT NULL)",
		"INSERT INTO r6_balance VALUES (1, 0)",
		"CREATE TABLE r6_entries (id TEXT PRIMARY KEY, cents INTEGER NOT NULL)",
	} {
		if _, err := primary.Exec(query); err != nil {
			t.Fatal(err)
		}
	}
	const writers, writes, readers, reads, checkpoints = 2, 300, 3, 300, 300
	var pools []*sql.DB
	for range writers + readers + 1 {
		_, pool := r6Open(t, path)
		pool.SetMaxOpenConns(1)
		pool.SetMaxIdleConns(1)
		pools = append(pools, pool)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 40*time.Second)
	defer cancel()
	var pinned *sql.Tx
	if pinSnapshot {
		var err error
		pinned, err = primary.BeginTx(ctx, &sql.TxOptions{ReadOnly: true})
		if err != nil {
			t.Fatal(err)
		}
		defer pinned.Rollback()
		var initial int
		if err := pinned.QueryRow("SELECT cents FROM r6_balance WHERE id=1").Scan(&initial); err != nil || initial != 0 {
			t.Fatalf("pin initial snapshot: cents=%d err=%v", initial, err)
		}
	}
	start := make(chan struct{})
	errs := make(chan error, writers+readers+1)
	var wg sync.WaitGroup
	var committed, snapshots, checkpointRuns, partialCheckpoints atomic.Int64
	var resetsDuringWrites atomic.Int64
	for writer := range writers {
		wg.Add(1)
		go func() {
			defer wg.Done()
			<-start
			for i := range writes {
				tx, err := pools[writer].BeginTx(ctx, nil)
				if err != nil {
					errs <- err
					return
				}
				_, err = tx.ExecContext(ctx, "INSERT INTO r6_entries VALUES (?, 1)", fmt.Sprintf("%d-%d", writer, i))
				if err == nil {
					_, err = tx.ExecContext(ctx, "UPDATE r6_balance SET cents=cents+1 WHERE id=1")
				}
				if err != nil {
					_ = tx.Rollback()
					errs <- err
					return
				}
				if err = tx.Commit(); err != nil {
					errs <- err
					return
				}
				committed.Add(1)
				if !pinSnapshot && i%10 == 0 {
					time.Sleep(time.Millisecond)
				}
			}
		}()
	}
	for reader := range readers {
		wg.Add(1)
		go func() {
			defer wg.Done()
			<-start
			for range reads {
				tx, err := pools[writers+reader].BeginTx(ctx, &sql.TxOptions{ReadOnly: true})
				if err != nil {
					errs <- err
					return
				}
				var balance, total int
				err = tx.QueryRowContext(ctx, "SELECT cents FROM r6_balance WHERE id=1").Scan(&balance)
				if err == nil {
					err = tx.QueryRowContext(ctx, "SELECT coalesce(sum(cents),0) FROM r6_entries").Scan(&total)
				}
				_ = tx.Rollback()
				if err != nil || balance != total {
					errs <- fmt.Errorf("snapshot balance=%d entries=%d error=%v", balance, total, err)
					return
				}
				snapshots.Add(1)
			}
		}()
	}
	wg.Add(1)
	go func() {
		defer wg.Done()
		<-start
		for i := range checkpoints {
			var busy, logFrames, copied int
			query := "PRAGMA wal_checkpoint(PASSIVE)"
			if !pinSnapshot {
				query = "PRAGMA wal_checkpoint(RESTART)"
				if i%2 == 0 {
					query = "PRAGMA wal_checkpoint(TRUNCATE)"
				}
			}
			if err := pools[len(pools)-1].QueryRowContext(ctx, query).
				Scan(&busy, &logFrames, &copied); err != nil {
				errs <- err
				return
			}
			checkpointRuns.Add(1)
			if logFrames > copied {
				partialCheckpoints.Add(1)
			}
			if !pinSnapshot && busy == 0 && committed.Load() > 0 && committed.Load() < writers*writes {
				resetsDuringWrites.Add(1)
			}
			time.Sleep(time.Millisecond)
		}
	}()
	close(start)
	wg.Wait()
	close(errs)
	for err := range errs {
		t.Error(err)
	}
	if t.Failed() {
		return
	}
	if pinned != nil {
		var pinnedValue int
		if err := pinned.QueryRow("SELECT cents FROM r6_balance WHERE id=1").Scan(&pinnedValue); err != nil || pinnedValue != 0 {
			t.Fatalf("pinned snapshot changed: %d %v", pinnedValue, err)
		}
		if err := pinned.Rollback(); err != nil {
			t.Fatal(err)
		}
	}
	var balance, entries, total int
	if err := primary.QueryRow("SELECT cents FROM r6_balance WHERE id=1").Scan(&balance); err != nil {
		t.Fatal(err)
	}
	if err := primary.QueryRow("SELECT count(*), sum(cents) FROM r6_entries").Scan(&entries, &total); err != nil {
		t.Fatal(err)
	}
	if balance != writers*writes || entries != balance || total != balance ||
		committed.Load() != writers*writes || snapshots.Load() != readers*reads ||
		checkpointRuns.Load() != checkpoints {
		t.Fatalf("committed=%d snapshots=%d checkpoints=%d partial=%d balance=%d entries=%d sum=%d",
			committed.Load(), snapshots.Load(), checkpointRuns.Load(), partialCheckpoints.Load(), balance, entries, total)
	}
	if pinSnapshot && partialCheckpoints.Load() == 0 {
		t.Fatal("no checkpoint observed the pinned reader")
	}
	if !pinSnapshot && resetsDuringWrites.Load() == 0 {
		t.Fatal("no successful RESTART/TRUNCATE checkpoint interleaved with writes")
	}
	var busy, frames, checked int
	if err := primary.QueryRow("PRAGMA wal_checkpoint(TRUNCATE)").Scan(&busy, &frames, &checked); err != nil {
		t.Fatal(err)
	}
	if busy != 0 || frames != 0 || checked != 0 {
		t.Fatalf("truncate checkpoint=%d,%d,%d", busy, frames, checked)
	}
	r6Engine(t, primary)
	t.Logf("pinned=%t writers=%d committed=%d readers=%d snapshots=%d checkpoints=%d partial_checkpoints=%d resets_during_writes=%d final_truncate=%d,%d,%d",
		pinSnapshot, writers, committed.Load(), readers, snapshots.Load(), checkpointRuns.Load(), partialCheckpoints.Load(), resetsDuringWrites.Load(), busy, frames, checked)
}
