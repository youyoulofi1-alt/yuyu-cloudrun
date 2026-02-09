package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"os"
	"strings"
	"time"
)

// StatsResponse represents XRAY stats API response
type StatsResponse struct {
	Stat []Stat `json:"stat"`
}

type Stat struct {
	Name  string `json:"name"`
	Value int64  `json:"value"`
}

// ConnectionInfo holds current connection stats
type ConnectionInfo struct {
	ActiveConnections int64 `json:"active_connections"`
	UploadTraffic     int64 `json:"upload_bytes"`
	DownloadTraffic   int64 `json:"download_bytes"`
	TotalTraffic      int64 `json:"total_bytes"`
}

// getTelegramEnv gets telegram credentials from environment
func getTelegramEnv() (botToken, chatID string, shouldMonitor bool) {
	botToken = os.Getenv("BOT_TOKEN")
	chatID = os.Getenv("CHAT_ID")
	shouldMonitor = botToken != "" && chatID != ""
	return
}

// getXRAYStats retrieves connection statistics from XRAY API
func getXRAYStats(ctx context.Context) (*ConnectionInfo, error) {
	// Connect to XRAY API (usually listening on localhost:10085)
	apiAddr := "127.0.0.1:10085"
	
	// Create a context with timeout
	dialCtx, cancel := context.WithTimeout(ctx, 2*time.Second)
	defer cancel()
	
	// Dial XRAY API
	dialer := &net.Dialer{}
	conn, err := dialer.DialContext(dialCtx, "tcp", apiAddr)
	if err != nil {
		return nil, fmt.Errorf("failed to connect to XRAY API: %v", err)
	}
	defer conn.Close()

	// Build XRAY API request
	// Format: command\nobject\n
	request := "StatsService\nQueryStats\n"
	if _, err := fmt.Fprint(conn, request); err != nil {
		return nil, fmt.Errorf("failed to send request: %v", err)
	}

	// Read response (attempt to parse JSON). Responses may vary; be tolerant.
	_ = conn.SetReadDeadline(time.Now().Add(2 * time.Second))
	respBytes, err := io.ReadAll(conn)
	if err != nil && !errors.Is(err, io.EOF) {
		return nil, fmt.Errorf("failed to read response: %v", err)
	}

	info := &ConnectionInfo{}
	var sr StatsResponse
	if err := json.Unmarshal(respBytes, &sr); err == nil {
		for _, st := range sr.Stat {
			name := strings.ToLower(st.Name)
			if strings.Contains(name, "connection") {
				info.ActiveConnections += st.Value
			}
			if strings.Contains(name, "uplink") || strings.Contains(name, "up") {
				info.UploadTraffic += st.Value
			}
			if strings.Contains(name, "downlink") || strings.Contains(name, "down") {
				info.DownloadTraffic += st.Value
			}
		}
		info.TotalTraffic = info.UploadTraffic + info.DownloadTraffic
		return info, nil
	}

	// Fallback: try to extract numbers from plain text
	var active int64
	var up int64
	var down int64
	parts := strings.Fields(string(respBytes))
	for i := 0; i < len(parts); i++ {
		p := parts[i]
		if strings.Contains(strings.ToLower(p), "conn") {
			// look ahead for a number
			if i+1 < len(parts) {
				if v, err := parseInt(parts[i+1]); err == nil {
					active += v
				}
			}
		}
		if strings.Contains(strings.ToLower(p), "up") {
			if i+1 < len(parts) {
				if v, err := parseInt(parts[i+1]); err == nil {
					up += v
				}
			}
		}
		if strings.Contains(strings.ToLower(p), "down") {
			if i+1 < len(parts) {
				if v, err := parseInt(parts[i+1]); err == nil {
					down += v
				}
			}
		}
	}
	info.ActiveConnections = active
	info.UploadTraffic = up
	info.DownloadTraffic = down
	info.TotalTraffic = up + down
	return info, nil
}

// helper to parse int64 from string (strips non-digits)
func parseInt(s string) (int64, error) {
	var b strings.Builder
	for _, r := range s {
		if (r >= '0' && r <= '9') || r == '-' {
			b.WriteRune(r)
		}
	}
	if b.Len() == 0 {
		return 0, fmt.Errorf("no number in %s", s)
	}
	var v int64
	_, err := fmt.Sscan(b.String(), &v)
	return v, err
}

