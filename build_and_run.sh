package main

import (
  "context"
  "encoding/json"
  "errors"
  "fmt"
  "net/http"
  "os"
  "strconv"
  "sync"
  "sync/atomic"
  "syscall"
  "time"
  "unsafe"

  "github.com/golang-jwt/jwt/v5"
  "github.com/gorilla/websocket"
  "golang.org/x/crypto/bcrypt"
)

const (
  capacity = 4096
  scale    = 100000000
  tokenTTL = 15 * time.Minute
)

type orderPacket struct {
  OrderID  uint64
  UserID   uint64
  Price    uint64
  Quantity uint64
  Side     uint8
  Type     uint8
  Reserved [6]byte
  Padding  [24]byte
}

type depthDelta struct {
  Price    uint64
  Quantity uint64
  Side     uint8
  Padding  [7]byte
}

type sharedBuffer struct {
  WriteIndex, ReadIndex uint32
  OrderPadding          [56]byte
  Queue                 [capacity]orderPacket
  DepthWriteIndex       uint32
  DepthReadIndex        uint32
  DepthPadding          [56]byte
  DepthQueue            [capacity]depthDelta
}

type credentials struct {
  UserID   uint64 `json:"user_id"`
  Password string `json:"password"`
}

type claims struct {
  UserID uint64 `json:"user_id"`
  jwt.RegisteredClaims
}

type userStore struct {
  mu     sync.RWMutex
  hashes map[uint64][]byte
}

type contextKey string

var (
  buffer *sharedBuffer
  nextID uint64
  users  = userStore{hashes: make(map[uint64][]byte)}
  depthMu sync.RWMutex
  bids    = map[uint64]uint64{}
  asks    = map[uint64]uint64{}
  clientsMu sync.RWMutex
  clients   = map[*websocket.Conn]struct{}{}
  currentMarkPrice uint64 = 65000_000_00000
  upgrader = websocket.Upgrader{CheckOrigin: func(r *http.Request) bool { return true }}
)

func jwtSecret() []byte {
  value := os.Getenv("JWT_SECRET")
  if value == "" {
    value = "development-secret-change-this-please-1234"
  }
  return []byte(value)
}

func initSharedMemory() error {
  fd, err := os.OpenFile("/dev/shm/varianth_exchange_shm", os.O_RDWR, 0600)
  if err != nil {
    return err
  }
  defer fd.Close()

  info, err := fd.Stat()
  if err != nil {
    return err
  }

  data, err := syscall.Mmap(int(fd.Fd()), 0, int(info.Size()), syscall.PROT_READ|syscall.PROT_WRITE, syscall.MAP_SHARED)
  if err != nil {
    return err
  }

  buffer = (*sharedBuffer)(unsafe.Pointer(&data[0]))
  return nil
}

func registerUserHandler(w http.ResponseWriter, r *http.Request) {
  if r.Method != http.MethodPost {
    http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
    return
  }

  var creds credentials
  if err := json.NewDecoder(r.Body).Decode(&creds); err != nil || creds.UserID == 0 || len(creds.Password) < 12 {
    http.Error(w, "invalid credentials", http.StatusBadRequest)
    return
  }

  hash, err := bcrypt.GenerateFromPassword([]byte(creds.Password), bcrypt.DefaultCost)
  if err != nil {
    http.Error(w, "registration failed", http.StatusInternalServerError)
    return
  }

  users.mu.Lock()
  defer users.mu.Unlock()
  if _, exists := users.hashes[creds.UserID]; exists {
    http.Error(w, "user already exists", http.StatusConflict)
    return
  }
  users.hashes[creds.UserID] = hash
  w.WriteHeader(http.StatusCreated)
}

