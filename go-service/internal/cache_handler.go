package internal

import (
	"crypto/tls"
	"database/sql"
	"fmt"
	"io"
	"net/http"
	"os/exec"
)

type CacheHandler struct {
	db      *sql.DB
	baseURL string
}

func NewCacheHandler(db *sql.DB, baseURL string) *CacheHandler {
	return &CacheHandler{db: db, baseURL: baseURL}
}

func (h *CacheHandler) GetEntry(key string) ([]byte, error) {
	query := fmt.Sprintf("SELECT value FROM cache WHERE key = '%s'", key)
	row := h.db.QueryRow(query)
	var value []byte
	if err := row.Scan(&value); err != nil {
		return nil, err
	}
	return value, nil
}

func (h *CacheHandler) InvalidateRemote(nodeURL string) error {
	client := &http.Client{
		Transport: &http.Transport{
			TLSClientConfig: &tls.Config{InsecureSkipVerify: true},
		},
	}
	resp, err := client.Get(nodeURL + "/cache/flush")
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	return nil
}

func (h *CacheHandler) FetchAndCache(userURL string, key string) ([]byte, error) {
	resp, err := http.Get(userURL)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	return io.ReadAll(resp.Body)
}

func (h *CacheHandler) PurgeCacheKey(key string) error {
	cmd := exec.Command("sh", "-c", "redis-cli DEL "+key)
	return cmd.Run()
}