// Start HTTP server: /api/status and /telegram webhook
func startHTTPServer(addr string) {
	botToken, _, _ := getTelegramEnv()

	http.HandleFunc("/api/status", func(w http.ResponseWriter, r *http.Request) {
		ctx := r.Context()
		info, err := getXRAYStats(ctx)
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(info)
	})

	http.HandleFunc("/telegram", func(w http.ResponseWriter, r *http.Request) {
		// Parse Telegram update
		var upd struct {
			Message *struct {
				Text string `json:"text"`
				Chat *struct {
					ID int64 `json:"id"`
				} `json:"chat"`
			} `json:"message"`
		}
		defer r.Body.Close()
		if err := json.NewDecoder(r.Body).Decode(&upd); err != nil {
			// Acknowledge to avoid retries
			w.WriteHeader(http.StatusOK)
			return
		}
		if upd.Message == nil || upd.Message.Chat == nil {
			w.WriteHeader(http.StatusOK)
			return
		}
		text := strings.TrimSpace(upd.Message.Text)
		chatID := fmt.Sprintf("%d", upd.Message.Chat.ID)

		if strings.HasPrefix(text, "/count") || strings.HasPrefix(text, "/status") {
			info, err := getXRAYStats(r.Context())
			var msg string
			if err != nil {
				msg = fmt.Sprintf("Error getting stats: %v", err)
			} else {
				msg = fmt.Sprintf(`<b>📊 Server Stats</b>\n<b>Active Connections:</b> %d\n<b>Upload:</b> %s\n<b>Download:</b> %s\n<b>Total:</b> %s`,
					info.ActiveConnections,
					formatTraffic(info.UploadTraffic),
					formatTraffic(info.DownloadTraffic),
					formatTraffic(info.TotalTraffic))
			}
			go func() {
				if err := sendTelegramMessage(botToken, chatID, msg); err != nil {
					fmt.Printf("[Webhook] failed to send message: %v\n", err)
				}
			}()
		} else if strings.HasPrefix(text, "/top") {
			// Placeholder for future implementation
			go func() {
				_ = sendTelegramMessage(botToken, chatID, "Top-sites feature is not implemented yet.")
			}()
		}
		w.WriteHeader(http.StatusOK)
	})

	log.Printf("Starting HTTP server on %s", addr)
	if err := http.ListenAndServe(addr, nil); err != nil {
		log.Printf("HTTP server exited: %v", err)
	}
}

// sendTelegramMessage sends a message to Telegram
func sendTelegramMessage(botToken, chatID, message string) error {
	url := fmt.Sprintf("https://api.telegram.org/bot%s/sendMessage", botToken)
	
	payload := strings.NewReader(fmt.Sprintf(`{
		"chat_id": "%s",
		"text": "%s",
		"parse_mode": "HTML"
	}`, chatID, escapeJSON(message)))

	req, err := http.NewRequest("POST", url, payload)
	if err != nil {
		return err
	}

	req.Header.Add("Content-Type", "application/json")

	client := &http.Client{Timeout: 10 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("telegram API error: %d - %s", resp.StatusCode, string(body))
	}

	return nil
}

// escapeJSON escapes special characters for JSON
func escapeJSON(s string) string {
	s = strings.ReplaceAll(s, `\`, `\\`)
	s = strings.ReplaceAll(s, `"`, `\"`)
	s = strings.ReplaceAll(s, "\n", `\n`)
	s = strings.ReplaceAll(s, "\r", `\r`)
	return s
}

// formatTraffic formats bytes to human-readable format
func formatTraffic(bytes int64) string {
	if bytes < 1024 {
		return fmt.Sprintf("%d B", bytes)
	}
	if bytes < 1024*1024 {
		return fmt.Sprintf("%.2f KB", float64(bytes)/1024)
	}
	if bytes < 1024*1024*1024 {
		return fmt.Sprintf("%.2f MB", float64(bytes)/(1024*1024))
	}
	return fmt.Sprintf("%.2f GB", float64(bytes)/(1024*1024*1024))
}

// monitorConnections starts monitoring connections and sending updates to telegram
func monitorConnections(botToken, chatID string, interval time.Duration) {
	ctx := context.Background()
	ticker := time.NewTicker(interval)
	defer ticker.Stop()

	for range ticker.C {
		info, err := getXRAYStats(ctx)
		if err != nil {
			fmt.Printf("[Monitor] Error getting stats: %v\n", err)
			continue
		}

		// Build message
		message := fmt.Sprintf(`<b>📊 Server Stats</b>
<b>Active Connections:</b> %d
<b>Upload Traffic:</b> %s
<b>Download Traffic:</b> %s
<b>Total Traffic:</b> %s
<b>Timestamp:</b> %s`,
			info.ActiveConnections,
			formatTraffic(info.UploadTraffic),
			formatTraffic(info.DownloadTraffic),
			formatTraffic(info.TotalTraffic),
			time.Now().Format("2006-01-02 15:04:05"))

		// Send to telegram
		if err := sendTelegramMessage(botToken, chatID, message); err != nil {
			fmt.Printf("[Monitor] Failed to send message: %v\n", err)
		} else {
			fmt.Println("[Monitor] Message sent successfully")
		}
	}
}

// StartMonitoring starts the monitoring goroutine if configured
func StartMonitoring() {
	botToken, chatID, shouldMonitor := getTelegramEnv()
	if !shouldMonitor {
		fmt.Println("[Monitor] Telegram not configured, monitoring disabled")
		return
	}

	interval := 5 * time.Minute // Send stats every 5 minutes
	go monitorConnections(botToken, chatID, interval)
	fmt.Println("[Monitor] Connection monitoring started - will send updates to Telegram every", interval)
}