func loginUserHandler(w http.ResponseWriter, r *http.Request) {
  if r.Method != http.MethodPost {
    http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
    return
  }

  var creds credentials
  if err := json.NewDecoder(r.Body).Decode(&creds); err != nil || creds.UserID == 0 || creds.Password == "" {
    http.Error(w, "invalid credentials", http.StatusBadRequest)
    return
  }

  users.mu.RLock()
  storedHash, exists := users.hashes[creds.UserID]
  users.mu.RUnlock()
  if !exists || bcrypt.CompareHashAndPassword(storedHash, []byte(creds.Password)) != nil {
    http.Error(w, "unauthorized", http.StatusUnauthorized)
    return
  }

  now := time.Now()
  token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims{
    UserID: creds.UserID,
    RegisteredClaims: jwt.RegisteredClaims{
      Issuer:    "varianth-gateway",
      IssuedAt:  jwt.NewNumericDate(now),
      ExpiresAt: jwt.NewNumericDate(now.Add(tokenTTL)),
      NotBefore: jwt.NewNumericDate(now),
    },
  })

  signed, err := token.SignedString(jwtSecret())
  if err != nil {
    http.Error(w, "token generation failed", http.StatusInternalServerError)
    return
  }

  if err := json.NewEncoder(w).Encode(map[string]string{"token": signed}); err != nil {
    http.Error(w, "response error", http.StatusInternalServerError)
  }
}

func authenticateJWT(next http.HandlerFunc) http.HandlerFunc {
  return func(w http.ResponseWriter, r *http.Request) {
    tokenString := r.Header.Get("Authorization")
    if len(tokenString) < 8 || tokenString[:7] != "Bearer " {
      http.Error(w, "unauthorized", http.StatusUnauthorized)
      return
    }

    parsed, err := jwt.ParseWithClaims(tokenString[7:], &claims{}, func(t *jwt.Token) (interface{}, error) {
      if t.Method != jwt.SigningMethodHS256 {
        return nil, errors.New("unexpected signing method")
      }
      return jwtSecret(), nil
    })
    if err != nil || !parsed.Valid {
      http.Error(w, "unauthorized", http.StatusUnauthorized)
      return
    }

    c, ok := parsed.Claims.(*claims)
    if !ok || c.UserID == 0 {
      http.Error(w, "unauthorized", http.StatusUnauthorized)
      return
    }

    ctx := context.WithValue(r.Context(), contextKey("user_id"), c.UserID)
    next.ServeHTTP(w, r.WithContext(ctx))
  }
}

func orderSubmitHandler(w http.ResponseWriter, r *http.Request) {
  if r.Method != http.MethodPost {
    http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
    return
  }

  userID, ok := r.Context().Value(contextKey("user_id")).(uint64)
  if !ok || userID == 0 {
    http.Error(w, "unauthorized", http.StatusUnauthorized)
    return
  }

  var req struct {
    Price    float64 `json:"price"`
    Quantity float64 `json:"quantity"`
    Side     uint8   `json:"side"`
    Type     uint8   `json:"type"`
  }
  if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.Price <= 0 || req.Quantity <= 0 || req.Side > 1 || req.Type > 1 {
    http.Error(w, "invalid order", http.StatusBadRequest)
    return
  }

  price := uint64(req.Price * scale)
  qty := uint64(req.Quantity * scale)
  if price == 0 || qty == 0 {
    http.Error(w, "invalid order values", http.StatusBadRequest)
    return
  }

  writeIndex := atomic.LoadUint32(&buffer.WriteIndex)
  readIndex := atomic.LoadUint32(&buffer.ReadIndex)
  if writeIndex-readIndex >= capacity {
    http.Error(w, "queue full", http.StatusServiceUnavailable)
    return
  }

  id := atomic.AddUint64(&nextID, 1)
  buffer.Queue[writeIndex%capacity] = orderPacket{
    OrderID:  id,
    UserID:   userID,
    Price:    price,
    Quantity: qty,
    Side:     req.Side,
    Type:     req.Type,
  }
  atomic.StoreUint32(&buffer.WriteIndex, writeIndex+1)

  if err := json.NewEncoder(w).Encode(map[string]string{"status": "queued", "order_id": strconv.FormatUint(id, 10)}); err != nil {
    http.Error(w, "response error", http.StatusInternalServerError)
  }
}

