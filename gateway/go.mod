package main

import (
  "bytes"
  "encoding/json"
  "fmt"
  "net/http"
  "os"
  "testing"
  "time"
)

func TestWatchdogFlashCrash(t *testing.T) {
  baseURL := "http://127.0.0.1:8080"
  if value := os.Getenv("EXCHANGE_BASE_URL"); value != "" {
    baseURL = value
  }

  userID := uint64(1001)
  password := "SecurePassword123!"

  registerReq, _ := json.Marshal(map[string]any{"user_id": userID, "password": password})
  req, err := http.NewRequest(http.MethodPost, baseURL+"/api/v1/auth/register", bytes.NewReader(registerReq))
  if err != nil {
    t.Fatalf("failed to build register request: %v", err)
  }
  req.Header.Set("Content-Type", "application/json")
  resp, err := http.DefaultClient.Do(req)
  if err != nil {
    t.Fatalf("register failed: %v", err)
  }
  if resp.StatusCode != http.StatusCreated && resp.StatusCode != http.StatusConflict {
    t.Fatalf("unexpected register status: %d", resp.StatusCode)
  }
  resp.Body.Close()

  loginReq, _ := json.Marshal(map[string]any{"user_id": userID, "password": password})
  req, err = http.NewRequest(http.MethodPost, baseURL+"/api/v1/auth/login", bytes.NewReader(loginReq))
  if err != nil {
    t.Fatalf("failed to build login request: %v", err)
  }
  req.Header.Set("Content-Type", "application/json")
  resp, err = http.DefaultClient.Do(req)
  if err != nil {
    t.Fatalf("login failed: %v", err)
  }
  if resp.StatusCode != http.StatusOK {
    t.Fatalf("login status was %d; expected 200", resp.StatusCode)
  }
  var tokenResp map[string]string
  if err := json.NewDecoder(resp.Body).Decode(&tokenResp); err != nil {
    t.Fatalf("decode login response: %v", err)
  }
  resp.Body.Close()

  token := tokenResp["token"]
  if token == "" {
    t.Fatal("empty JWT token returned")
  }

  orderBody, _ := json.Marshal(map[string]any{"price": 65000.0, "quantity": 4.5, "side": 0, "type": 0})
  req, err = http.NewRequest(http.MethodPost, baseURL+"/api/v1/order/submit", bytes.NewReader(orderBody))
  if err != nil {
    t.Fatalf("build order request: %v", err)
  }
  req.Header.Set("Authorization", "Bearer "+token)
  req.Header.Set("Content-Type", "application/json")
  resp, err = http.DefaultClient.Do(req)
  if err != nil {
    t.Fatalf("order submit failed: %v", err)
  }
  if resp.StatusCode != http.StatusOK {
    t.Fatalf("order submit status was %d; expected 200", resp.StatusCode)
  }
  resp.Body.Close()

  markBody, _ := json.Marshal(map[string]any{"price": 58000.0})
  req, err = http.NewRequest(http.MethodPost, baseURL+"/api/v1/admin/mark-price", bytes.NewReader(markBody))
  if err != nil {
    t.Fatalf("build mark-price request: %v", err)
  }
  req.Header.Set("Authorization", "Bearer "+token)
  req.Header.Set("Content-Type", "application/json")
  resp, err = http.DefaultClient.Do(req)
  if err != nil {
    t.Fatalf("mark-price request failed: %v", err)
  }
  if resp.StatusCode != http.StatusOK {
    t.Fatalf("mark-price status was %d; expected 200", resp.StatusCode)
  }
  resp.Body.Close()

  fmt.Println("[Watchdog] Flash-crash scenario submitted; allow the risk engine to process the mark-price event.")
  time.Sleep(250 * time.Millisecond)
}
