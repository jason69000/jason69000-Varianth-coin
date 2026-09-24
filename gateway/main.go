package main

import (
  "encoding/json"
  "errors"
  "fmt"
  "net/http"
  "os"
  "strconv"
  "sync"
  "sync/atomic"
  "time"
  "unsafe"

  "github.com/golang-jwt/jwt/v5"
  "github.com/gorilla/websocket"
  "golang.org/x/crypto/bcrypt"
)

const capacity = 4096
const scale = 100000000
const tokenTTL = 15 * time.Minute

type orderPacket struct { OrderID, UserID, Price, Quantity uint64; Side, Type uint8; Reserved [6]byte; Padding [24]byte }
type depthDelta struct { Price, Quantity uint64; Side uint8; Padding [7]byte }
type sharedBuffer struct { WriteIndex, ReadIndex uint32; OrderPadding [56]byte; Queue [capacity]orderPacket; DepthWriteIndex, DepthReadIndex uint32; DepthPadding [56]byte; DepthQueue [capacity]depthDelta }
type credentials struct { UserID uint64 `json:"user_id"`; Password string `json:"password"` }
type claims struct { UserID uint64 `json:"user_id"`; jwt.RegisteredClaims }
type userStore struct { sync.RWMutex; hashes map[uint64][]byte }

var buffer *sharedBuffer
var nextID uint64
var users = userStore{hashes: make(map[uint64][]byte)}
var clients = struct{ sync.RWMutex; m map[*websocket.Conn]struct{} }{m: make(map[*websocket.Conn]struct{})}
var upgrader = websocket.Upgrader{CheckOrigin: func(r *http.Request) bool { return os.Getenv("ALLOW_CROSS_ORIGIN") == "true" }}

func secret() []byte { value := os.Getenv("JWT_SECRET"); if len(value) < 32 { panic("JWT_SECRET must be at least 32 bytes") }; return []byte(value) }
func initSharedMemory() error { f, err := os.OpenFile("/dev/shm/varianth_exchange_shm", os.O_RDWR, 0600); if err != nil { return err }; defer f.Close(); info, err := f.Stat(); if err != nil { return err }; data, err := syscallMmap(int(f.Fd()), int(info.Size())); if err != nil { return err }; buffer = (*sharedBuffer)(unsafe.Pointer(&data[0])); return nil }
func syscallMmap(fd, size int) ([]byte, error) { return unixMmap(fd, size) }

func register(w http.ResponseWriter, r *http.Request) { var c credentials; if json.NewDecoder(http.MaxBytesReader(w, r.Body, 4096)).Decode(&c) != nil || c.UserID == 0 || len(c.Password) < 12 { http.Error(w, "invalid credentials", 400); return }; hash, err := bcrypt.GenerateFromPassword([]byte(c.Password), bcrypt.DefaultCost); if err != nil { http.Error(w, "registration failed", 500); return }; users.Lock(); defer users.Unlock(); if _, ok := users.hashes[c.UserID]; ok { http.Error(w, "user already exists", 409); return }; users.hashes[c.UserID] = hash; w.WriteHeader(http.StatusCreated) }
func login(w http.ResponseWriter, r *http.Request) { var c credentials; if json.NewDecoder(http.MaxBytesReader(w, r.Body, 4096)).Decode(&c) != nil { http.Error(w, "unauthorized", 401); return }; users.RLock(); hash := users.hashes[c.UserID]; users.RUnlock(); if bcrypt.CompareHashAndPassword(hash, []byte(c.Password)) != nil { http.Error(w, "unauthorized", 401); return }; now := time.Now(); token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims{c.UserID, jwt.RegisteredClaims{Issuer:"varianth-gateway", IssuedAt:jwt.NewNumericDate(now), ExpiresAt:jwt.NewNumericDate(now.Add(tokenTTL)), NotBefore:jwt.NewNumericDate(now)}}); value, err := token.SignedString(secret()); if err != nil { http.Error(w, "token failure", 500); return }; json.NewEncoder(w).Encode(map[string]string{"token":value}) }
func authenticate(next http.HandlerFunc) http.HandlerFunc { return func(w http.ResponseWriter, r *http.Request) { tokenString := r.Header.Get("Authorization"); if len(tokenString) < 8 || tokenString[:7] != "Bearer " { http.Error(w, "unauthorized", 401); return }; parsed, err := jwt.ParseWithClaims(tokenString[7:], &claims{}, func(t *jwt.Token) (any, error) { if t.Method != jwt.SigningMethodHS256 { return nil, errors.New("unexpected signing method") }; return secret(), nil }); if err != nil || !parsed.Valid { http.Error(w, "unauthorized", 401); return }; c, ok := parsed.Claims.(*claims); if !ok || c.UserID == 0 { http.Error(w, "unauthorized", 401); return }; next(w, r.WithContext(withUser(r.Context(), c.UserID))) } }

