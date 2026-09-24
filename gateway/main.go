package main

import (
  "encoding/json"
  "fmt"
  "net/http"
  "os"
  "sync/atomic"
  "syscall"
  "unsafe"
)

const capacity = 4096
const scale = 100000000

type orderPacket struct { OrderID, UserID, Price, Quantity uint64; Side, Type uint8; Reserved [6]byte; Padding [24]byte }
type sharedBuffer struct { WriteIndex uint32; ReadIndex uint32; Padding [56]byte; Queue [capacity]orderPacket }
type orderRequest struct { UserID uint64 `json:"user_id"`; Price float64 `json:"price"`; Quantity float64 `json:"quantity"`; Side uint8 `json:"side"`; Type uint8 `json:"type"` }

var buffer *sharedBuffer
var nextID uint64

func initSharedMemory() error {
  fd, err := os.OpenFile("/dev/shm/varianth_exchange_shm", os.O_RDWR, 0600)
  if err != nil { return err }
  defer fd.Close()
  info, err := fd.Stat(); if err != nil { return err }
  data, err := syscall.Mmap(int(fd.Fd()), 0, int(info.Size()), syscall.PROT_READ|syscall.PROT_WRITE, syscall.MAP_SHARED)
  if err != nil { return err }
  buffer = (*sharedBuffer)(unsafe.Pointer(&data[0]))
  return nil
}

func submit(w http.ResponseWriter, r *http.Request) {
  if r.Method != http.MethodPost { http.Error(w, "method not allowed", 405); return }
  var req orderRequest
  dec := json.NewDecoder(r.Body); dec.DisallowUnknownFields()
  if err := dec.Decode(&req); err != nil || req.UserID == 0 || req.Price <= 0 || req.Quantity <= 0 || req.Side > 1 || req.Type > 1 { http.Error(w, "invalid order", 400); return }
  price := uint64(req.Price * scale); quantity := uint64(req.Quantity * scale)
  if price == 0 || quantity == 0 { http.Error(w, "invalid scaled order", 400); return }
  write := atomic.LoadUint32(&buffer.WriteIndex); read := atomic.LoadUint32(&buffer.ReadIndex)
  if write-read >= capacity { http.Error(w, "order queue full", 503); return }
  id := atomic.AddUint64(&nextID, 1)
  buffer.Queue[write%capacity] = orderPacket{OrderID:id, UserID:req.UserID, Price:price, Quantity:quantity, Side:req.Side, Type:req.Type}
  atomic.StoreUint32(&buffer.WriteIndex, write+1)
  w.Header().Set("Content-Type", "application/json")
  json.NewEncoder(w).Encode(map[string]any{"status":"queued", "order_id":fmt.Sprint(id)})
}

func main() {
  if err := initSharedMemory(); err != nil { panic(err) }
  mux := http.NewServeMux(); mux.HandleFunc("/api/v1/order/submit", submit)
  server := &http.Server{Addr:"127.0.0.1:8080", Handler:mux}
  if err := server.ListenAndServe(); err != nil { panic(err) }
}