func orderBookDepthHandler(w http.ResponseWriter, r *http.Request) {
  conn, err := upgrader.Upgrade(w, r, nil)
  if err != nil {
    return
  }
  defer conn.Close()

  clientsMu.Lock()
  clients[conn] = struct{}{}
  clientsMu.Unlock()

  depthMu.RLock()
  snapshot, _ := json.Marshal(map[string]any{"event": "orderbook_l2_update", "bids": bids, "asks": asks, "time": time.Now().UnixMilli()})
  depthMu.RUnlock()
  if err := conn.WriteMessage(websocket.TextMessage, snapshot); err != nil {
    return
  }

  for {
    if _, _, err := conn.ReadMessage(); err != nil {
      clientsMu.Lock()
      delete(clients, conn)
      clientsMu.Unlock()
      return
    }
  }
}

func buildDepthSnapshot() []byte {
  depthMu.RLock()
  defer depthMu.RUnlock()
  payload, _ := json.Marshal(map[string]any{"event": "orderbook_l2_update", "bids": bids, "asks": asks, "time": time.Now().UnixMilli()})
  return payload
}

func depthReaderLoop() {
  for {
    readIndex := atomic.LoadUint32(&buffer.DepthReadIndex)
    writeIndex := atomic.LoadUint32(&buffer.DepthWriteIndex)
    if readIndex == writeIndex {
      time.Sleep(time.Millisecond)
      continue
    }

    delta := buffer.DepthQueue[readIndex%capacity]
    atomic.StoreUint32(&buffer.DepthReadIndex, readIndex+1)

    depthMu.Lock()
    if delta.Side == 0 {
      if delta.Quantity == 0 {
        delete(bids, delta.Price)
      } else {
        bids[delta.Price] = delta.Quantity
      }
    } else {
      if delta.Quantity == 0 {
        delete(asks, delta.Price)
      } else {
        asks[delta.Price] = delta.Quantity
      }
    }
    payload := buildDepthSnapshot()
    depthMu.Unlock()

    clientsMu.RLock()
    for conn := range clients {
      if err := conn.WriteMessage(websocket.TextMessage, payload); err != nil {
        conn.Close()
        delete(clients, conn)
      }
    }
    clientsMu.RUnlock()
  }
}

func markPriceHandler(w http.ResponseWriter, r *http.Request) {
  if r.Method != http.MethodPost {
    http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
    return
  }

  var req struct { Price float64 `json:"price"` }
  if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.Price <= 0 {
    http.Error(w, "invalid mark price", http.StatusBadRequest)
    return
  }

  atomic.StoreUint64(&currentMarkPrice, uint64(req.Price*scale))
  if err := json.NewEncoder(w).Encode(map[string]any{"status": "updated", "price": req.Price, "scaled": atomic.LoadUint64(&currentMarkPrice)}); err != nil {
    http.Error(w, "response error", http.StatusInternalServerError)
  }
}

func main() {
  if err := initSharedMemory(); err != nil {
    panic(err)
  }

  go depthReaderLoop()
  go startFIXServer()

  mux := http.NewServeMux()
  mux.HandleFunc("/api/v1/auth/register", registerUserHandler)
  mux.HandleFunc("/api/v1/auth/login", loginUserHandler)
  mux.HandleFunc("/api/v1/order/submit", authenticateJWT(orderSubmitHandler))
  mux.HandleFunc("/api/v1/admin/mark-price", authenticateJWT(markPriceHandler))
  mux.HandleFunc("/ws/orderbook", orderBookDepthHandler)

  fmt.Println("⚡ [Go API Gateway Application Layer Engine] Listening live on secure cluster interface endpoint port :8080...")
  if err := http.ListenAndServe("127.0.0.1:8080", mux); err != nil {
    panic(err)
  }
}