type contextKey string
func withUser(ctx context.Context, id uint64) context.Context { return context.WithValue(ctx, contextKey("user_id"), id) }
func order(w http.ResponseWriter, r *http.Request) { userID := r.Context().Value(contextKey("user_id")).(uint64); var in struct { Price float64 `json:"price"`; Quantity float64 `json:"quantity"`; Side uint8 `json:"side"`; Type uint8 `json:"type"` }; if json.NewDecoder(http.MaxBytesReader(w, r.Body, 4096)).Decode(&in) != nil || in.Price <= 0 || in.Quantity <= 0 || in.Side > 1 || in.Type > 1 { http.Error(w, "invalid order", 400); return }; price, quantity := uint64(in.Price*scale), uint64(in.Quantity*scale); write, read := atomic.LoadUint32(&buffer.WriteIndex), atomic.LoadUint32(&buffer.ReadIndex); if write-read >= capacity { http.Error(w, "queue full", 503); return }; id := atomic.AddUint64(&nextID, 1); buffer.Queue[write%capacity] = orderPacket{OrderID:id, UserID:userID, Price:price, Quantity:quantity, Side:in.Side, Type:in.Type}; atomic.StoreUint32(&buffer.WriteIndex, write+1); json.NewEncoder(w).Encode(map[string]string{"status":"queued", "order_id":strconv.FormatUint(id,10)}) }

var depthMu sync.RWMutex
var bids, asks = map[uint64]uint64{}, map[uint64]uint64{}
func depthReader() { for { read, write := atomic.LoadUint32(&buffer.DepthReadIndex), atomic.LoadUint32(&buffer.DepthWriteIndex); if read == write { time.Sleep(time.Millisecond); continue }; d := buffer.DepthQueue[read%capacity]; atomic.StoreUint32(&buffer.DepthReadIndex, read+1); depthMu.Lock(); book := asks; if d.Side == 0 { book = bids }; if d.Quantity == 0 { delete(book,d.Price) } else { book[d.Price] = d.Quantity }; snapshot := makeSnapshot(); depthMu.Unlock(); clients.RLock(); for c := range clients.m { if err := c.WriteMessage(websocket.TextMessage, snapshot); err != nil { _ = c.Close(); deleteClient(c) } }; clients.RUnlock() } }
func makeSnapshot() []byte { return jsonBytes(map[string]any{"event":"orderbook_l2_update", "bids":bids, "asks":asks, "time":time.Now().UnixMilli()}) }
func jsonBytes(v any) []byte { b, _ := json.Marshal(v); return b }
func depth(w http.ResponseWriter, r *http.Request) { c, err := upgrader.Upgrade(w,r,nil); if err != nil { return }; clients.Lock(); clients.m[c] = struct{}{}; clients.Unlock(); depthMu.RLock(); _ = c.WriteMessage(websocket.TextMessage, makeSnapshot()); depthMu.RUnlock(); for { if _, _, err := c.ReadMessage(); err != nil { deleteClient(c); return } } }
func deleteClient(c *websocket.Conn) { clients.Lock(); delete(clients.m,c); clients.Unlock(); _ = c.Close() }
func main() { _ = fmt.Sprintf(""); if err := initSharedMemory(); err != nil { panic(err) }; mux := http.NewServeMux(); mux.HandleFunc("/api/v1/auth/register", register); mux.HandleFunc("/api/v1/auth/login", login); mux.HandleFunc("/api/v1/order/submit", authenticate(order)); mux.HandleFunc("/ws/orderbook", depth); go depthReader(); secret(); if err := http.ListenAndServe("127.0.0.1:8080", mux); err != nil { panic(err) } }
