package observability

import (
	"crypto/subtle"
	"database/sql"
	"fmt"
	"net/http"
	"runtime"
	"sort"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/gin-gonic/gin"
)

var durationBuckets = [...]float64{0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5}

type requestKey struct {
	method string
	route  string
	status int
}

type requestMetrics struct {
	count   uint64
	buckets [len(durationBuckets) + 1]uint64
	sum     float64
}

// Registry stores bounded, process-local operational metrics. Route labels use
// Gin templates instead of raw URLs so IDs and query strings are never exposed.
type Registry struct {
	startedAt time.Time
	db        *sql.DB
	inFlight  atomic.Int64
	mu        sync.RWMutex
	requests  map[requestKey]requestMetrics
}

func NewRegistry(db *sql.DB) *Registry {
	return &Registry{
		startedAt: time.Now(),
		db:        db,
		requests:  make(map[requestKey]requestMetrics),
	}
}

func (r *Registry) Middleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		startedAt := time.Now()
		r.inFlight.Add(1)
		defer r.inFlight.Add(-1)

		c.Next()

		route := c.FullPath()
		if route == "" {
			route = "unmatched"
		}
		r.observe(c.Request.Method, route, c.Writer.Status(), time.Since(startedAt))
	}
}

func (r *Registry) observe(method, route string, status int, duration time.Duration) {
	key := requestKey{method: metricMethod(method), route: route, status: status}
	seconds := duration.Seconds()
	r.mu.Lock()
	metric := r.requests[key]
	metric.count++
	metric.sum += seconds
	for index, upperBound := range durationBuckets {
		if seconds <= upperBound {
			metric.buckets[index]++
		}
	}
	metric.buckets[len(durationBuckets)]++
	r.requests[key] = metric
	r.mu.Unlock()
}

func (r *Registry) Handler(token string) gin.HandlerFunc {
	expected := []byte("Bearer " + token)
	return func(c *gin.Context) {
		provided := []byte(c.GetHeader("Authorization"))
		if len(provided) != len(expected) || subtle.ConstantTimeCompare(provided, expected) != 1 {
			c.Header("WWW-Authenticate", "Bearer")
			c.AbortWithStatus(http.StatusUnauthorized)
			return
		}
		c.Header("Content-Type", "text/plain; version=0.0.4; charset=utf-8")
		c.Data(http.StatusOK, "text/plain; version=0.0.4; charset=utf-8", []byte(r.render()))
	}
}

func metricMethod(method string) string {
	switch method {
	case http.MethodGet, http.MethodHead, http.MethodPost, http.MethodPut,
		http.MethodPatch, http.MethodDelete, http.MethodConnect, http.MethodOptions,
		http.MethodTrace:
		return method
	default:
		return "OTHER"
	}
}

func (r *Registry) render() string {
	r.mu.RLock()
	keys := make([]requestKey, 0, len(r.requests))
	values := make(map[requestKey]requestMetrics, len(r.requests))
	for key, value := range r.requests {
		keys = append(keys, key)
		values[key] = value
	}
	r.mu.RUnlock()
	sort.Slice(keys, func(i, j int) bool {
		if keys[i].route != keys[j].route {
			return keys[i].route < keys[j].route
		}
		if keys[i].method != keys[j].method {
			return keys[i].method < keys[j].method
		}
		return keys[i].status < keys[j].status
	})

	var output strings.Builder
	output.WriteString("# HELP ledger_http_requests_total Total HTTP requests by route template.\n")
	output.WriteString("# TYPE ledger_http_requests_total counter\n")
	for _, key := range keys {
		labels := requestLabels(key)
		fmt.Fprintf(&output, "ledger_http_requests_total{%s} %d\n", labels, values[key].count)
	}
	output.WriteString("# HELP ledger_http_request_duration_seconds HTTP request duration by route template.\n")
	output.WriteString("# TYPE ledger_http_request_duration_seconds histogram\n")
	for _, key := range keys {
		metric := values[key]
		labels := requestLabels(key)
		for index, upperBound := range durationBuckets {
			fmt.Fprintf(&output, "ledger_http_request_duration_seconds_bucket{%s,le=%q} %d\n", labels, strconv.FormatFloat(upperBound, 'g', -1, 64), metric.buckets[index])
		}
		fmt.Fprintf(&output, "ledger_http_request_duration_seconds_bucket{%s,le=\"+Inf\"} %d\n", labels, metric.buckets[len(durationBuckets)])
		fmt.Fprintf(&output, "ledger_http_request_duration_seconds_sum{%s} %s\n", labels, strconv.FormatFloat(metric.sum, 'f', 6, 64))
		fmt.Fprintf(&output, "ledger_http_request_duration_seconds_count{%s} %d\n", labels, metric.count)
	}
	fmt.Fprintf(&output, "# HELP ledger_http_requests_in_flight Current in-flight HTTP requests.\n# TYPE ledger_http_requests_in_flight gauge\nledger_http_requests_in_flight %d\n", r.inFlight.Load())
	fmt.Fprintf(&output, "# HELP ledger_process_uptime_seconds Process uptime in seconds.\n# TYPE ledger_process_uptime_seconds gauge\nledger_process_uptime_seconds %.3f\n", time.Since(r.startedAt).Seconds())
	fmt.Fprintf(&output, "# HELP ledger_go_goroutines Current Go goroutines.\n# TYPE ledger_go_goroutines gauge\nledger_go_goroutines %d\n", runtime.NumGoroutine())
	var memory runtime.MemStats
	runtime.ReadMemStats(&memory)
	fmt.Fprintf(&output, "# HELP ledger_go_memory_alloc_bytes Currently allocated Go heap bytes.\n# TYPE ledger_go_memory_alloc_bytes gauge\nledger_go_memory_alloc_bytes %d\n", memory.Alloc)
	if r.db != nil {
		stats := r.db.Stats()
		fmt.Fprintf(&output, "# HELP ledger_db_open_connections Open database connections.\n# TYPE ledger_db_open_connections gauge\nledger_db_open_connections %d\n", stats.OpenConnections)
		fmt.Fprintf(&output, "# HELP ledger_db_in_use_connections In-use database connections.\n# TYPE ledger_db_in_use_connections gauge\nledger_db_in_use_connections %d\n", stats.InUse)
		fmt.Fprintf(&output, "# HELP ledger_db_wait_count_total Database connection waits.\n# TYPE ledger_db_wait_count_total counter\nledger_db_wait_count_total %d\n", stats.WaitCount)
	}
	return output.String()
}

func requestLabels(key requestKey) string {
	return fmt.Sprintf(
		"method=%s,route=%s,status=%s",
		quoteLabel(key.method),
		quoteLabel(key.route),
		quoteLabel(strconv.Itoa(key.status)),
	)
}

func quoteLabel(value string) string {
	value = strings.ReplaceAll(value, `\`, `\\`)
	value = strings.ReplaceAll(value, "\n", `\n`)
	value = strings.ReplaceAll(value, `"`, `\"`)
	return `"` + value + `"`
}
